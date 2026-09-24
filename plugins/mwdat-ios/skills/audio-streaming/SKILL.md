---
name: audio-streaming
description: Receive synchronized PCM audio frames through a Camera stream on iOS
---

# Audio Streaming (iOS)

Audio Streaming is an experimental extension of Camera Stream, not a separate capability. Follow the `camera-streaming` skill to start a device session and attach Camera, then add audio configuration and collection.

## Permissions

The app needs Camera and Audio Streaming approval in Wearables Developer Center plus both `.camera` and `.microphone` runtime permissions. Check silently first and request either permission only after explaining the Meta AI app transition.

## Configure PCM audio

Provide a non-`nil` `audioCodec` when creating `StreamConfiguration`:

```swift
let configuration = StreamConfiguration(
  videoCodec: .raw,
  audioCodec: .pcm(sampleRate: .rate16000, numberOfChannels: 1),
  resolution: .medium,
  frameRate: 24
)

guard let camera = try session.addCamera(config: configuration) else { return }
let stream = camera.stream
```

Supported sample rates are 16,000, 44,100, and 48,000 Hz. Match downstream audio processing to the configured sample rate and channel count.

## Listen before starting

Retain the listener token on the long-lived owner and register it before `stream.start()`:

```swift
stream.audioFramePublisher.listen { frame in
  consumePCM(
    frame.pcmBuffer,
    presentationTime: frame.presentationTimeStamp
  )
}.store(in: streamTokens)
stream.start()
```

Use the presentation timestamp when ordering audio or aligning it with video. Do not mutate the delivered PCM buffer.

Audio shares Stream state and errors. Permission failures and critical stream errors arrive through `stream.errorPublisher`; do not create a second lifecycle for audio.

## Cleanup and testing limits

Deterministically cancel the audio listener before calling `camera.stop()`. Stopping Camera cascades to its Stream and invalidates both.

MockDeviceKit can negotiate an audio-enabled Camera stream, but it does not provide a public deterministic audio-frame injection API. Do not write tests that assume mock PCM frames will arrive.

## Availability

Audio Streaming is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.
