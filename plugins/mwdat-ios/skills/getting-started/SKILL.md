---
name: getting-started
description: SDK setup, Swift Package Manager integration, Info.plist configuration, and first connection to Meta glasses
---

# Getting Started with DAT SDK (iOS)

Set up the Meta Wearables Device Access Toolkit in an iOS app.

## Prerequisites

- Xcode 26.4+, Swift 6.3+, iOS 17.2+ deployment target — this matches the public `CameraAccess` and `DisplayAccess` sample apps
- Meta AI companion app installed on test device
- Ray-Ban Meta glasses or Meta Ray-Ban Display glasses (or use MockDeviceKit for development)
- Developer Mode enabled in Meta AI app (Settings > Your glasses > Developer Mode)

## Step 1: Add the SDK via Swift Package Manager

1. In Xcode, select **File** > **Add Package Dependencies...**
2. Enter `https://github.com/facebook/meta-wearables-dat-ios`
3. Select a [version](https://github.com/facebook/meta-wearables-dat-ios/tags)
4. Add `MWDATCore` and `MWDATCamera` to your target

## Step 2: Configure Info.plist

Add these required entries to your `Info.plist`:

```xml
<!-- URL scheme for Meta AI callbacks -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myexampleapp</string>
    </array>
  </dict>
</array>

<!-- DAT configuration -->
<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key>
  <string>myexampleapp://</string>
  <key>MetaAppID</key>
  <string>$(META_APP_ID)</string>
  <key>ClientToken</key>
  <string>$(CLIENT_TOKEN)</string>
  <key>TeamID</key>
  <string>$(DEVELOPMENT_TEAM)</string>
</dict>

<!-- Background modes and transport permissions -->
<key>UIBackgroundModes</key>
<array>
  <string>processing</string>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
  <string>external-accessory</string>
</array>
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.meta.ar.wearable</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta AI Glasses</string>
<key>NSLocalNetworkUsageDescription</key>
<string>This lets your phone find and connect to your glasses over Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
  <string>_bonjour._tcp</string>
</array>
```

Replace `myexampleapp` with your app's URL scheme and keep `MWDAT` > `AppLinkURLScheme` in sync with it — the SDK sends that scheme to Meta AI so it can call your app back.

`MetaAppID`, `ClientToken`, and `TeamID` come from build settings in the sample apps. With Developer Mode you can leave `MetaAppID` empty, set it to `0`, or leave the `$(META_APP_ID)` placeholder unexpanded; the SDK treats all three as "no app ID" and skips attestation. For production, set `MetaAppID` and `ClientToken` from your app in the [Wearables Developer Center](https://wearables.developer.meta.com/) and set `TeamID` to your Apple Developer Team ID (Xcode > Signing & Capabilities).

The SDK moves traffic over more than one link type and checks Info.plist before it can use each one, so declare all of them:

| Link | Required Info.plist entries |
|------|-----------------------------|
| Bluetooth LE | `bluetooth-central` and `bluetooth-peripheral` background modes, `NSBluetoothAlwaysUsageDescription` |
| Bluetooth Classic (used by camera streaming) | `external-accessory` background mode, `UISupportedExternalAccessoryProtocols` containing `com.meta.ar.wearable` |
| Wi-Fi (high bandwidth) | non-empty `NSLocalNetworkUsageDescription`, `NSBonjourServices` with `_bonjour._tcp` |

Only add the `audio` background mode and `NSMicrophoneUsageDescription` if you record glasses-microphone audio, as `CameraAccess` does.

## Step 3: Initialize the SDK

Call `Wearables.configure()` once at app launch:

```swift
import MWDATCore

@main
struct MyApp: App {
    init() {
        do {
            try Wearables.configure()
        } catch {
            assertionFailure("Failed to configure Wearables SDK: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Step 4: Handle URL callbacks

Your app must handle the URL callback from Meta AI after registration and permission flows. Both sample apps filter on the `metaWearablesAction` query item so unrelated deep links are not forwarded to the SDK:

```swift
.onOpenURL { url in
    guard
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    else {
        return
    }
    Task {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            // Surface the failure; `handleUrl` throws `WearablesHandleURLError`
        }
    }
}
```

## Step 5: Register with Meta AI

```swift
func startRegistration() async throws {
    try await Wearables.shared.startRegistration()
}
```

Observe registration state:

```swift
Task {
    for await state in Wearables.shared.registrationStateStream() {
        // Update UI based on registration state
    }
}
```

## Step 6: Start streaming

```swift
import MWDATCore
import MWDATCamera

// Create a DeviceSession — device selection is configured here
let wearables = Wearables.shared
let deviceSelector = AutoDeviceSelector(wearables: wearables)
let deviceSession = try wearables.createSession(deviceSelector: deviceSelector)
try deviceSession.start()

// Wait for the device session to reach the started state
for await state in deviceSession.stateStream() {
    if state == .started { break }
}

let config = StreamConfiguration(
    videoCodec: .raw,
    resolution: .low,
    frameRate: 24
)
guard let camera = try deviceSession.addCamera(config: config) else {
    return
}
let stream = camera.stream

// Observe frames
let frameToken = stream.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.currentFrame = image
    }
}

// Start the stream capability
stream.start()
```

## Next steps

- [Camera Streaming](camera-streaming.md) — Resolution, frame rate, photo capture
- [MockDevice Testing](mockdevice-testing.md) — Test without hardware
- [Session Lifecycle](session-lifecycle.md) — Handle pause/resume/stop
- [Permissions](permissions-registration.md) — Camera permission flows
- [Full documentation](https://wearables.developer.meta.com/docs/develop/)
