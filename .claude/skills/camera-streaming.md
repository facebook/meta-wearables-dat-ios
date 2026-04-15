---
description: StreamSession, video frames, photo capture, resolution/frame rate configuration
---

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

- [StreamSession API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.6/mwdatcamera_streamsession)
- [StreamSessionConfig API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.6/mwdatcamera_streamsessionconfig)
- [Integration guide](https://wearables.developer.meta.com/docs/build-integration-ios)
