---
name: display-access
description: Display capability setup, display-capable device selection, UI DSL, icons, buttons, images, and video playback
---

# Display Access (iOS)

Use `MWDATDisplay` to render content on Meta Ray-Ban Display glasses.

Use this skill with `getting-started` and `permissions-registration` when creating a full app. A Display app still needs `Wearables.configure()` at launch, Info.plist URL scheme configuration, URL callbacks through `Wearables.shared.handleUrl(_:)`, and completed Meta AI registration before it can create a session.

## Add the Display module

Add `MWDATDisplay` to the same app target that already uses `MWDATCore`. Import it next to core:

```swift
import MWDATCore
import MWDATDisplay
```

For a phone preview, add `MWDATMockDevice` alongside `MWDATDisplay`, enable
`MockDeviceKit`, and pair a display-capable model:

```swift
import MWDATMockDevice

MockDeviceKit.shared.enable()
let mockDevice = try MockDeviceKit.shared.pairGlasses(model: .metaRayBanDisplay)
mockDevice.powerOn()
mockDevice.don()

// Render what the glasses would show, inside your app
let previewView = mockDevice.services.display.createPreviewView()
```

`MockDisplayKit` also exposes `sendClick(identifier:)` so tests can simulate taps.

Use the normal `DeviceSession.addDisplay()` API for both physical and mock
devices. Wait until `deviceForIdentifier(_:)` reports `linkState == .connected`
and `compatibility() == .compatible` before creating the session.

## Display-specific app configuration

Use the getting-started Info.plist setup, then mirror the DisplayAccess sample for Display sessions:

- Keep the `CFBundleURLTypes` URL scheme and route callbacks to `Wearables.shared.handleUrl(_:)`.
- Under `MWDAT`, set `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, and `TeamID`. An empty, `0`, or unexpanded `$(META_APP_ID)` value keeps the SDK in Developer Mode; production apps should use Wearables Developer Center values for `MetaAppID` and `ClientToken`, plus the Apple Developer Team ID.
- Set `UIBackgroundModes` to `processing`, `bluetooth-central`, `bluetooth-peripheral`, and `external-accessory`; add `UISupportedExternalAccessoryProtocols` with `com.meta.ar.wearable`; and add `NSBluetoothAlwaysUsageDescription`. The DisplayAccess sample declares the first three background modes; keep the `external-accessory` mode and the accessory protocol so the Bluetooth Classic link stays available.
- For high-bandwidth Display/video, include a non-empty `NSLocalNetworkUsageDescription` and `NSBonjourServices` with `_bonjour._tcp`. Display acquires link leases: core device discovery/session setup uses medium then low links, while Display uses medium then high links when available.

## Select a display-capable device

Use the public display filter when creating an automatic selector:

```swift
let wearables = Wearables.shared
let deviceSelector = AutoDeviceSelector(
  wearables: wearables,
  filter: { device in device.supportsDisplay() }
)
```

Use `SpecificDeviceSelector(device: selectedDevice.identifier)` instead when your UI lets the user pick a specific `Device`. The initializer takes a `DeviceIdentifier`, not the whole `Device`.

`AutoDeviceSelector` updates from `devicesStream()`. Create it before the user taps the Display action, or wait for `activeDeviceStream()` to yield a non-nil device before calling `createSession(deviceSelector:)`; otherwise `createSession` can throw `DeviceSessionError.noEligibleDevice`.

For a picker or Settings screen, list devices from `Wearables.shared.devicesStream()`, then look up metadata from `deviceForIdentifier(_:)`. The DisplayAccess sample shows `nameOrId()`, `deviceType().rawValue`, `linkState`, and `compatibility()` and keeps `addLinkStateListener` / `addCompatibilityListener` tokens alive while rows are visible. If `compatibility() == .deviceUpdateRequired`, surface a firmware update action through `Wearables.shared.openFirmwareUpdate()`.

## Attach Display after the session starts

Create and start the `DeviceSession`, wait for `.started`, then add and start `Display`. Keep the state listener token alive for as long as you need updates, and observe `session.errorStream()` for async session failures.

```swift
import MWDATCore
import MWDATDisplay

@MainActor
final class DisplayController {
  private var deviceSession: DeviceSession?
  private var display: Display?
  private var displayStateToken: AnyListenerToken?
  private var sessionErrorTask: Task<Void, Never>?

  func connect() async {
    do {
      let wearables = Wearables.shared
      let selector = AutoDeviceSelector(
        wearables: wearables,
        filter: { $0.supportsDisplay() }
      )

      let session = try wearables.createSession(deviceSelector: selector)
      deviceSession = session
      sessionErrorTask = Task { [weak self] in
        for await error in session.errorStream() {
          await self?.showError(error.localizedDescription)
        }
      }

      let sessionStarted = Task {
        for await state in session.stateStream() {
          if state == .started {
            return
          }
        }
      }
      do {
        try session.start()
        await sessionStarted.value
      } catch {
        sessionStarted.cancel()
        throw error
      }

      let capability = try session.addDisplay()
      display = capability
      displayStateToken = capability.statePublisher.listen { [weak self] state in
        Task { @MainActor in
          if state == .started {
            self?.showStatusCard()
          }
        }
      }

      capability.start()
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      showDATGlassesAppUpdate()
    } catch {
      showError(error.localizedDescription)
    }
  }

  func disconnect() async {
    display?.onPlaybackEvent = nil
    display?.stop()
    deviceSession?.stop()
    sessionErrorTask?.cancel()
    sessionErrorTask = nil
    displayStateToken = nil
    display = nil
    deviceSession = nil
  }
}
```

For user-triggered content, match the sample's pending-action pattern: if the user taps "Try it" before Display is connected, store the send as a pending async action, attach to Display, and run the action when `DisplayState.started` arrives. Reset the display session when registration changes to `.available` or `.unavailable`.

## Send display UI

Build exactly one root `DisplayableView` per `send(_:)` call. Each send replaces the previous content on the glasses and replaces the active tap handlers. Use a root `FlexBox` for UI, or a root `VideoPlayer` for video. Do not send `Text`, `Button`, `Image`, or `Icon` as the root; place them inside a `FlexBox`.

If a file also imports SwiftUI, Display DSL names such as `Text`, `Button`, and `Image` can be ambiguous. Prefer keeping Display builders in files that import `MWDATDisplay` without SwiftUI, or qualify the symbols as `MWDATDisplay.Text`, `MWDATDisplay.Button`, and `MWDATDisplay.Image`.

```swift
func showStatusCard() {
  Task {
    do {
      try await display?.send(
        FlexBox(direction: .column, spacing: 12) {
          Text("Bike ride", style: .heading)
          Text("Turn right in 200 ft", style: .body, color: .secondary)
          Button(
            label: "Done",
            style: .primary,
            iconName: .checkmark,
            onClick: { print("Done tapped") }
          )
        }
        .padding(24)
        .background(.card)
        .onTap { print("Card tapped") }
      )
    } catch {
      showError((error as? DisplayError)?.description ?? error.localizedDescription)
    }
  }
}
```

## Group buttons and control layout

Wrap multiple buttons in a `ButtonGroup` rather than adding them directly to a `FlexBox`. Mark the default action with `.actionRole(.primary)`. `FlexBox`, `Text`, `Button`, `ButtonGroup`, `Image`, and `Icon` all support `.flexGrow(_:)`, `.flexShrink(_:)`, and `.alignSelf(_:)`; `FlexBox` also supports `.padding(_:)`, `.background(_:)`, and `.onTap(_:)`.

```swift
FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
  ButtonGroup {
    Button(label: "Previous", style: .primary, iconName: .triangleLeftVerticalLine, onClick: onPrevious)
    Button(label: "Next", style: .primary, iconName: .triangleRightVerticalLine, onClick: onNext)
      .actionRole(.primary)
    Button(label: "Watch video", style: .secondary, iconName: .videoCamera, onClick: onWatchVideo)
  }
}
```

`FlexBox` also accepts `wrap: true` and `padding: EdgeInsets(...)` in its initializer, and its `@ComponentBuilder` content supports `for` loops and `if` conditions.

## Use images and built-in icons

Use HTTPS image URLs for remote images, or `Image(image:)` for a bundled `UIImage`. Use the `IconName` enum for built-in icons; do not invent raw icon strings. `ButtonStyle` is `.primary`, `.secondary`, or `.outline`; `IconStyle` is `.filled` or `.outline`.

```swift
try await display.send(
  FlexBox(direction: .row, spacing: 8, crossAlignment: .center) {
    Image(
      uri: "https://example.com/thumbnail.png",
      sizePreset: .fill,
      cornerRadius: .medium
    )
    Image(image: UIImage(resource: .oil), sizePreset: .fill, cornerRadius: .medium)
    Icon(name: .gear, style: .filled)
    Text("Device settings", style: .body)
  }
  .padding(24)
)
```

## Send video

For URL-based video, send a root `VideoPlayer`. Use `VideoPlayer(onError:)` for video-specific errors, and use `display.onPlaybackEvent` for playback events. Set `onPlaybackEvent` before sending the video, clear it after terminal events if the flow is complete, and call `sendVideoStop()` if the user exits playback early. Blank or non-HTTP(S) URLs throw `DisplayError.invalidVideoURL`.

```swift
display.onPlaybackEvent = { event in
  if event.type == .ended || event.type == .stopped {
    Task { @MainActor in
      display.onPlaybackEvent = nil
      showStatusCard()
    }
  }
}

try await display.send(
  VideoPlayer(
    provider: .uri("https://example.com/tutorial.mp4"),
    codec: .mp4,
    onError: { error in
      Task { @MainActor in
        showError(error.localizedDescription)
      }
    }
  )
)
```

## Display rules

- Call `Wearables.configure()` at app launch and complete registration before creating the session.
- Include the DisplayAccess sample's link-lease Info.plist keys when building a full Display app.
- Wait for the `DeviceSession` to reach `.started` before calling `addDisplay()`.
- Handle `DeviceSessionError.datAppOnTheGlassesUpdateRequired` separately and offer `Wearables.shared.openDATGlassesAppUpdate()`.
- Call `display.start()`, then wait for `DisplayState.started` through `statePublisher` before sending user-triggered content.
- Observe `session.errorStream()` so async session failures are surfaced.
- Keep listener tokens alive; dropping a token stops that listener.
- Use the getting-started setup for Info.plist URL schemes and route app-open URLs to `Wearables.shared.handleUrl(_:)`.
- Use `nameOrId()`, `deviceType()`, `linkState`, and `compatibility()` for device rows; keep link/compatibility listener tokens until the row is gone.
- Use `FlexBox.onTap` and `Button(label:onClick:)` for interactions. The callbacks belong to the most recent sent view.
- Use only public Display DSL names: `FlexBox`, `Text`, `Button`, `ButtonGroup`, `Image`, `Icon`, `VideoPlayer`, `IconName`, `IconStyle`, `TextStyle`, `TextColor`, `ButtonStyle`, `ButtonGroupAlignment`, `ActionRole`, `ImageSize`, `CornerRadius`, `Direction`, `Alignment`, `Background`, `Edge`, and `EdgeInsets`.
- Call `display.clearDisplay()` when you want to remove content without stopping Display.
- Clear `display.onPlaybackEvent` when the video flow is finished if you no longer need playback callbacks.
- Stop Display before stopping the parent `DeviceSession` when the display experience ends.

## Sample app

Use the Display Access sample app for a complete flow: registration, device selection, display attachment, interactive content, and video.

## Links

- [iOS API reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest)
- [Developer documentation](https://wearables.developer.meta.com/docs/develop/)
