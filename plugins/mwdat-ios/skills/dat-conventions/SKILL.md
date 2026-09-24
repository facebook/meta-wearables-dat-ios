---
name: dat-conventions
description: Swift patterns, async/await, naming conventions, key types for DAT SDK iOS development
---

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

See the `dat-docs-mcp` skill for Claude Code, Cursor, and MCP Inspector setup and troubleshooting.

Use `llms.txt` when your tool only supports static reference context.

## Links

- [iOS API Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [GitHub Repository](https://github.com/facebook/meta-wearables-dat-ios)
