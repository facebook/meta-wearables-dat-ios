---
description: SDK setup, Swift Package Manager integration, Info.plist configuration, and first connection to Meta glasses
---

# Getting Started with DAT SDK (iOS)

Guide for setting up the Meta Wearables Device Access Toolkit in an iOS app.

## Prerequisites

- Xcode 15.0+, iOS 16.0+ deployment target
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

<!-- Allow Meta AI to callback -->
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>fb-viewapp</string>
</array>

<!-- External accessory protocol -->
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.meta.ar.wearable</string>
</array>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-peripheral</string>
  <string>external-accessory</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta Wearables</string>

<!-- DAT configuration -->
<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key>
  <string>myexampleapp://</string>
  <key>MetaAppID</key>
  <string>0</string>
</dict>
```

Replace `myexampleapp` with your app's URL scheme. Use `0` for `MetaAppID` during development with Developer Mode.

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

Your app must handle the URL callback from Meta AI after registration:

```swift
.onOpenURL { url in
    Task {
        _ = try? await Wearables.shared.handleUrl(url)
    }
}
```

## Step 5: Register with Meta AI

```swift
func startRegistration() throws {
    try Wearables.shared.startRegistration()
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
import MWDATCamera

let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
let config = StreamSessionConfig(
    videoCodec: .raw,
    resolution: .low,
    frameRate: 24
)
let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

// Observe frames
let frameToken = session.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
    Task { @MainActor in
        self.currentFrame = image
    }
}

// Start
Task { await session.start() }
```

## Next steps

- [Camera Streaming](camera-streaming.md) — Resolution, frame rate, photo capture
- [MockDevice Testing](mockdevice-testing.md) — Test without hardware
- [Session Lifecycle](session-lifecycle.md) — Handle pause/resume/stop
- [Permissions](permissions-registration.md) — Camera permission flows
- [Full documentation](https://wearables.developer.meta.com/docs/develop/)
