---
name: camera-streaming
description: Stream, video frames, photo capture, resolution/frame rate configuration
---

# Camera Streaming (iOS)

Guide for implementing camera streaming and photo capture with the DAT SDK.

For PCM audio delivered with this stream, use the `audio-streaming` skill.

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

## In-stream photo capture

This is the lightweight capture path used while video is streaming. For standalone high-quality capture with resolution, quality, transfer progress, and its own lifecycle, use the `camera-capture` skill.

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
