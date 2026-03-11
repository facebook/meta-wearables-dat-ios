# Meta Wearables DAT SDK — AI Instructions

> Full API reference: [https://wearables.developer.meta.com/llms.txt?full=true](https://wearables.developer.meta.com/llms.txt?full=true)
>
> Developer docs: [https://wearables.developer.meta.com/docs/develop/](https://wearables.developer.meta.com/docs/develop/)


# DAT SDK Conventions (iOS)

## Architecture

The SDK is organized into three modules:
- **MWDATCore**: Device discovery, registration, permissions, device selectors
- **MWDATCamera**: StreamSession, VideoFrame, photo capture
- **MWDATMockDevice**: MockDeviceKit for testing without hardware

## Swift Patterns

- Use `async/await` for all SDK operations — the SDK is fully async
- Use `AsyncSequence` / publisher `.listen {}` for observing streams
- Annotate UI-updating code with `@MainActor`
- Never block the main thread with frame processing
- Handle errors with do/catch — the SDK throws typed errors

## Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Entry point | `Wearables.shared` | `Wearables.shared.startRegistration()` |
| Sessions | `*Session` | `StreamSession`, `DeviceStateSession` |
| Selectors | `*DeviceSelector` | `AutoDeviceSelector`, `SpecificDeviceSelector` |
| Config | `*Config` | `StreamSessionConfig` |
| Publishers | `*Publisher` | `statePublisher`, `videoFramePublisher` |

## Imports

```swift
import MWDATCore    // Registration, devices, permissions
import MWDATCamera  // StreamSession, VideoFrame, photo capture
```

For testing:
```swift
import MWDATMockDevice  // MockDeviceKit, MockRaybanMeta, MockCameraKit
```

## Key Types

- `Wearables` — SDK entry point. Call `Wearables.configure()` at launch, then use `Wearables.shared`
- `StreamSession` — Camera streaming session. Create with config + device selector
- `VideoFrame` — Individual video frame with `.makeUIImage()` convenience
- `AutoDeviceSelector` — Automatically selects the best available device
- `SpecificDeviceSelector` — Selects a specific device by identifier
- `StreamSessionConfig` — Configure video codec, resolution, frame rate
- `MockDeviceKit` — Factory for creating simulated devices in tests

## Error Handling

```swift
do {
    try Wearables.configure()
} catch {
    // Handle configuration error
}

do {
    try Wearables.shared.startRegistration()
} catch {
    // Handle registration error
}
```

## Links

- [iOS API Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.5)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [GitHub Repository](https://github.com/facebook/meta-wearables-dat-ios)


# Camera Streaming (iOS)

Guide for implementing camera streaming and photo capture with the DAT SDK.

## Key concepts

- **StreamSession**: Main interface for camera streaming
- **VideoFrame**: Individual video frames — call `.makeUIImage()` to render
- **StreamSessionConfig**: Configure resolution, frame rate, and codec
- **PhotoData**: Still image captured from glasses

## Creating a StreamSession

```swift
import MWDATCamera
import MWDATCore

let wearables = Wearables.shared
let deviceSelector = AutoDeviceSelector(wearables: wearables)

let config = StreamSessionConfig(
    videoCodec: .raw,
    resolution: .medium,  // 504x896
    frameRate: 24
)

let session = StreamSession(
    streamSessionConfig: config,
    deviceSelector: deviceSelector
)
```

### Resolution options

| Resolution | Size |
|-----------|------|
| `.high` | 720 x 1280 |
| `.medium` | 504 x 896 |
| `.low` | 360 x 640 |

### Frame rate options

Valid values: `2`, `7`, `15`, `24`, `30` FPS.

Lower resolution and frame rate yield higher visual quality due to less Bluetooth compression.

## Observing stream state

`StreamSessionState` transitions: `stopping` → `stopped` → `waitingForDevice` → `starting` → `streaming` → `paused`

```swift
let stateToken = session.statePublisher.listen { state in
    Task { @MainActor in
        switch state {
        case .streaming:
            // Stream is active, frames are flowing
        case .waitingForDevice:
            // Waiting for glasses to connect
        case .stopped:
            // Stream ended — release resources
        case .paused:
            // Temporarily suspended — keep connection, wait
        default:
            break
        }
    }
}
```

## Receiving video frames

```swift
let frameToken = session.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.previewImage = image
    }
}
```

## Starting and stopping

```swift
// Start streaming
Task { await session.start() }

// Stop streaming
Task { await session.stop() }
```

## Photo capture

Capture a still photo while streaming:

```swift
// Listen for photo data
let photoToken = session.photoDataPublisher.listen { photoData in
    let imageData = photoData.data
    // Convert to UIImage or save
}

// Trigger capture
session.capturePhoto(format: .jpeg)
```

## Bandwidth and quality

Resolution and frame rate are constrained by Bluetooth Classic bandwidth. The SDK automatically reduces quality when bandwidth is limited:
1. First lowers resolution (e.g., High → Medium)
2. Then reduces frame rate (e.g., 30 → 24), never below 15 FPS

Request lower settings for higher visual quality per frame.

## Device selection

Use `AutoDeviceSelector` to let the SDK pick the best device, or `SpecificDeviceSelector` for a known device:

```swift
// Auto-select
let auto = AutoDeviceSelector(wearables: wearables)

// Specific device
let specific = SpecificDeviceSelector(deviceIdentifier: deviceId)
```

## Links

- [StreamSession API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.5/mwdatcamera_streamsession)
- [StreamSessionConfig API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.5/mwdatcamera_streamsessionconfig)
- [Integration guide](https://wearables.developer.meta.com/docs/build-integration-ios)


# Debugging (iOS)

Guide for diagnosing common issues with DAT SDK integrations.

## Quick diagnosis

```text
Device not connecting?
│
├── Is Developer Mode enabled? → Enable in Meta AI app settings
│
├── Is device registered? → Check registration state
│
├── Is device in range? → Bluetooth on, glasses powered on
│
├── Is the app registered? → Check registrationStateStream()
│
└── Stream stuck in waitingForDevice? → Check device availability
```

## Developer Mode

Developer Mode must be enabled for 3P apps to access device features.

### Enabling Developer Mode

1. Open Meta AI app on phone
2. Go to Settings → (Your connected glasses)
3. Find "Developer Mode" toggle
4. Toggle ON
5. Device may restart

### Symptoms of Developer Mode disabled

- Registration completes but device never connects
- StreamSession stuck in `waitingForDevice`
- Permission requests fail or never appear

### Common gotchas

- Developer Mode toggles **off** after firmware updates — re-enable it
- Developer Mode is per-device — enable for each glasses pair
- Some features need additional permissions beyond Developer Mode

## StreamSession state issues

### Expected flow

```text
stopped → waitingForDevice → starting → streaming → stopped
```

### Stuck in waitingForDevice

- Device not in range or not connected
- Device not reporting availability
- DeviceSelector not matching any device

### Unexpected stop

- Device disconnected (out of range, battery died)
- Channel closed by device
- Error in frame processing

## Version compatibility

Ensure compatible versions of SDK, Meta AI app, and glasses firmware:

| SDK | Meta AI App | Ray-Ban Meta | Meta Ray-Ban Display |
|-----|-------------|--------------|----------------------|
| 0.5.0 | Check [version dependencies](https://wearables.developer.meta.com/docs/version-dependencies) | Check docs | Check docs |
| 0.4.0 | V254 | V20 | V21 |
| 0.3.0 | V249 | V20 | — |

## Known issues

| Issue | Workaround |
|-------|-----------|
| No internet → registration fails | Internet required for registration |
| Streams started with glasses doffed pause when donned | Unpause by tapping side of glasses |
| `DeviceStateSession` unreliable with camera stream | Avoid using `DeviceStateSession` |
| [iOS] Meta Ray-Ban Display: no audio feedback on pause/resume | Will be fixed in future release |

## Adding debug logging

```swift
import os

private let logger = Logger(subsystem: "com.yourapp", category: "Wearables")

// In your streaming code:
logger.debug("Stream state changed to: \(state)")
logger.error("Stream error: \(error)")
```

## Checklist

- [ ] Developer Mode enabled in Meta AI app
- [ ] Meta AI app updated to compatible version
- [ ] Glasses firmware updated to compatible version
- [ ] Internet connection available for registration
- [ ] Bluetooth enabled on phone
- [ ] Correct URL scheme configured in Info.plist
- [ ] Background modes enabled (bluetooth-peripheral, external-accessory)

## Links

- [Known issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [Troubleshooting discussions](https://github.com/facebook/meta-wearables-dat-ios/discussions)


# Getting Started with DAT SDK (iOS)

Guide for setting up the Meta Wearables Device Access Toolkit in an iOS app.

## Prerequisites

- Xcode 15.0+, iOS 16.0+ deployment target
- Meta AI companion app installed on test device
- Ray-Ban Meta glasses or Meta Ray-Ban Display glasses (or use MockDeviceKit for development)
- Developer Mode enabled in Meta AI app (Settings > Your glasses > Developer Mode)

## Step 1: Add the SDK via Swift Package Manager

1. In Xcode, select **File** > **Add Package Dependencies...**
2. Enter `https://github.com/facebook/meta-wearables-dat-ios`
3. Select a [version](https://github.com/facebook/meta-wearables-dat-ios/tags)
4. Add `MWDATCore` and `MWDATCamera` to your target

## Step 2: Configure Info.plist

Add these required entries to your `Info.plist`:

```xml
<!-- URL scheme for Meta AI callbacks -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myexampleapp</string>
    </array>
  </dict>
</array>

<!-- Allow Meta AI to callback -->
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>fb-viewapp</string>
</array>

<!-- External accessory protocol -->
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.meta.ar.wearable</string>
</array>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-peripheral</string>
  <string>external-accessory</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta Wearables</string>

<!-- DAT configuration -->
<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key>
  <string>myexampleapp://</string>
  <key>MetaAppID</key>
  <string>0</string>
</dict>
```

Replace `myexampleapp` with your app's URL scheme. Use `0` for `MetaAppID` during development with Developer Mode.

## Step 3: Initialize the SDK

Call `Wearables.configure()` once at app launch:

```swift
import MWDATCore

@main
struct MyApp: App {
    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Step 4: Handle URL callbacks

Your app must handle the URL callback from Meta AI after registration:

```swift
.onOpenURL { url in
    Task {
        _ = try? await Wearables.shared.handleUrl(url)
    }
}
```

## Step 5: Register with Meta AI

```swift
func startRegistration() throws {
    try Wearables.shared.startRegistration()
}
```

Observe registration state:

```swift
Task {
    for await state in Wearables.shared.registrationStateStream() {
        // Update UI based on registration state
    }
}
```

## Step 6: Start streaming

```swift
import MWDATCamera

let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
let config = StreamSessionConfig(
    videoCodec: .raw,
    resolution: .low,
    frameRate: 24
)
let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

// Observe frames
let frameToken = session.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.currentFrame = image
    }
}

// Start
Task { await session.start() }
```

## Next steps

- [Camera Streaming](camera-streaming.md) — Resolution, frame rate, photo capture
- [MockDevice Testing](mockdevice-testing.md) — Test without hardware
- [Session Lifecycle](session-lifecycle.md) — Handle pause/resume/stop
- [Permissions](permissions-registration.md) — Camera permission flows
- [Full documentation](https://wearables.developer.meta.com/docs/develop/)


# MockDevice Testing (iOS)

Guide for testing DAT SDK integrations without physical Meta glasses.

## Overview

MockDeviceKit simulates Meta glasses behavior for development and testing. It provides:
- `MockDeviceKit` — Entry point for creating simulated devices
- `MockRaybanMeta` — Simulated Ray-Ban Meta glasses
- `MockCameraKit` — Simulated camera with configurable video feed and photo capture

## Setup

Add `MWDATMockDevice` to your target via Swift Package Manager (it's included in the `meta-wearables-dat-ios` package).

```swift
import MWDATMockDevice
```

## Creating a mock device

```swift
let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
```

## Simulating device states

```swift
// Simulate glasses lifecycle
await mockDevice.powerOn()
await mockDevice.unfold()
await mockDevice.don()    // Simulate wearing the glasses

// Later...
await mockDevice.doff()   // Simulate removing
await mockDevice.fold()
await mockDevice.powerOff()
```

## Setting up mock camera feeds

### Video streaming

```swift
let camera = mockDevice.getCameraKit()
await camera.setCameraFeed(fileURL: videoURL)
```

### Photo capture

```swift
let camera = mockDevice.getCameraKit()
await camera.setCapturedImage(fileURL: imageURL)
```

## Writing tests with MockDeviceKit

Create a reusable test base class:

```swift
import XCTest
import MetaWearablesDAT

@MainActor
class MockDeviceKitTestCase: XCTestCase {
    private var mockDevice: MockRaybanMeta?
    private var cameraKit: MockCameraKit?

    override func setUp() async throws {
        try await super.setUp()
        try? Wearables.configure()
        mockDevice = MockDeviceKit.shared.pairRaybanMeta()
        cameraKit = mockDevice?.getCameraKit()
    }

    override func tearDown() async throws {
        MockDeviceKit.shared.pairedDevices.forEach { device in
            MockDeviceKit.shared.unpairDevice(device)
        }
        mockDevice = nil
        cameraKit = nil
        try await super.tearDown()
    }
}
```

## Using MockDeviceKit in the CameraAccess sample

The CameraAccess sample app includes a Debug menu for MockDeviceKit:

1. Tap the **Debug icon** to open the MockDeviceKit menu
2. Tap **Pair RayBan Meta** to create a simulated device
3. Use **PowerOn**, **Unfold**, **Don** to simulate glasses states
4. Select video/image files to configure mock camera feeds
5. Start streaming to see simulated frames

## Supported media formats

| Type | Formats |
|------|---------|
| Video | h.265 (HEVC) |
| Image | JPEG, PNG |

## Links

- [Mock Device Kit overview](https://wearables.developer.meta.com/docs/mock-device-kit)
- [iOS testing guide](https://wearables.developer.meta.com/docs/testing-mdk-ios)


# Permissions & Registration (iOS)

Guide for app registration and camera permission flows in the DAT SDK.

## Overview

The DAT SDK separates two concepts:
1. **Registration** — Your app registers with Meta AI to become a permitted integration
2. **Device permissions** — After registration, request specific device permissions (e.g., camera)

All permission grants occur through the Meta AI companion app.

## Registration flow

### Start registration

```swift
func startRegistration() throws {
    try Wearables.shared.startRegistration()
}
```

This opens the Meta AI app where the user approves your app. Meta AI then calls back via your URL scheme.

### Handle the callback

```swift
.onOpenURL { url in
    Task {
        _ = try? await Wearables.shared.handleUrl(url)
    }
}
```

### Observe registration state

```swift
Task {
    for await state in Wearables.shared.registrationStateStream() {
        switch state {
        case .registered:
            // App is registered, can request permissions
        case .unregistered:
            // App is not registered
        case .registering:
            // Registration in progress
        }
    }
}
```

### Unregister

```swift
func startUnregistration() throws {
    try Wearables.shared.startUnregistration()
}
```

## Camera permissions

### Check permission status

```swift
let status = try await Wearables.shared.checkPermissionStatus(.camera)
```

### Request permission

```swift
let status = try await Wearables.shared.requestPermission(.camera)
```

The SDK opens Meta AI for the user to grant access. Users can choose:
- **Allow once** — temporary, single-session grant
- **Allow always** — persistent grant

## Multi-device behavior

Users can link multiple glasses to Meta AI. The SDK handles this transparently:
- Permission granted on **any** linked device means your app has access
- You don't need to track which device has permissions
- If all devices disconnect, permissions become unavailable

## Developer Mode vs Production

| Mode | Registration behavior |
|------|----------------------|
| Developer Mode | Registration always allowed (use `MetaAppID` = `0`) |
| Production | Users must be in proper release channel |

For production, get your `APPLICATION_ID` from the [Wearables Developer Center](https://wearables.developer.meta.com/).

## Prerequisites

- Registration requires an internet connection
- Meta AI companion app must be installed
- For Developer Mode: enable in Meta AI > Settings > Your glasses > Developer Mode

## Links

- [Permissions documentation](https://wearables.developer.meta.com/docs/permissions-requests)
- [Getting started guide](https://wearables.developer.meta.com/docs/getting-started-toolkit)
- [Manage projects](https://wearables.developer.meta.com/docs/manage-projects)


# Sample App Guide (iOS)

Guide for building a complete DAT SDK app with camera streaming and photo capture.

## Overview

This guide walks through building an iOS app that connects to Meta glasses, streams video, and captures photos. Use it as a reference alongside the [CameraAccess sample](https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples).

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
│   └── StreamSessionViewModel.swift # Streaming, photo capture
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
                    Task {
                        _ = try? await Wearables.shared.handleUrl(url)
                    }
                }
        }
    }
}
```

## Wearables ViewModel

```swift
import MWDATCore

@MainActor
class WearablesViewModel: ObservableObject {
    @Published var registrationState: String = "Unknown"
    @Published var devices: [DeviceIdentifier] = []

    private let wearables = Wearables.shared

    func observeState() {
        Task {
            for await state in wearables.registrationStateStream() {
                self.registrationState = "\(state)"
            }
        }
        Task {
            for await devices in wearables.devicesStream() {
                self.devices = devices.map { $0.identifier }
            }
        }
    }

    func register() {
        try? wearables.startRegistration()
    }

    func unregister() {
        try? wearables.startUnregistration()
    }
}
```

## Stream ViewModel

```swift
import MWDATCamera
import MWDATCore

@MainActor
class StreamSessionViewModel: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var streamState: String = "Stopped"
    @Published var capturedPhoto: Data?

    private var session: StreamSession?

    func startStream() {
        let wearables = Wearables.shared
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .medium,
            frameRate: 24
        )
        let selector = AutoDeviceSelector(wearables: wearables)
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        self.session = session

        _ = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.streamState = "\(state)"
            }
        }

        _ = session.videoFramePublisher.listen { [weak self] frame in
            guard let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self?.currentFrame = image
            }
        }

        _ = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                self?.capturedPhoto = photoData.data
            }
        }

        Task { await session.start() }
    }

    func stopStream() {
        Task { await session?.stop() }
        session = nil
    }

    func capturePhoto() {
        session?.capturePhoto(format: .jpeg)
    }
}
```

## Testing with MockDeviceKit

Add mock device support to develop without glasses:

```swift
import MWDATMockDevice

func setupMockDevice() async {
    let device = MockDeviceKit.shared.pairRaybanMeta()
    await device?.powerOn()
    await device?.unfold()
    await device?.don()

    // Set up mock camera feed
    if let videoURL = Bundle.main.url(forResource: "test_video", withExtension: "mov") {
        let camera = device?.getCameraKit()
        await camera?.setCameraFeed(fileURL: videoURL)
    }
}
```

## Allowed dependencies

Your DAT app should only depend on:
- `MWDATCore` — always required
- `MWDATCamera` — for camera streaming
- `MWDATMockDevice` — for testing (can be test-only dependency)

## Links

- [CameraAccess sample](https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples)
- [Full integration guide](https://wearables.developer.meta.com/docs/build-integration-ios)
- [Developer documentation](https://wearables.developer.meta.com/docs/develop/)


# Session Lifecycle (iOS)

Guide for managing device session states in DAT SDK integrations.

## Overview

The DAT SDK runs work inside sessions. Meta glasses expose two experience types:
- **Device sessions** — sustained access to device sensors and outputs
- **Transactions** — short, system-owned interactions (notifications, "Hey Meta")

Your app observes session state changes — the device decides when to transition.

## Session states

| State | Meaning | App action |
|-------|---------|------------|
| `STOPPED` | Session inactive, not reconnecting | Free resources, wait for user action |
| `RUNNING` | Session active, streaming data | Perform live work |
| `PAUSED` | Temporarily suspended | Hold work, may resume |

## Observing session state

```swift
Task {
    for await state in Wearables.shared.deviceSessionStateStream(for: deviceId) {
        switch state {
        case .running:
            // Confirm UI shows session is live
        case .paused:
            // Keep connection, wait for running or stopped
        case .stopped:
            // Release resources, allow user to restart
        }
    }
}
```

## StreamSession state transitions

StreamSession has its own state flow:

```text
stopped → waitingForDevice → starting → streaming → paused → stopped
```

```swift
let token = session.statePublisher.listen { state in
    Task { @MainActor in
        // React to state changes
    }
}
```

## Common transitions

The device changes session state when:
- User performs a system gesture that opens another experience
- Another app starts a device session
- User removes or folds the glasses (Bluetooth disconnects)
- User removes the app from Meta AI companion app
- Connectivity between companion app and glasses drops

## Pause and resume

When a session is paused:
- The device keeps the connection alive
- Streams stop delivering data
- The device may resume by returning to `RUNNING`

Your app should **not** attempt to restart while paused — wait for `RUNNING` or `STOPPED`.

## Device availability

Monitor device availability to know when sessions can start:

```swift
Task {
    for await devices in Wearables.shared.devicesStream() {
        // Update list of available glasses
    }
}
```

Key behaviors:
- Closing hinges disconnects Bluetooth → forces `STOPPED`
- Opening hinges restores Bluetooth but does **not** restart sessions
- Start a new session after the device becomes available again

## Implementation checklist

- [ ] Handle all session states (`RUNNING`, `PAUSED`, `STOPPED`)
- [ ] Monitor device availability before starting work
- [ ] Release resources only after `STOPPED`
- [ ] Don't infer transition causes — rely only on observable state
- [ ] Don't restart during `PAUSED` — wait for system to resume or stop

## Links

- [Session lifecycle documentation](https://wearables.developer.meta.com/docs/lifecycle-events)
