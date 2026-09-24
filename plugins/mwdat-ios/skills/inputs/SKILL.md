---
name: inputs
description: Receive navigation, button, capture, and drag input events from connected glasses on iOS
---

# Inputs (iOS)

Use the experimental Inputs capability to receive semantic interactions from glasses. The app must have Inputs enabled for it in Wearables Developer Center. Inputs does not have a `Permission` value to request at runtime.

## Attach after the session starts

`addInputs(configuration:)` returns `nil` unless the `DeviceSession` is already `.started`. Adding the capability starts it automatically; there is no public `start()` method.

```swift
let configuration = InputsConfiguration(consumeBack: true)
guard let inputs = try session.addInputs(configuration: configuration) else {
  return
}

let events = inputs.events
inputTask = Task {
  for await event in events {
    switch event {
    case .nav(let direction, _, _): moveFocus(direction)
    case .select: activateFocusedItem()
    case .back: dismissCurrentView()
    case .button(let button, _, _): handleButton(button)
    case .capture(let pressType, _, _): handleCaptureButton(pressType)
    case .drag(let action, let x, let y, let dx, let dy, _, _):
      updateDrag(action: action, x: x, y: y, dx: dx, dy: dy)
    }
  }
}
```

Retain the event task while Inputs is attached. Observe `statePublisher` when the UI needs activation state and `errorPublisher` for activation, availability, connection, and communication failures.

The default configuration enables every known source and consumes Back. Set `consumeBack` to `false` when the system, rather than the app, should handle Back.

Each event includes its source and device timestamp in milliseconds. Keep the switch exhaustive so new behavior is intentional. The event stream buffers the newest 64 events and drops the oldest when a consumer falls behind, so keep processing lightweight.

## Errors and cleanup

`InputsError.permissionDenied` means the capability was not approved for the app; it is not fixed with `requestPermission`. A terminal error ends the event stream but the capability remains attached.

Cancel the event task and any listener tokens, then call `session.removeInputs()` before adding another Inputs capability.

## Test with MockDeviceKit

After the app has attached Inputs, inject events through the paired mock glasses with calls such as `glasses.services.input.navDown()`. The service also exposes Select, Back, Button, Capture, and Drag injection. Calls made before Inputs is active, or from a source excluded by the configuration, are dropped.

## Availability

Inputs is experimental. Apps can use it for development and beta testing, but cannot publish it to production release channels yet.
