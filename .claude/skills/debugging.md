---
description: Common issues, Developer Mode, version compatibility, state machine diagnosis
---

# Debugging (iOS)

Guide for diagnosing common issues with DAT SDK integrations.

## Quick diagnosis

```text
Device not connecting?
│
├── Is Developer Mode enabled? → Enable in Meta AI app settings
│
├── Is device registered? → Check registration state
│
├── Is device in range? → Bluetooth on, glasses powered on
│
├── Is the app registered? → Check registrationStateStream()
│
└── Stream stuck in waitingForDevice? → Check device availability
```

## Developer Mode

Developer Mode must be enabled for 3P apps to access device features.

### Enabling Developer Mode

1. Open Meta AI app on phone
2. Go to Settings → (Your connected glasses)
3. Find "Developer Mode" toggle
4. Toggle ON
5. Device may restart

### Symptoms of Developer Mode disabled

- Registration completes but device never connects
- StreamSession stuck in `waitingForDevice`
- Permission requests fail or never appear

### Common gotchas

- Developer Mode toggles **off** after firmware updates — re-enable it
- Developer Mode is per-device — enable for each glasses pair
- Some features need additional permissions beyond Developer Mode

## StreamSession state issues

### Expected flow

```text
stopped → waitingForDevice → starting → streaming → stopped
```

### Stuck in waitingForDevice

- Device not in range or not connected
- Device not reporting availability
- DeviceSelector not matching any device

### Unexpected stop

- Device disconnected (out of range, battery died)
- Channel closed by device
- Error in frame processing

## Version compatibility

Ensure compatible versions of SDK, Meta AI app, and glasses firmware:

| SDK | Meta AI App | Ray-Ban Meta | Meta Ray-Ban Display |
|-----|-------------|--------------|----------------------|
| 0.5.0 | Check [version dependencies](https://wearables.developer.meta.com/docs/version-dependencies) | Check docs | Check docs |
| 0.4.0 | V254 | V20 | V21 |
| 0.3.0 | V249 | V20 | — |

## Known issues

| Issue | Workaround |
|-------|-----------|
| No internet → registration fails | Internet required for registration |
| Streams started with glasses doffed pause when donned | Unpause by tapping side of glasses |
| `DeviceStateSession` unreliable with camera stream | Avoid using `DeviceStateSession` |
| [iOS] Meta Ray-Ban Display: no audio feedback on pause/resume | Will be fixed in future release |

## Adding debug logging

```swift
import os

private let logger = Logger(subsystem: "com.yourapp", category: "Wearables")

// In your streaming code:
logger.debug("Stream state changed to: \(state)")
logger.error("Stream error: \(error)")
```

## Checklist

- [ ] Developer Mode enabled in Meta AI app
- [ ] Meta AI app updated to compatible version
- [ ] Glasses firmware updated to compatible version
- [ ] Internet connection available for registration
- [ ] Bluetooth enabled on phone
- [ ] Correct URL scheme configured in Info.plist
- [ ] Background modes enabled (bluetooth-peripheral, external-accessory)

## Links

- [Known issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [Troubleshooting discussions](https://github.com/facebook/meta-wearables-dat-ios/discussions)
