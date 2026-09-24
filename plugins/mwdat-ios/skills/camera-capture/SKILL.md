---
name: camera-capture
description: Capture standalone high-quality photos from connected glasses on iOS
---

# Camera Capture (iOS)

Camera Capture is the experimental standalone high-quality photo path exposed by `camera.photo`. It is different from `stream.capturePhoto`, which takes a photo while video streaming remains active.

## Prepare Camera and permission

The app needs Camera approval in Wearables Developer Center and `.camera` permission. Add Camera only after the `DeviceSession` starts. Stream and standalone Photo compete for camera hardware, so stop an active Stream before starting Photo.

## Observe and start Photo

Register the publishers you need before calling `start()`, then wait for `.started` before requesting a capture.

```swift
guard let camera = try session.addCamera(config: StreamConfiguration()) else { return }
let photo = camera.photo
let photoTokens = ListenerTokenBag()

photo.photoDataPublisher.listen { capture in
  Task { @MainActor in
    updatePhotoPreview(capture.imageData, metadata: capture.metadata)
  }
}.store(in: photoTokens)

photo.start()
```

After Photo reaches `.started`, call `photo.capturePhoto(resolution: .full, quality: .high)` with the desired resolution and quality. Capture is asynchronous; image data arrives through `photoDataPublisher`. Observe `transferProgressPublisher` for progress and `errorPublisher` for failures. Larger, higher-quality captures take longer to process and transfer.

## Errors and cleanup

Calling capture before `.started` publishes `PhotoError.notReady`. Setup and capture failures arrive through `errorPublisher`. Keep the Photo and `photoTokens` alive until delivery completes, then stop Photo, clear the token bag, and stop Camera.

After `photo.stop()` returns Photo to `.stopped`, the same `camera.photo` instance can be restarted with `photo.start()`. Stopping Camera or the parent session also stops its children.

## Test with MockDeviceKit

Before requesting capture, configure the next image with `glasses.services.cameraCapture.setCapturedPhoto(fileURL:)` or use `simulateCaptureFailure()` for a one-shot failure.

## Availability

Standalone Camera Capture is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.
