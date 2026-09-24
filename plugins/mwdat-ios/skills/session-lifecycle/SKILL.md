---
name: session-lifecycle
description: Device session states, pause/resume, availability monitoring
---

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
