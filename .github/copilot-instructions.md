# Meta Wearables DAT SDK — AI Instructions

> Full API reference: [https://wearables.developer.meta.com/llms.txt?full=true](https://wearables.developer.meta.com/llms.txt?full=true)
>
> DAT docs MCP: [https://mcp.developer.meta.com/wearables](https://mcp.developer.meta.com/wearables)
>
> Developer docs: [https://wearables.developer.meta.com/docs/develop/](https://wearables.developer.meta.com/docs/develop/)

# DAT SDK Conventions (iOS)

## Architecture

The public SDK is organized into these modules:
- **MWDATCore**: Device discovery, registration, permissions, device selectors, `DeviceSession`
- **MWDATCamera**: `Camera`, `Stream`, `VideoFrame`, photo capture
- **MWDATDisplay**: Display capability, display UI components, icons, images, buttons, video
- **MWDATMockDevice**: MockDeviceKit for testing without hardware
- **MWDATMockDeviceTestClient**: `MockDeviceTestClient` for driving MockDeviceKit over HTTP from a UI-test process

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
import MWDATMockDevice  // MockDeviceKit, MockGlasses, MockCameraKit
```

## Key Types

- `Wearables` — SDK entry point. Call `Wearables.configure()` at launch, then use `Wearables.shared` (an `any WearablesInterface`)
- `DeviceSession` — The connection to a selected device. Create with `createSession(deviceSelector:)`, then attach capabilities
- `Camera` — Camera capability from `session.addCamera(config:)`; owns `camera.stream`
- `Stream` — Camera stream: `start()`, `stop()`, `capturePhoto(format:)`, and the frame/state/photo/error publishers
- `Display` — Display capability from `session.addDisplay()`
- `VideoFrame` — Individual video frame with `.makeUIImage()` and `.sampleBuffer`
- `Device` / `DeviceIdentifier` — `DeviceIdentifier` is a `String`; resolve a `Device` with `deviceForIdentifier(_:)`
- `AutoDeviceSelector` — Selects the best available device, optionally filtered (`filter: { $0.supportsDisplay() }`)
- `SpecificDeviceSelector` — Selects a specific device by `DeviceIdentifier`
- `StreamConfiguration` — Configure video codec, resolution, frame rate
- `ListenerTokenBag` / `AnyListenerToken` — Keep `.listen {}` subscriptions alive; dropping a token cancels it
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

If your editor supports remote MCP servers, connect `https://mcp.developer.meta.com/wearables` and use `search_dat_docs` for current DAT setup, session lifecycle, camera streaming, MockDeviceKit, permissions, and exact API symbols. This public docs server does not require authentication; do not configure tokens, OAuth, or custom authorization headers for it.

Use `llms.txt` when your tool only supports static reference context.

## Links

- [iOS API Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [GitHub Repository](https://github.com/facebook/meta-wearables-dat-ios)

# Camera Streaming (iOS)

Guide for implementing camera streaming and photo capture with the DAT SDK.

## Key concepts

- **DeviceSession**: The connection to the glasses. Create and start it first; it can stay connected with no camera attached.
- **Camera**: The capability you attach to a started `DeviceSession` with `addCamera(config:)`. It owns the `Stream`.
- **Stream**: `camera.stream` — start/stop streaming, capture photos, observe frames, state, and errors.
- **VideoFrame**: Individual video frames. Use `.makeUIImage()` to render, or `.sampleBuffer` when you need the raw `CMSampleBuffer` (for example to write compressed frames to a file).
- **StreamConfiguration**: Configure video codec, resolution, and frame rate.
- **PhotoData**: Still image captured from glasses (`.data` plus `.format`).

Treat "start a session" and "start the preview" as two separate user-visible steps, as the `CameraAccess` sample does. That keeps the session reusable when the user stops and restarts the preview.

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

## Adding a Camera

Once the `DeviceSession` is started, add the `Camera` capability and stream through `camera.stream`.

Check camera permission first. `checkPermissionStatus(.camera)` is a silent query, while `requestPermission(.camera)` switches to the Meta AI app. `CameraAccess` only calls `requestPermission` after the user confirms the app switch, so the redirect is never a surprise:

```swift
if try await wearables.checkPermissionStatus(.camera) != .granted {
    // Confirm with the user, then:
    guard try await wearables.requestPermission(.camera) == .granted else { return }
}
```

Then attach the camera:

```swift
let config = StreamConfiguration(
    videoCodec: .raw,
    resolution: .medium,  // 504x896
    frameRate: 24
)

guard let camera = try deviceSession.addCamera(config: config) else {
    // DeviceSession must be in the started state before adding a camera
    return
}
let stream = camera.stream
```

### Resolution options

| Resolution | Size |
|-----------|------|
| `.high` | 720 x 1280 |
| `.medium` | 504 x 896 |
| `.low` | 360 x 640 |

### Frame rate options

`frameRate` is a `UInt`. Valid values: `2`, `7`, `15`, `24`, `30` FPS.

Lower resolution and frame rate yield higher visual quality due to less Bluetooth compression.

### Codec options

`VideoCodec` has two cases:

- `.raw` — decoded frames. Render them directly with `frame.makeUIImage()`.
- `.hvc1` — compressed HEVC frames. Use this when you want to write frames to a file in passthrough mode; you must decode `frame.sampleBuffer` yourself for on-screen preview, as `CameraAccess` does.

`StreamConfiguration()` with no arguments defaults to `.raw`, `.medium`, and 30 FPS.

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

## Observing stream errors

`stream.errorPublisher` emits typed `StreamError` values such as `.permissionDenied`,
`.deviceNotConnected`, `.hingesClosed`, `.thermalHot`, `.batteryLow`, and
`.photoCaptureFailed`. Surface `error.localizedDescription` rather than maintaining
your own error-message map.

```swift
let errorToken = stream.errorPublisher.listen { error in
    Task { @MainActor in
        self.errorMessage = error.localizedDescription
    }
}
```

Keep listener tokens alive for as long as you need callbacks. `MWDATCore` provides
`ListenerTokenBag` and `AnyListenerToken.store(in:)` for that:

```swift
let streamTokens = ListenerTokenBag()
stream.statePublisher.listen { _ in }.store(in: streamTokens)
stream.videoFramePublisher.listen { _ in }.store(in: streamTokens)
// On teardown:
streamTokens.clear()
```

## Starting and stopping

```swift
// Start the stream capability
stream.start()

// Stop the camera — this cascades to its stream child and detaches the camera
// from the session, so a later addCamera() can register a new one.
camera.stop()

// Stop the parent device session when you're done with all capabilities.
// Teardown cascades parent -> child, not child -> parent.
deviceSession.stop()
```

## Photo capture

Capture a still photo while streaming. `capturePhoto(format:)` returns `Bool`:
`false` means the capture was not started (for example another capture is already
in flight), so no `photoDataPublisher` event will arrive.

```swift
// Listen for photo data
let photoToken = stream.photoDataPublisher.listen { photoData in
    let imageData = photoData.data  // photoData.format is .jpeg or .heic
    // Convert to UIImage or save
}

// Trigger capture
let started = stream.capturePhoto(format: .jpeg)
if !started {
    // Re-enable the shutter button and tell the user to try again
}
```

## Bandwidth and quality

Resolution and frame rate are constrained by Bluetooth Classic bandwidth. The SDK automatically reduces quality when bandwidth is limited:
1. First lowers resolution (e.g., High → Medium)
2. Then reduces frame rate (e.g., 30 → 24), never below 15 FPS

Request lower settings for higher visual quality per frame.

## Links

- [Stream API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest/mwdatcamera_stream)
- [StreamConfiguration API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest/mwdatcamera_streamconfiguration)
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
| Streams started with glasses doffed pause when donned | Unpause by tapping the side of the glasses |
| A single touchpad tap pauses an active stream | Tap again to resume; keep the last frame on screen while `StreamState` is `.paused` |

See the public [known issues](https://wearables.developer.meta.com/docs/knownissues) page for the current list.

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
- [ ] Correct URL scheme configured in Info.plist, and `MWDAT` > `AppLinkURLScheme` matches it
- [ ] URL callback handler forwards `metaWearablesAction` links to `Wearables.shared.handleUrl(_:)`
- [ ] Background modes enabled (`processing`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`)
- [ ] `UISupportedExternalAccessoryProtocols` contains `com.meta.ar.wearable`
- [ ] `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, and `NSBonjourServices` present

## Links

- [Known issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [Troubleshooting discussions](https://github.com/facebook/meta-wearables-dat-ios/discussions)

# Getting Started with DAT SDK (iOS)

Set up the Meta Wearables Device Access Toolkit in an iOS app.

## Prerequisites

- Xcode 26.4+, Swift 6.3+, iOS 17.2+ deployment target — this matches the public `CameraAccess` and `DisplayAccess` sample apps
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

<!-- DAT configuration -->
<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key>
  <string>myexampleapp://</string>
  <key>MetaAppID</key>
  <string>$(META_APP_ID)</string>
  <key>ClientToken</key>
  <string>$(CLIENT_TOKEN)</string>
  <key>TeamID</key>
  <string>$(DEVELOPMENT_TEAM)</string>
</dict>

<!-- Background modes and transport permissions -->
<key>UIBackgroundModes</key>
<array>
  <string>processing</string>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
  <string>external-accessory</string>
</array>
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.meta.ar.wearable</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta AI Glasses</string>
<key>NSLocalNetworkUsageDescription</key>
<string>This lets your phone find and connect to your glasses over Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
  <string>_bonjour._tcp</string>
</array>
```

Replace `myexampleapp` with your app's URL scheme and keep `MWDAT` > `AppLinkURLScheme` in sync with it — the SDK sends that scheme to Meta AI so it can call your app back.

`MetaAppID`, `ClientToken`, and `TeamID` come from build settings in the sample apps. With Developer Mode you can leave `MetaAppID` empty, set it to `0`, or leave the `$(META_APP_ID)` placeholder unexpanded; the SDK treats all three as "no app ID" and skips attestation. For production, set `MetaAppID` and `ClientToken` from your app in the [Wearables Developer Center](https://wearables.developer.meta.com/) and set `TeamID` to your Apple Developer Team ID (Xcode > Signing & Capabilities).

The SDK moves traffic over more than one link type and checks Info.plist before it can use each one, so declare all of them:

| Link | Required Info.plist entries |
|------|-----------------------------|
| Bluetooth LE | `bluetooth-central` and `bluetooth-peripheral` background modes, `NSBluetoothAlwaysUsageDescription` |
| Bluetooth Classic (used by camera streaming) | `external-accessory` background mode, `UISupportedExternalAccessoryProtocols` containing `com.meta.ar.wearable` |
| Wi-Fi (high bandwidth) | non-empty `NSLocalNetworkUsageDescription`, `NSBonjourServices` with `_bonjour._tcp` |

Only add the `audio` background mode and `NSMicrophoneUsageDescription` if you record glasses-microphone audio, as `CameraAccess` does.

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

Your app must handle the URL callback from Meta AI after registration and permission flows. Both sample apps filter on the `metaWearablesAction` query item so unrelated deep links are not forwarded to the SDK:

```swift
.onOpenURL { url in
    guard
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    else {
        return
    }
    Task {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            // Surface the failure; `handleUrl` throws `WearablesHandleURLError`
        }
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
guard let camera = try deviceSession.addCamera(config: config) else {
    return
}
let stream = camera.stream

// Observe frames
let frameToken = stream.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.currentFrame = image
    }
}

// Start the stream capability
stream.start()
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
- `MockDeviceKit.shared` — Entry point (`MockDeviceKitInterface`) for creating simulated devices
- `MockGlasses` — Simulated glasses, created with `pairGlasses(model:)`
- `MockGlassesServices` — Per-device services: `camera`, `captouch`, `display`
- `MockCameraKit` — Simulated camera with configurable video feed and photo capture
- `MockCaptouchKit` — Simulated touchpad (`tap()`, `tapAndHold()`)
- `MockDisplayKit` — Simulated Display surface for `MWDATDisplay` content
- `MockPermissions` — Control DAT permission results without the Meta AI app

`GlassesModel` cases: `.rayBanMeta`, `.oakleyMetaHSTN`, `.oakleyMetaVanguard`,
`.rayBanMetaOptics`, `.metaGlasses`, `.metaRayBanDisplay`. Use `.metaRayBanDisplay`
when you need a display-capable simulated device.

## Setup

Add `MWDATMockDevice` to your target via Swift Package Manager (it's included in the `meta-wearables-dat-ios` package).

```swift
import MWDATMockDevice
```

To test a Display experience, also add `MWDATDisplay` to the target. After
enabling `MockDeviceKit`, use the normal `DeviceSession.addDisplay()` API.

## Creating a mock device

```swift
import MWDATMockDevice

let mockDeviceKit = MockDeviceKit.shared
mockDeviceKit.enable()

let mockDevice = try mockDeviceKit.pairGlasses(model: .rayBanMeta)
```

`enable()` starts from a registered, permissions-granted state. Pass a
`MockDeviceKitConfig` when you want to exercise the registration or permission
flow instead:

```swift
mockDeviceKit.enable(
    config: MockDeviceKitConfig(initiallyRegistered: false, initialPermissionsGranted: false)
)
```

Use `mockDeviceKit.pairedDevices`, `mockDeviceKit.unpairDevice(_:)`, and
`mockDeviceKit.disable()` to tear devices down.

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

// Battery, charging, and thermal state
mockDevice.setBatteryLevel(35)
mockDevice.setChargingState(.charging)
mockDevice.setThermalLevel(.severe)
```

## Simulating touchpad input

A single tap pauses an active camera stream, and a second tap resumes it — the
`CameraAccess` tests use this to cover the `StreamState.paused` path.

```swift
mockDevice.services.captouch.tap()
mockDevice.services.captouch.tapAndHold()
```

## Configuring permissions

MockDeviceKit provides `permissions` to control permission behavior without the Meta AI app.

By default, `requestPermission()` returns `.granted`. Use `set(_:_:)` to control `checkPermissionStatus()` and `setRequestResult(_:result:)` to control `requestPermission()` outcomes.

```swift
let mockDeviceKit = MockDeviceKit.shared

// Simulate denied camera permission status
mockDeviceKit.permissions.set(.camera, .denied)

// Simulate denied request result (user tapping "deny")
mockDeviceKit.permissions.setRequestResult(.camera, result: .denied)
```

## Setting up mock camera feeds

### Video streaming

```swift
let camera = mockDevice.services.camera
camera.setCameraFeed(fileURL: videoURL)

// Or stream live from the phone's own camera
camera.setCameraFeed(cameraFacing: .back)  // CameraFacing is .front or .back
```

### Photo capture

```swift
let camera = mockDevice.services.camera
camera.setCapturedImage(fileURL: imageURL)
```

## Writing tests with MockDeviceKit

Create a reusable test base class:

```swift
import MWDATCore
import MWDATMockDevice
import XCTest

@MainActor
class MockDeviceKitTestCase: XCTestCase {
    private var mockDevice: MockGlasses?
    private var cameraKit: MockCameraKit?

    override func setUp() async throws {
        try await super.setUp()
        try? Wearables.configure()
        MockDeviceKit.shared.enable()
        let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
        mockDevice = device
        cameraKit = device.services.camera

        // Make the device available to Wearables before creating a session
        device.powerOn()
        device.unfold()
    }

    override func tearDown() async throws {
        MockDeviceKit.shared.disable()
        mockDevice = nil
        cameraKit = nil
        try await super.tearDown()
    }
}
```

The device only shows up in `Wearables.shared.devicesStream()` after it is
powered on and unfolded, so wait for your view model's "device available" state
before calling `createSession(deviceSelector:)`.

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
| Video | h.265 (HEVC); the samples ship an `.mp4` file |
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

Filter on the `metaWearablesAction` query item so unrelated deep links are not forwarded to the SDK:

```swift
.onOpenURL { url in
    guard
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    else {
        return
    }
    Task {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch let error as RegistrationError {
            showError(error.description)
        } catch {
            showError(error.localizedDescription)
        }
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
            // Registration is unavailable
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

## Typed errors

Registration and permission APIs use typed throws. Prefer `error.description` or
`error.localizedDescription` over your own error strings:

- `startRegistration()` throws `RegistrationError`: `.alreadyRegistered`, `.configurationInvalid`, `.metaAINotInstalled`, `.networkUnavailable`, `.unknown`
- `startUnregistration()` throws `UnregistrationError`: `.alreadyUnregistered`, `.configurationInvalid`, `.metaAINotInstalled`, `.unknown`
- `handleUrl(_:)` throws `WearablesHandleURLError`: `.registrationError`, `.unregistrationError`
- `checkPermissionStatus(_:)` and `requestPermission(_:)` throw `PermissionError`: `.noDevice`, `.noDeviceWithConnection`, `.connectionError`, `.metaAINotInstalled`, `.requestInProgress`, `.requestTimeout`, `.internalError`
- `openFirmwareUpdate()` and `openDATGlassesAppUpdate()` throw `NavigationError`: `.metaAINotInstalled`, `.notRegistered`

## Update flows

When a device reports `compatibility() == .deviceUpdateRequired`, offer a firmware
update. When session start reports `DeviceSessionError.datAppOnTheGlassesUpdateRequired`,
offer the glasses app update. Both open Meta AI:

```swift
try await Wearables.shared.openFirmwareUpdate()
try await Wearables.shared.openDATGlassesAppUpdate()
```

## Developer Mode vs Production

| Mode | Registration behavior |
|------|----------------------|
| Developer Mode | Registration always allowed. `MetaAppID` is empty, `0`, or an unexpanded `$(META_APP_ID)` placeholder, so the SDK skips attestation |
| Production | `MetaAppID`, `ClientToken`, and `TeamID` must all be set, and users must be in the proper release channel |

For production, get your app ID and client token from the [Wearables Developer Center](https://wearables.developer.meta.com/), and use your Apple Developer Team ID for `TeamID`.

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
let session = try Wearables.shared.createSession(deviceSelector: AutoDeviceSelector(wearables: Wearables.shared))
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

`DeviceSession` exposes both shapes: `stateStream()` / `errorStream()` as
`AsyncStream`, and `statePublisher` / `errorPublisher` as listener-token
`Announcer`s. Pick one per call site; subscribe before calling `start()` so no
initial transition is missed.

## Session errors

`errorStream()` and `errorPublisher` emit `DeviceSessionError`. Handle
`.noEligibleDevice` (no matching device yet), `.sessionAlreadyExists`,
`.capabilityAlreadyActive`, the thermal/battery cases (`.thermalCritical`,
`.thermalEmergency`, `.peakPowerShutdown`, `.batteryCritical`), and
`.datAppOnTheGlassesUpdateRequired`, which is delivered as a one-shot event and
should open `Wearables.shared.openDATGlassesAppUpdate()`.

`start()` uses typed throws, so you can catch the specific case:

```swift
do throws(DeviceSessionError) {
    try session.start()
} catch .datAppOnTheGlassesUpdateRequired {
    showGlassesAppUpdatePrompt()
} catch {
    showError(error.localizedDescription)
}
```

## Stream state transitions

A `Stream` is a capability attached to a started `DeviceSession`:

```text
stopped → waitingForDevice → starting → streaming → paused → stopped
```

```swift
guard let camera = try session.addCamera(config: StreamConfiguration()) else { return }
let stream = camera.stream

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
    for await deviceIds in Wearables.shared.devicesStream() {
        // deviceIds is [DeviceIdentifier]; resolve details with deviceForIdentifier(_:)
    }
}
```

A `DeviceSelector` also reports availability directly. `AutoDeviceSelector` and
`SpecificDeviceSelector` both expose `activeDevice` and `activeDeviceStream()`,
which yields `nil` when no eligible device is available:

```swift
let selector = AutoDeviceSelector(wearables: Wearables.shared)
Task {
    for await deviceId in selector.activeDeviceStream() {
        hasActiveDevice = deviceId != nil
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

For a full Display app, mirror the DisplayAccess sample configuration: keep `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, and `TeamID` under `MWDAT`, set `UIBackgroundModes` to `processing`, `bluetooth-central`, `bluetooth-peripheral`, and `external-accessory`, add `UISupportedExternalAccessoryProtocols` with `com.meta.ar.wearable` for the Bluetooth Classic link, and add `NSBluetoothAlwaysUsageDescription`, a non-empty `NSLocalNetworkUsageDescription`, and `NSBonjourServices` with `_bonjour._tcp` for the Wi-Fi link lease. Keep the URL callback path wired to `Wearables.shared.handleUrl(_:)`.

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
display.start()
```

For device picker/settings UI, read `Wearables.shared.devicesStream()`, resolve each identifier with `deviceForIdentifier(_:)`, and display `nameOrId()`, `deviceType().rawValue`, `linkState`, and `compatibility()`. Keep link-state and compatibility listener tokens alive. If firmware compatibility reports `.deviceUpdateRequired`, offer `Wearables.shared.openFirmwareUpdate()`. If session start throws or streams `DeviceSessionError.datAppOnTheGlassesUpdateRequired`, offer `Wearables.shared.openDATGlassesAppUpdate()`.

Keep `displayStateToken` alive while you need state updates, and cancel the session error task when the flow ends. Wait for `DisplayState.started` through `statePublisher` after `display.start()` before sending user-triggered content. If the user taps before Display is connected, queue the send and run it when `DisplayState.started` arrives, as DisplayAccess does. Reset the Display session when registration changes back to `.available` or `.unavailable`.

Build exactly one root `DisplayableView` per send: use a root `FlexBox` for UI or a root `VideoPlayer` for video. Do not send `Text`, `Button`, `Image`, or `Icon` as roots. Wrap multiple buttons in a `ButtonGroup` and mark the default action with `.actionRole(.primary)`. Use `FlexBox.onTap` and `Button(label:onClick:)` for interactions; each send replaces the active content and tap handlers. If SwiftUI is imported, qualify Display DSL names such as `MWDATDisplay.Text`, `MWDATDisplay.Button`, and `MWDATDisplay.Image`. Use `IconName` enum values such as `.gear`, not raw strings, and use `Image(uri:)` for remote images or `Image(image:)` for a bundled `UIImage`. For URL video, set `display.onPlaybackEvent` before sending `VideoPlayer(provider: .uri(...), codec: .mp4, onError: { ... })`, clear it after terminal events, call `sendVideoStop()` for early exits, and treat blank or non-HTTP(S) URLs as `DisplayError.invalidVideoURL`.

To preview Display content without hardware, pair a mock device with `MockDeviceKit.shared.pairGlasses(model: .metaRayBanDisplay)`, power it on, and render `mockDevice.services.display.createPreviewView()` in your app.

# DAT docs MCP

The public DAT documentation MCP server is at `https://mcp.developer.meta.com/wearables` over Streamable HTTP. It exposes `search_dat_docs` for semantic search over DAT guides, API reference, and code examples, and may add more tools over time.

- Muse Code, Claude Code, and Codex: install the `mwdat-ios` plugin; it registers the server automatically and requires no separate MCP configuration
- Cursor: add an HTTP MCP server named `wearables-dat` pointing at the same URL
- MCP Inspector: `npx @modelcontextprotocol/inspector`, transport Streamable HTTP, connection type Direct

The server does not require authentication. Do not configure tokens, OAuth, or custom `Authorization` headers for it. Use the repo-local AI config for coding patterns and setup, and the MCP endpoint for live docs and exact current API symbols.

# Inputs

Inputs is experimental and requires capability approval in Wearables Developer Center; there is no runtime Inputs permission to request. Attach it only after `DeviceSession` reaches `.started` with `session.addInputs(configuration:)`; adding starts it automatically. Consume `inputs.events`, handle every `InputEvent`, retain state/error listener tokens, then cancel observers and call `session.removeInputs()`. Mock input events are injected through `glasses.services.input` after the capability is active.

# Motion

Motion is experimental and has no runtime permission. Attach it after the session starts, observe state/errors/samples before `motion.start()`, treat all sensor components as optional, and cancel observers before `session.removeMotion()`. Use `glasses.services.motion.setMotionFeed` for deterministic replay.

# Speech

Speech is experimental and requires microphone permission requested from a user action. Attach after the session starts, register state/locale/error/transcription listeners before `speech.start()`, handle partial/final text and confidence `-1`, and remove Speech during cleanup. Use `glasses.services.speech` for tests.

# Audio Streaming

Audio Streaming is an experimental Camera Stream extension. Require camera and microphone permission, configure PCM audio, register `audioFramePublisher` before starting Stream, and cancel the listener before stopping Camera. MockDeviceKit does not guarantee PCM frame injection.

# Camera Capture

Use `camera.photo` for standalone high-quality capture, not `stream.capturePhoto`. Stop Stream first, register state/data/progress/error publishers, call `photo.start()`, wait for `.started`, then capture. Stop Photo before Camera and use `glasses.services.cameraCapture` for tests.

# Voice Invocations

Voice Invocations is a Wearables-level stream, not a DeviceSession capability. Retain listeners before `start(deviceIdentifier:)`, acknowledge every `LaunchApp` exactly once, and stop during cleanup. It needs WDC approval and an app name, but no runtime camera/microphone permission or Info.plist phrase.
