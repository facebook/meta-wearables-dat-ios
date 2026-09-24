---
name: sample-app-guide
description: Building a complete DAT app with camera streaming and photo capture
---

# Sample App Guide (iOS)

Build an iOS DAT app with camera streaming and photo capture.

This walkthrough covers app setup, registration, streaming, and capture. Pair it with the [CameraAccess sample](https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples).

## Project setup

1. Create a new Xcode project (SwiftUI App)
2. Add the SDK via SPM: `https://github.com/facebook/meta-wearables-dat-ios`
3. Add `MWDATCore`, `MWDATCamera`, and `MWDATMockDevice` to your target
4. Configure `Info.plist` (see [Getting Started](getting-started.md))

## App architecture

A typical DAT app has these components:

```text
MyDATApp/
├── MyDATApp.swift              # App entry point, SDK init
├── ViewModels/
│   ├── WearablesViewModel.swift    # Registration, device management
│   └── StreamViewModel.swift # Streaming, photo capture
└── Views/
    ├── MainAppView.swift           # Navigation
    ├── RegistrationView.swift      # Registration UI
    └── StreamView.swift            # Video preview, capture button
```

## SDK initialization

```swift
import MWDATCore

@main
struct MyDATApp: App {
    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Wearables SDK configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .onOpenURL { url in
                    guard
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                    else {
                        return
                    }
                    Task {
                        _ = try? await Wearables.shared.handleUrl(url)
                    }
                }
        }
    }
}
```

## Wearables ViewModel

`devicesStream()` yields `[DeviceIdentifier]` (a `[String]`), not device objects.
Resolve each identifier with `wearables.deviceForIdentifier(_:)` when you need
`nameOrId()`, `deviceType()`, `linkState`, or `compatibility()`.

```swift
import MWDATCore

@MainActor
class WearablesViewModel: ObservableObject {
    @Published var registrationState: RegistrationState
    @Published var devices: [DeviceIdentifier] = []

    private let wearables = Wearables.shared

    init() {
        registrationState = Wearables.shared.registrationState
    }

    func observeState() {
        Task {
            for await state in wearables.registrationStateStream() {
                self.registrationState = state
            }
        }
        Task {
            for await deviceIds in wearables.devicesStream() {
                self.devices = deviceIds
            }
        }
    }

    func register() async {
        try? await wearables.startRegistration()
    }

    func unregister() async {
        try? await wearables.startUnregistration()
    }
}
```

## Stream ViewModel

```swift
import MWDATCamera
import MWDATCore

@MainActor
class StreamViewModel: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var streamState: String = "Stopped"
    @Published var capturedPhoto: Data?

    private let wearables = Wearables.shared
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: Stream?

    func startStream() async {
        let config = StreamConfiguration(
            videoCodec: .raw,
            resolution: .medium,
            frameRate: 24
        )
        let selector = AutoDeviceSelector(wearables: wearables)

        do {
            let deviceSession = try wearables.createSession(deviceSelector: selector)
            try deviceSession.start()
            // Wait for the device session to reach the started state
            for await state in deviceSession.stateStream() {
                if state == .started { break }
            }
            guard let camera = try deviceSession.addCamera(config: config) else { return }
            self.deviceSession = deviceSession
            self.camera = camera
            self.stream = camera.stream
        } catch {
            return
        }

        guard let stream else { return }

        _ = stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.streamState = "\(state)"
            }
        }

        _ = stream.videoFramePublisher.listen { [weak self] frame in
            guard let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self?.currentFrame = image
            }
        }

        _ = stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                self?.capturedPhoto = photoData.data
            }
        }

        stream.start()
    }

    func stopStream() {
        // Stopping the camera cascades to its stream child
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil
    }

    func capturePhoto() {
        stream?.capturePhoto(format: .jpeg)
    }
}
```

## Behaviors the CameraAccess sample also covers

- **Two explicit steps.** "Start Session" creates and starts the `DeviceSession`; "Preview" adds the `Camera` and starts the stream. Stopping the preview leaves the session connected so the user can start it again without re-creating the session.
- **Bind the UI to the SDK's own states.** Mirror `DeviceSessionState` and `StreamState` instead of maintaining a parallel state machine, and show a busy indicator while `starting`, `waitingForDevice`, or `stopping`.
- **Background handling.** On `UIApplication.didEnterBackgroundNotification`, end the session. Suppress the teardown errors that the SDK emits during that intentional stop so the user does not see a false failure on return.
- **Update prompts.** Watch `device.compatibility()` with `device.addCompatibilityListener`; on `.deviceUpdateRequired`, offer `Wearables.shared.openFirmwareUpdate()`. When session start reports `DeviceSessionError.datAppOnTheGlassesUpdateRequired`, offer `Wearables.shared.openDATGlassesAppUpdate()`.
- **Single error surface.** Present `error.localizedDescription` from `session.errorPublisher` and `stream.errorPublisher` in one alert rather than an app-maintained error map.

## Testing with MockDeviceKit

Add mock device support to develop without glasses:

```swift
import MWDATMockDevice

func setupMockDevice() async {
    let mockDeviceKit = MockDeviceKit.shared
    mockDeviceKit.enable()

    guard let device = try? mockDeviceKit.pairGlasses(model: .rayBanMeta) else { return }
    device.powerOn()
    device.unfold()
    device.don()

    if let videoURL = Bundle.main.url(forResource: "test_video", withExtension: "mp4") {
        let camera = device.services.camera
        camera.setCameraFeed(fileURL: videoURL)
    }
}

func tearDownMockDevice() {
    MockDeviceKit.shared.disable()
}
```

## Allowed dependencies

Your DAT app should only depend on:
- `MWDATCore` — always required
- `MWDATCamera` — for camera streaming
- `MWDATMockDevice` — for testing (can be test-only dependency)
- `MWDATDisplay` — for Display experiences

## Links

- [CameraAccess sample](https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples)
- [Full integration guide](https://wearables.developer.meta.com/docs/build-integration-ios)
- [Developer documentation](https://wearables.developer.meta.com/docs/develop/)
