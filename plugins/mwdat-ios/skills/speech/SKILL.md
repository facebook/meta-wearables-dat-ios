---
name: speech
description: Recognize speech on connected glasses and consume partial and final transcriptions on iOS
---

# Speech (iOS)

Speech is an experimental on-device recognition capability. Enable it for the app in Wearables Developer Center and obtain microphone permission before starting it.

## Request permission deliberately

Check permission silently first with `checkPermissionStatus(.microphone)`. If it is not granted, call `requestPermission(.microphone)` only after a user action that explains the transition to the Meta AI app, and continue only when the result is `.granted`.

## Attach and start

Add Speech after the `DeviceSession` reaches `.started`. Register listeners before `start()` so initial state, locale, errors, and transcription events are not missed.

```swift
guard let speech = try session.addSpeech() else { return }

speech.transcriptionPublisher.listen { result in
  if result.isFinal {
    commitTranscript(result.text)
  } else {
    showPartialTranscript(result.text)
  }
}.store(in: tokens)

speech.start()
```

Retain the listener token while Speech is attached. Observe `statePublisher`, `localePublisher`, and `errorPublisher` when the app needs lifecycle, locale, or failure updates.

`confidence` is between 0 and 1, or `-1` when unavailable. Do not discard a transcription just because confidence is unavailable.

## Stop and remove

`speech.stop()` keeps Speech attached and allows another `start()`. Cancel listener tokens before calling `session.removeSpeech()`; removal is terminal.

Handle device disconnection, invalid state, unavailable recognition, already-listening, start failure, and unexpected errors through `errorPublisher`.

## Test with MockDeviceKit

After Speech is listening, inject results with calls such as `glasses.services.speech.simulateTranscription(text: "turn left", isFinal: true, confidence: 0.9)`. The service can also inject locale changes, partial text, completion, and recognition errors. The live host-device ASR source is for manual MockDevice testing; real-glasses recognition uses the glasses microphone.

## Availability

Speech is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.
