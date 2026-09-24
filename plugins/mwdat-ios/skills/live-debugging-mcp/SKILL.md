---
name: live-debugging-mcp
description: Use this whenever debugging an iOS DAT app with local DAT Inspector MCP tools, live device events, Meta AI app/device boundary issues, permissions, registration, sessions, streaming, callbacks, or user reports that the app cannot communicate with glasses.
---

# Live DAT Debugging with MCP (iOS)

Use this skill when a developer is debugging an iOS DAT app and has a local DAT
Inspector MCP server or DAT debug server available to the agent. This is the
live-runtime counterpart to `dat-docs-mcp`: use docs search for API lookup, and
use this skill for observed app/device behavior.

## Ground rules

- Stay read-only unless the user explicitly asks for an app code change.
- Do not mutate Meta AI app, device, account, permission, registration, or app
  state.
- Treat companion-app/device results as boundary diagnosis from app-visible DAT
  events, not as direct access to companion app internals.
- Use live DAT evidence before guessing: registration, permissions, device
  selection, link state, session state, stream state, typed errors, and SDK logs.
- If the MCP tools are not configured, ask the developer to enable their local
  DAT debug setup and fall back to logs plus `search_dat_docs`.

## Normal agent loop

1. Discover and connect to the running app debug server:
   - `discover_debug_servers`
   - `connect_to_debug_server`
2. Establish the baseline with all three calls before diagnosing deeper:
   - `get_connection_status`
   - `get_sdk_state`
   - `get_dat_readiness`
   Do not skip `get_connection_status`; it separates MCP/debug-server
   connectivity from SDK, registration, permission, session, and stream state.
3. If the issue looks like Meta AI app or device boundary behavior, inspect:
   - `get_companion_boundary_diagnosis`
   - `get_device_path`
   - `get_permissions`
   - `get_device_properties`
4. Ask the developer to reproduce the failing iOS flow while connected.
5. Wait for narrow evidence instead of polling everything:
   - `wait_for_events` with `category` or `source`
   - `get_errors`
   - `get_event_digest`
6. For handoff, collect a redacted bundle:
   - `export_diagnostic_bundle`

## Evidence map

- Configuration: app logs around `Wearables.configure()`
- URL callbacks: `Wearables.shared.handleUrl(_:)` return handling
- Registration: `Wearables.shared.startRegistration()` and
  `wearables.registrationState`
- Device availability: device selectors, `wearables.devices`,
  `device.compatibility`, and `device.properties`
- Device link: `device.linkState`
- Permissions: DAT permission APIs, `device.permission`, `check_permissions`,
  and `get_permissions`
- Session: `DeviceSession` creation/start, `deviceSession.state`,
  `session.state`, and session errors
- Stream: stream start, `stream.state`, frame counters, and stream errors
- DAM/DWA-visible transport: DAM/DWA error values

## Diagnosis patterns

- Registration blocked: verify Info.plist DAT configuration, app URL scheme,
  Developer Mode setup, and callback handling.
- No eligible device: inspect discovered devices, selector behavior, device
  compatibility, and `device.linkState` before changing stream code.
- Permission failure: use `get_permissions` and `get_companion_boundary_diagnosis`;
  do not assume iOS system permission is the same as DAT permission through the
  Meta AI app/device boundary.
- Session fails before stream creation: inspect session errors and selected
  device compatibility before changing camera code.
- Stream fails after session start: inspect stream state, camera permission, and
  recent errors before changing frame processing.

## Output expectations

When summarizing, name the evidence plane, the blocking state, and the next
developer action. Example:

```text
DAT readiness is blocked at registration: the app-visible registration state is
not registered. Check the Info.plist DAT URL scheme and MetaAppID, complete the
Meta AI callback through handleUrl(_:), then retry while the MCP connection waits
for registration and device-link events.
```
