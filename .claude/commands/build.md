---
description: Build the Xcode project using Swift Package Manager
---

Build the Xcode project using Swift Package Manager.

## Prerequisites

- Xcode 15.0 or later
- iOS 16.0+ deployment target
- Meta Wearables DAT SDK added via SPM

## Build

Open the `.xcodeproj` or `.xcworkspace` in Xcode and build with Cmd+B, or from the command line:

```bash
xcodebuild -scheme YourScheme -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Run on device

To test with real glasses, build and run on a physical device:

```bash
xcodebuild -scheme YourScheme -destination 'platform=iOS,id=YOUR_DEVICE_UDID' build
```

## Common build issues

- **Missing package**: Ensure `https://github.com/facebook/meta-wearables-dat-ios` is added in Xcode > File > Add Package Dependencies
- **Minimum deployment target**: The SDK requires iOS 16.0+
- **Entitlements**: Ensure `bluetooth-peripheral` and `external-accessory` background modes are enabled
