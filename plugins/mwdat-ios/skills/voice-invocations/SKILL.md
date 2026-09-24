---
name: voice-invocations
description: Launch and activate an iOS app from Hey Meta voice invocations and acknowledge each action
---

# Voice Invocations (iOS)

Voice Invocations lets Meta AI launch or foreground an app when the wearer says “Hey Meta, start {app name}.” It is a Wearables-level stream, not a `DeviceSession` capability, and does not require a running device session.

## Configure the app

Register the bundle identifier, request Voice Invocation approval, and configure the spoken app name in Wearables Developer Center. Do not add invocation phrases to `Info.plist`. Voice Invocations does not require camera or microphone permission.

## Create and start the stream

`VoiceInvocationsStream` is `@MainActor`. Retain the stream and both listener tokens for as long as the app should receive actions. Register listeners before starting.

```swift
let newStream = try VoiceInvocationsStream(wearables: Wearables.shared)
stream = newStream
invocationToken = newStream.invocationsPublisher.listen { invocation in
  guard let launch = invocation as? LaunchApp else { return }
  navigateToMainScreen()
  Task {
    _ = await launch.responseHandle.sendSuccess(actionOutput: nil)
  }
}
errorToken = newStream.errorPublisher.listen { error in
  showError(error.localizedDescription)
}
try newStream.start(deviceIdentifier: deviceIdentifier)
```

Store `stream`, `invocationToken`, and `errorToken` on the `@MainActor` owner. Every delivered invocation must be acknowledged exactly once with `sendSuccess` or `sendFailure`. The Boolean result indicates whether the response was delivered.

The initializer can throw `invalidWearablesInterface`. Starting can throw `deviceNotFound` or `channelNotConnected`; later communication failures arrive through `errorPublisher`. Starting again switches the stream to the new device.

## Stop and test

`stop()` is safe when inactive, and the same stream can start again later. Stop the stream and release its listener tokens when the owning app component is done.

To test without hardware, check `glasses.services.voiceInvocation.hasConnectedClients` before calling `sendLaunchAppAction()`. Use `sendIncompleteAction()` to confirm malformed actions produce an error rather than an invocation.

## Availability

Voice Invocations is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.

See the [Voice Invocations guide](https://wearables.developer.meta.com/docs/develop/dat/voice-invocations/).
