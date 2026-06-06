# Meta Wearables DAT SDK — AI Instructions

> Full API reference: [https://wearables.developer.meta.com/llms.txt?full=true](https://wearables.developer.meta.com/llms.txt?full=true)
>
> DAT docs MCP: [https://mcp.facebook.com/wearables_dat](https://mcp.facebook.com/wearables_dat)
>
> Developer docs: [https://wearables.developer.meta.com/docs/develop/](https://wearables.developer.meta.com/docs/develop/)

# DAT SDK Conventions (iOS)

## Architecture

The SDK is organized into four modules:
- **MWDATCore**: Device discovery, registration, permissions, device selectors
- **MWDATCamera**: Stream, VideoFrame, photo capture
- **MWDATDisplay**: Display capability, display UI components, icons, images, buttons, video
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
| Device sessions | `*Session` | `DeviceSession` |
| Capabilities | Named by function | `Stream` |
| Selectors | `*DeviceSelector` | `AutoDeviceSelector`, `SpecificDeviceSelector` |
| Config | `*Configuration` | `StreamConfiguration` |
| Publishers | `*Publisher` | `statePublisher`, `videoFramePublisher` |

## Imports

```swift
import MWDATCore    // Registration, devices, permissions
import MWDATCamera  // Stream, VideoFrame, photo capture
import MWDATDisplay // Display, FlexBox, Text, Button, Image, Icon, VideoPlayer
```

For testing:
```swift
import MWDATMockDevice  // MockDeviceKit, MockRaybanMeta, MockCameraKit
```

## Key Types

- `Wearables` — SDK entry point. Call `Wearables.configure()` at launch, then use `Wearables.shared`
- `Stream` — Camera streaming session. Create with config + device selector
- `Display` — Display capability attached to a started DeviceSession
- `VideoFrame` — Individual video frame with `.makeUIImage()` convenience
- `AutoDeviceSelector` — Automatically selects the best available device
- `SpecificDeviceSelector` — Selects a specific device by identifier
- `StreamConfiguration` — Configure video codec, resolution, frame rate
- `MockDeviceKit` — Factory for creating simulated devices in tests

## Error Handling

```swift
do {
    try Wearables.configure()
} catch {
    // Handle configuration error
}

do {
    try await Wearables.shared.startRegistration()
} catch {
    // Handle registration error
}
```

## Build and Test

```bash
# Install dependencies via Swift Package Manager
# In Xcode: File > Add Package Dependencies > enter repo URL

# Build from command line
xcodebuild -scheme MWDATCore -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme MWDATCoreTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

For sample apps:
```bash
# Open the sample app workspace
open ExternalSampleApps/CameraAccess/CameraAccess.xcodeproj

# Build and run on simulator (uses MockDeviceKit - no glasses needed)
xcodebuild -scheme CameraAccess -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Development Workflow

1. **Add SDK** via Swift Package Manager (SPM) in Xcode
2. **Import modules** (`MWDATCore`, `MWDATCamera`, `MWDATDisplay` when rendering Display content)
3. **Configure** at app launch: `try Wearables.configure()`
4. **Build** with Xcode or `xcodebuild`
5. **Test** with MockDeviceKit - no physical glasses required
6. **Debug** using Xcode console for SDK logs

## Live docs search

If your editor supports remote MCP servers, connect `https://mcp.facebook.com/wearables_dat` and use `search_dat_docs` for current DAT setup, session lifecycle, camera streaming, MockDeviceKit, permissions, and exact API symbols.

Use `llms.txt` when your tool only supports static reference context.

## Links

- [iOS API Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.7)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [GitHub Repository](https://github.com/facebook/meta-wearables-dat-ios)

# Camera Streaming (iOS)

Guide for implementing camera streaming and photo capture with the DAT SDK.

## Key concepts

- **Stream**: Main interface for camera streaming
- **VideoFrame**: Individual video frames — call `.makeUIImage()` to render
- **StreamConfiguration**: Configure resolution, frame rate, and codec
- **PhotoData**: Still image captured from glasses

## Creating a DeviceSession

```swift
import MWDATCamera
import MWDATCore

let wearables = Wearables.shared
let deviceSelector = AutoDeviceSelector(wearables: wearables)
// Or for a specific device: SpecificDeviceSelector(device: deviceId)
let deviceSession = try wearables.createSession(deviceSelector: deviceSelector)
try deviceSession.start()

// Wait for the device session to reach the started state
for await state in deviceSession.stateStream() {
    if state == .started { break }
}
```

## Adding a Stream

Once the `DeviceSession` is started, add a `Stream` capability:

```swift
let config = StreamConfiguration(
    videoCodec: .raw,
    resolution: .medium,  // 504x896
    frameRate: 24
)

guard let stream = try deviceSession.addStream(config: config) else {
    // DeviceSession must be in the started state before adding a stream
    return
}
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

`StreamState` transitions: `stopping` → `stopped` → `waitingForDevice` → `starting` → `streaming` → `paused`

```swift
let stateToken = stream.statePublisher.listen { state in
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
let frameToken = stream.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.previewImage = image
    }
}
```

## Starting and stopping

```swift
// Start the stream capability
Task { await stream.start() }

// Stop streaming
Task { await stream.stop() }

// Stop the parent device session when you're done with all capabilities
deviceSession.stop()
```

## Photo capture

Capture a still photo while streaming:

```swift
// Listen for photo data
let photoToken = stream.photoDataPublisher.listen { photoData in
    let imageData = photoData.data
    // Convert to UIImage or save
}

// Trigger capture
stream.capturePhoto(format: .jpeg)
```

## Bandwidth and quality

Resolution and frame rate are constrained by Bluetooth Classic bandwidth. The SDK automatically reduces quality when bandwidth is limited:
1. First lowers resolution (e.g., High → Medium)
2. Then reduces frame rate (e.g., 30 → 24), never below 15 FPS

Request lower settings for higher visual quality per frame.

## Links

- [Stream API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.7/mwdatcamera_stream)
- [StreamConfiguration API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.7/mwdatcamera_streamconfiguration)
- [Integration guide](https://wearables.developer.meta.com/docs/build-integration-ios)

# Debugging (iOS)

Diagnose common setup, registration, and streaming issues in DAT SDK integrations.

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
- Stream stuck in `waitingForDevice`
- Permission requests fail or never appear

### Watch for

- Developer Mode toggles **off** after firmware updates — re-enable it
- Developer Mode is per-device — enable for each glasses pair
- Some features need additional permissions beyond Developer Mode

## Stream state issues

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

Ensure compatible versions of SDK, Meta AI app, and glasses firmware. See [version dependencies](https://wearables.developer.meta.com/docs/version-dependencies) for the current compatibility matrix.

## Known issues

| Issue | Workaround |
|-------|-----------|
| No internet → registration fails | Internet required for registration |
| Streams started with glasses doffed pause when donned | Unpause by tapping side of glasses |
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

Set up the Meta Wearables Device Access Toolkit in an iOS app.

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
func startRegistration() async throws {
    try await Wearables.shared.startRegistration()
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
import MWDATCore
import MWDATCamera

// Create a DeviceSession — device selection is configured here
let wearables = Wearables.shared
let deviceSelector = AutoDeviceSelector(wearables: wearables)
let deviceSession = try wearables.createSession(deviceSelector: deviceSelector)
try deviceSession.start()

// Wait for the device session to reach the started state
for await state in deviceSession.stateStream() {
    if state == .started { break }
}

let config = StreamConfiguration(
    videoCodec: .raw,
    resolution: .low,
    frameRate: 24
)
guard let stream = try deviceSession.addStream(config: config) else {
    return
}

// Observe frames
let frameToken = stream.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.currentFrame = image
    }
}

// Start the stream capability
Task { await stream.start() }
```

## Next steps

- [Camera Streaming](camera-streaming.md) — Resolution, frame rate, photo capture
- [MockDevice Testing](mockdevice-testing.md) — Test without hardware
- [Session Lifecycle](session-lifecycle.md) — Handle pause/resume/stop
- [Permissions](permissions-registration.md) — Camera permission flows
- [Full documentation](https://wearables.developer.meta.com/docs/develop/)

# MockDevice Testing (iOS)

Use MockDeviceKit to test DAT SDK integrations without physical Meta glasses.

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
import MWDATMockDevice

let mockDeviceKit = MockDeviceKit.shared
mockDeviceKit.enable()

let mockDevice = mockDeviceKit.pairRaybanMeta()
```

## Simulating device states

```swift
// Simulate glasses lifecycle
mockDevice.powerOn()
mockDevice.unfold()
mockDevice.don()    // Simulate wearing the glasses

// Later...
mockDevice.doff()   // Simulate removing
mockDevice.fold()
mockDevice.powerOff()
```

## Configuring permissions

MockDeviceKit provides `mockPermissions` to control permission behavior without the Meta AI app.

By default, `requestPermission()` returns `.granted`. Use `set(_:_:)` to control `checkPermissionStatus()` and `setRequestResult(_:result:)` to control `requestPermission()` outcomes.

```swift
let mockDeviceKit = MockDeviceKit.shared

// Simulate denied camera permission status
mockDeviceKit.mockPermissions.set(.camera, .denied)

// Simulate denied request result (user tapping "deny")
mockDeviceKit.mockPermissions.setRequestResult(.camera, result: .denied)
```

## Setting up mock camera feeds

### Video streaming

```swift
let camera = mockDevice.services.camera
camera.setCameraFeed(fileURL: videoURL)
```

### Photo capture

```swift
let camera = mockDevice.services.camera
camera.setCapturedImage(fileURL: imageURL)
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
        MockDeviceKit.shared.enable()
        mockDevice = MockDeviceKit.shared.pairRaybanMeta()
        cameraKit = mockDevice?.services.camera
    }

    override func tearDown() async throws {
        MockDeviceKit.shared.disable()
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

Register your app with Meta AI, then request the device permissions it needs.

The DAT SDK separates two concepts:
1. **Registration** — Your app registers with Meta AI to become a permitted integration
2. **Device permissions** — After registration, request specific device permissions (e.g., camera)

All permission grants occur through the Meta AI companion app.

## Registration flow

### Start registration

```swift
func startRegistration() async throws {
    try await Wearables.shared.startRegistration()
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
        case .unavailable:
            // Registration unavailable
        case .available:
            // Ready to register
        case .registering:
            // Registration in progress
        }
    }
}
```

### Unregister

```swift
func startUnregistration() async throws {
    try await Wearables.shared.startUnregistration()
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
class StreamViewModel: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var streamState: String = "Stopped"
    @Published var capturedPhoto: Data?

    private let wearables = Wearables.shared
    private var deviceSession: DeviceSession?
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
            guard let stream = try deviceSession.addStream(config: config) else { return }
            self.deviceSession = deviceSession
            self.stream = stream
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

        await stream.start()
    }

    func stopStream() {
        Task { await stream?.stop() }
        deviceSession?.stop()
        stream = nil
        deviceSession = nil
    }

    func capturePhoto() {
        stream?.capturePhoto(format: .jpeg)
    }
}
```

## Testing with MockDeviceKit

Add mock device support to develop without glasses:

```swift
import MWDATMockDevice

func setupMockDevice() async {
    let mockDeviceKit = MockDeviceKit.shared
    mockDeviceKit.enable()

    let device = mockDeviceKit.pairRaybanMeta()
    device.don()

    if let videoURL = Bundle.main.url(forResource: "test_video", withExtension: "mov") {
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
- `MWDATDisplay` — for rendering Display content
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
| `idle` | Session created but not started | Call `start()` when ready |
| `starting` | Session is connecting to the device | Show connecting state |
| `started` | Session active and ready for capabilities | Add or resume work |
| `paused` | Temporarily suspended by the device | Hold work, may resume |
| `stopping` | Session is cleaning up | Wait for terminal state |
| `stopped` | Session inactive and terminal | Free resources, create a new session to restart |

## Observing session state

```swift
let session = try Wearables.shared.createSession(deviceSelector: AutoDeviceSelector())
try session.start()

Task {
    for await state in session.stateStream() {
        switch state {
        case .started:
            // Confirm UI shows session is live
        case .paused:
            // Keep connection, wait for started or stopped
        case .stopped:
            // Release resources, allow user to restart
        default:
            break
        }
    }
}
```

## Stream state transitions

A `Stream` is a capability attached to a started `DeviceSession`:

```text
stopped → waitingForDevice → starting → streaming → paused → stopped
```

```swift
guard let stream = try session.addStream(config: StreamConfiguration()) else { return }

let token = stream.statePublisher.listen { state in
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
- The device may resume by returning to `started`

Your app should **not** attempt to restart while paused — wait for `started` or `stopped`.

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
- Closing hinges disconnects Bluetooth → forces `stopped`
- Opening hinges restores Bluetooth but does **not** restart sessions
- Start a new session after the device becomes available again

## Implementation checklist

- [ ] Handle all relevant session states (`started`, `paused`, `stopped`)
- [ ] Monitor device availability before starting work
- [ ] Release resources only after `stopped`
- [ ] Don't infer transition causes — rely only on observable state
- [ ] Don't restart during `paused` — wait for system to resume or stop

## Links

- [Session lifecycle documentation](https://wearables.developer.meta.com/docs/lifecycle-events)

# Display Access (iOS)

Add `MWDATDisplay` to the app target when rendering content on Meta Ray-Ban Display glasses. Display apps also need the core getting-started and permissions-registration setup: call `Wearables.configure()` at launch, configure Info.plist URL schemes, route app-open URLs to `Wearables.shared.handleUrl(_:)`, and complete Meta AI registration before creating a session.

```swift
import MWDATCore
import MWDATDisplay
```

For a full Display app, mirror the DisplayAccess sample configuration: set `MWDAT.DAMEnabled = true`, keep `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, and `TeamID`, include `UISupportedExternalAccessoryProtocols` with `com.meta.ar.wearable`, and add the link-lease Info.plist keys for external accessory, Bluetooth central, Bluetooth usage description, local network, and Bonjour. The sample also includes `bluetooth-peripheral` and `processing` background modes. Keep the URL callback path wired to `Wearables.shared.handleUrl(_:)`.

Select display-capable hardware before creating the session, wait for the session to reach `.started`, then add and start Display. Use `SpecificDeviceSelector(device: selectedDevice.identifier)` when targeting a picked device; the selector takes a `DeviceIdentifier`. `AutoDeviceSelector` updates from `devicesStream()`, so create it before the user taps the Display action or wait for `activeDeviceStream()` to yield a non-nil device before calling `createSession(deviceSelector:)`.

```swift
let wearables = Wearables.shared
let selector = AutoDeviceSelector(
  wearables: wearables,
  filter: { $0.supportsDisplay() }
)
let session = try wearables.createSession(deviceSelector: selector)
let sessionErrorTask = Task {
  for await error in session.errorStream() {
    await MainActor.run {
      showError(error.localizedDescription)
    }
  }
}
let sessionStarted = Task {
  for await state in session.stateStream() {
    if state == .started { return }
  }
}
try session.start()
await sessionStarted.value

let display = try session.addDisplay()
displayStateToken = display.statePublisher.listen { state in
  Task { @MainActor in
    if state == .started {
      do {
        try await display.send(
          FlexBox(direction: .column, spacing: 12) {
            Text("Bike ride", style: .heading)
            Button(label: "Done", style: .primary, iconName: .checkmark)
          }
          .padding(24)
          .background(.card)
        )
      } catch {
        showError(error.localizedDescription)
      }
    }
  }
}
await display.start()
```

For device picker/settings UI, read `Wearables.shared.devicesStream()`, resolve each identifier with `deviceForIdentifier(_:)`, and display `nameOrId()`, `deviceType().rawValue`, `linkState`, and `compatibility()`. Keep link-state and compatibility listener tokens alive. If firmware compatibility reports `.deviceUpdateRequired`, offer `Wearables.shared.openFirmwareUpdate()`. If session start throws or streams `DeviceSessionError.datAppOnTheGlassesUpdateRequired`, offer `Wearables.shared.openDATGlassesAppUpdate()`.

Keep `displayStateToken` alive while you need state updates, and cancel the session error task when the flow ends. Wait for `DisplayState.started` through `statePublisher` after `await display.start()` before sending user-triggered content. If the user taps before Display is connected, queue the send and run it when `DisplayState.started` arrives, as DisplayAccess does. Reset the Display session when registration changes back to `.available` or `.unavailable`.

Build exactly one root `DisplayableView` per send: use a root `FlexBox` for UI or a root `VideoPlayer` for video. Do not send `Text`, `Button`, `Image`, or `Icon` as roots. Use `FlexBox.onTap` and `Button(label:onClick:)` for interactions; each send replaces the active content and tap handlers. If SwiftUI is imported, qualify Display DSL names such as `MWDATDisplay.Text`, `MWDATDisplay.Button`, and `MWDATDisplay.Image`. Use `IconName` enum values such as `.gear`, not raw strings. For URL video, set `display.onPlaybackEvent` before sending `VideoPlayer(provider: .uri(...), codec: .mp4, onError: { ... })`, clear it after terminal events, call `sendVideoStop()` for early exits, and treat blank or non-HTTP(S) URLs as `DisplayError.invalidVideoURL`.
