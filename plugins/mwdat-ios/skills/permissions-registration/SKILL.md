---
name: permissions-registration
description: App registration with Meta AI, camera permission flows
---

# Permissions & Registration (iOS)

Register your app with Meta AI, then request the device permissions it needs.

The DAT SDK separates two concepts:
1. **Registration** — Your app registers with Meta AI to become a permitted integration
2. **Device permissions** — After registration, request specific device permissions (e.g., camera)

All permission grants occur through the Meta AI companion app.

## Registration flow

### Start registration

```swift
func startRegistration() async throws {
    try await Wearables.shared.startRegistration()
}
```

This opens the Meta AI app where the user approves your app. Meta AI then calls back via your URL scheme.

### Handle the callback

Filter on the `metaWearablesAction` query item so unrelated deep links are not forwarded to the SDK:

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
        } catch let error as RegistrationError {
            showError(error.description)
        } catch {
            showError(error.localizedDescription)
        }
    }
}
```

### Observe registration state

```swift
Task {
    for await state in Wearables.shared.registrationStateStream() {
        switch state {
        case .registered:
            // App is registered, can request permissions
        case .unavailable:
            // Registration is unavailable
        case .available:
            // Ready to register
        case .registering:
            // Registration in progress
        }
    }
}
```

### Unregister

```swift
func startUnregistration() async throws {
    try await Wearables.shared.startUnregistration()
}
```

## Camera permissions

### Check permission status

```swift
let status = try await Wearables.shared.checkPermissionStatus(.camera)
```

### Request permission

```swift
let status = try await Wearables.shared.requestPermission(.camera)
```

The SDK opens Meta AI for the user to grant access. Users can choose:
- **Allow once** — temporary, single-session grant
- **Allow always** — persistent grant

## Multi-device behavior

Users can link multiple glasses to Meta AI. The SDK handles this transparently:
- Permission granted on **any** linked device means your app has access
- You don't need to track which device has permissions
- If all devices disconnect, permissions become unavailable

## Typed errors

Registration and permission APIs use typed throws. Prefer `error.description` or
`error.localizedDescription` over your own error strings:

- `startRegistration()` throws `RegistrationError`: `.alreadyRegistered`, `.configurationInvalid`, `.metaAINotInstalled`, `.networkUnavailable`, `.unknown`
- `startUnregistration()` throws `UnregistrationError`: `.alreadyUnregistered`, `.configurationInvalid`, `.metaAINotInstalled`, `.unknown`
- `handleUrl(_:)` throws `WearablesHandleURLError`: `.registrationError`, `.unregistrationError`
- `checkPermissionStatus(_:)` and `requestPermission(_:)` throw `PermissionError`: `.noDevice`, `.noDeviceWithConnection`, `.connectionError`, `.metaAINotInstalled`, `.requestInProgress`, `.requestTimeout`, `.internalError`
- `openFirmwareUpdate()` and `openDATGlassesAppUpdate()` throw `NavigationError`: `.metaAINotInstalled`, `.notRegistered`

## Update flows

When a device reports `compatibility() == .deviceUpdateRequired`, offer a firmware
update. When session start reports `DeviceSessionError.datAppOnTheGlassesUpdateRequired`,
offer the glasses app update. Both open Meta AI:

```swift
try await Wearables.shared.openFirmwareUpdate()
try await Wearables.shared.openDATGlassesAppUpdate()
```

## Developer Mode vs Production

| Mode | Registration behavior |
|------|----------------------|
| Developer Mode | Registration always allowed. `MetaAppID` is empty, `0`, or an unexpanded `$(META_APP_ID)` placeholder, so the SDK skips attestation |
| Production | `MetaAppID`, `ClientToken`, and `TeamID` must all be set, and users must be in the proper release channel |

For production, get your app ID and client token from the [Wearables Developer Center](https://wearables.developer.meta.com/), and use your Apple Developer Team ID for `TeamID`.

## Prerequisites

- Registration requires an internet connection
- Meta AI companion app must be installed
- For Developer Mode: enable in Meta AI > Settings > Your glasses > Developer Mode

## Links

- [Permissions documentation](https://wearables.developer.meta.com/docs/permissions-requests)
- [Getting started guide](https://wearables.developer.meta.com/docs/getting-started-toolkit)
- [Manage projects](https://wearables.developer.meta.com/docs/manage-projects)
