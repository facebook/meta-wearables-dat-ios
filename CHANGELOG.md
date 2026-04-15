# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-04-15

### Added

- Ray-Ban Meta Optics glasses support.
- [Feature] `MockCameraKit` can use the phone camera (front and back) to simulate streaming with `MockCameraKit.setCameraFeed(cameraFacing)`.
- [Feature] `MockDeviceKit` now supports configuration to simulate device registration and permissions.
  - `MockDeviceKitConfig` struct to configure `MockDeviceKit` with `initiallyRegistered` and `initialPermissionsGranted` options.
  - `MockPermissions` protocol with `set` and `setRequestResult` to simulate permission states in tests.
  - `MockDeviceKitInterface`: added `enable(config:)`, `disable`, `isEnabled`, `pairedDevices`, and `permissions` for controlling MockDeviceKit lifecycle and permissions.
- [API] Session-based device management. Device interactions are now scoped to a `DeviceSession` with explicit lifecycle control.
  - `Wearables.createSession(deviceSelector:)` to create a `DeviceSession` for a given `DeviceSelector`.
  - `DeviceSession` class with `start`, `stop`, state observation via `statePublisher` / `stateStream()`, and error observation via `errorPublisher` / `errorStream()`.
  - `DeviceSessionState` enum with values `idle`, `starting`, `started`, `paused`, `stopping`, `stopped`.
  - `DeviceSessionError` enum with typed error cases including `noEligibleDevice`, `sessionAlreadyExists`, `capabilityAlreadyActive`, and more.
  - `Capability` protocol and `CapabilityState` enum for extending sessions with additional features such as camera streaming.
  - `DeviceSession.addStream(config:)` to add a camera `StreamSession` as a capability to a device session.
- [API] `MockDisplaylessGlassesServices` protocol grouping mock services, accessible via `MockDisplaylessGlasses.services`.
- [Feature] Objective-C camera API. `MWDATCamera` is now fully usable from Objective-C via `MWDATStreamSession` and related types.
  - Objective-C `MWDATStreamSession` with listener-based callbacks for state, video frames, photos, and errors, plus `NSNotification` names for each event.
  - Objective-C configuration and type wrappers: `MWDATStreamSessionConfig`, `MWDATVideoFrame`, `MWDATPhotoData`, `MWDATStreamSessionState`, `MWDATStreamSessionError`, `MWDATStreamingResolution`, `MWDATVideoCodec`, `MWDATPhotoCaptureFormat`.
  - Objective-C device selectors: `MWDATSpecificDeviceSelector` and `MWDATAutoDeviceSelector`.

### Changed

- [API] `MockDeviceKitInterface`, `MockDevice`, `MockCameraKit`, and related protocols no longer require `@MainActor` and now conform to `Sendable`, making them safe to use from any thread.
- [API] `MockCameraKit.setCameraFeed(fileURL:)` and `setCapturedImage(fileURL:)` are no longer `async`.
- Improved the Camera Access App MockDevice UI.

### Fixed

- `MockDevice` better simulates state when a device is powered off or doffed.

### Removed

- [API] `MockDeviceKitError` enum.
- [API] `MockDisplaylessGlasses.getCameraKit` has been removed. The functionality is accessible through `MockDisplaylessGlasses.services`.

## [0.5.0] - 2026-03-11

### Added

- [Feature] `VideoCodec.hvc1` to `StreamSessionConfig` for compressed HEVC streaming that continues in the background. The default `VideoCodec.raw` pauses streaming when app is backgrounded.
- [Feature] Support for app attestation.
- [API] `thermalCritical` to `StreamSessionError` to indicate that the device's thermal state has reached a critical level that may affect streaming performance.
- AI coding agents config files: AGENTS.md, Claude skills, Cursor rules, Copilot instructions.

### Removed

- [API] `@MainActor` requirement from MWDATCamera to enable safely calling this from any thread.
- [API] `HingeState` enum.
- [API] `DeviceState` struct.
- [Dependency] `nanopb` library dependency which was blocking Apple review for iOS apps.
- [CameraAccess] Removed timer functionality.

### Fixed

- High resolution (720x1280) video can now be requested.

### Changed

- [CameraAccess] Improved photo capture flow.

## [0.4.0] - 2026-02-03

> **Note:** This version requires updated configuration values from Wearables Developer Center for release channel functionality.

### Added

- Meta Ray-Ban Display glasses support.
- [API] `hingesClosed` value in `StreamSessionError`.
- [API] `UnregistrationError`, and moved some values from `RegistrationError` to it.
- [API] `networkUnavailable` value in `RegistrationError`.
- [API] `WearablesHandleURLError`.

### Changed

- `MWDATCore` types are now `Sendable`, making the SDK thread-safe.

### Fixed

- Fixed streaming status when switching between devices.
- Fixed streaming status failing to reach `Streaming` state. A race condition caused this issue.

## [0.3.0] - 2025-12-16

### Changed

- [API] In `PermissionError`, `companionAppNotInstalled` has been renamed to `metaAINotInstalled`.
- Relaxed constraints to API methods, allowing some to run outside `@MainActor`.
- The Camera Access app streaming UI reflects device availability.
- The Camera Access app shows errors when incompatible glasses are found.
- The Camera Access app can now run in background mode, without interrupting streaming (but stopping video decoding).

### Fixed

- Streaming status is set to `stopped` if permission is not granted.
- Fixed UI issues in the Camera Access app.

## [0.2.1] - 2025-12-04

### Added

- [API] Raw `CMSampleBuffer` to `VideoFrame`.

### Changed

- The SDK does not require setting `CFBundleDisplayName` in the app's `Info.plist` during development.

### Fixed

- Streaming can now continue when the app is in background mode.

## [0.2.0] - 2025-11-18

### Added

- [API] New `compatibility` method in `Device`.
- [API] `addCompatibilityListener` to react to compatibility changes.
- [API] Convenience initializer on `StreamSession` enabling user provided `StreamSessionConfig`.
- Description to enum types and made them `CustomStringConvertible` for easier printing.

### Changed

- [API] The SDK is now split into separate components, allowing independent inclusion in projects as needed.
- [API] Obj-C functions no longer use typed throws; they now throw only `Error`.
- [API] Permission API updated for better consistency with Android:
  - `isPermissionGranted` renamed to `checkPermissionStatus`, returning `PermissionStatus` instead of `Bool`.
  - `requestPermission` now returns `PermissionStatus` instead of `Bool`.
  - Added `PermissionStatus` with values `granted` and `denied`, instead of the `Bool` used before.
  - Updated `PermissionError` values.
- [API] `RegistrationError` now holds different errors, aligning more closely with the Android SDK.
- [API] Renamed `DeviceType` enum values.
- [API] Replaced `MockDevice` `UUID` with `DeviceIdentifier`.
- Updated `StreamingResolution.Medium` from 540x960 to 504x896 to match Android.
- `AutoDeviceSelector` now selects or drops devices based on connectivity state.
- Adaptive Bit Rate (streaming) now works with the provided resolution and frame rate hints.
- Camera Access app redesigned and updated to the current SDK version.

### Removed

- [API] `androidPermission` property from `Permission`.
- [API] `prepare` method from `StreamSession`.

### Fixed

- Fixed issue where sessions sometimes failed to close when connection with glasses was lost.

## [0.1.0] - 2025-10-30

### Added

- First version of the Wearables Device Access Toolkit for iOS.
