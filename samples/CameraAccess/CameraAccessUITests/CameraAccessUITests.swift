/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MWDATMockDeviceTestClient
import XCTest

@MainActor
final class CameraAccessUITests: XCTestCase {
  private static let portFilePrefix = "mwdat_test_server_port_"
  private static let portFileSuffix = ".txt"
  private let portFilePath = NSTemporaryDirectory() + "mwdat_test_server_port_\(UUID().uuidString).txt"
  private let app = XCUIApplication()
  // swiftlint:disable implicitly_unwrapped_optional
  private var mockClient: MockDeviceTestClient!
  private var pairedDeviceId: String!
  // swiftlint:enable implicitly_unwrapped_optional

  /// The iOS Local Network permission is a one-shot, per-install grant: once
  /// answered it persists across app relaunches, so the system dialog only
  /// appears on the first stream in the whole run. Tracked here so later tests
  /// skip the (otherwise wasted) wait for a prompt that will never reappear.
  private static var didAllowLocalNetwork = false

  override func setUp() async throws {
    continueAfterFailure = false
    removeStalePortFiles()
    addTeardownBlock { [portFilePath] in
      try? FileManager.default.removeItem(atPath: portFilePath)
    }

    app.launchArguments = ["--ui-testing"]
    app.launchEnvironment["MWDAT_TEST_SERVER_PORT_FILE"] = portFilePath
    app.launch()

    // Initialize the client *after* launch so the server has time to write the port file.
    mockClient = MockDeviceTestClient(portFilePath: portFilePath)
    let serverReachable = await mockClient.waitForServer(timeout: 10)
    XCTAssertTrue(serverReachable, "Test server should be running")
  }

  override func tearDown() async throws {
    cleanUpAppState()

    if pairedDeviceId != nil {
      _ = await mockClient.unpairDevice(deviceId: pairedDeviceId)
      pairedDeviceId = nil
    }
    app.terminate()
    mockClient = nil
  }

  // MARK: - Helpers

  private func cleanUpAppState() {
    guard app.state == .runningForeground else { return }

    dismissErrorAlertIfNeeded()
    closeCapturePreviewIfNeeded()

    let endSession = app.buttons["end_session_button"]
    if endSession.exists, endSession.isEnabled {
      endSession.tap()
      dismissErrorAlertIfNeeded()
      _ = app.buttons["start_session_button"].waitForExistence(timeout: 5)
      closeCapturePreviewIfNeeded()
    }

    dismissErrorAlertIfNeeded()
  }

  private func closeCapturePreviewIfNeeded() {
    let closePreview = app.buttons["close_preview_button"]
    if closePreview.exists, closePreview.isHittable {
      closePreview.tap()
    }
  }

  private func dismissErrorAlertIfNeeded() {
    let alertOK = app.alerts.buttons["OK"]
    if alertOK.exists, alertOK.isHittable {
      alertOK.tap()
    }
  }

  private func removeStalePortFiles() {
    let fileManager = FileManager.default
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    guard let fileURLs = try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil) else {
      return
    }

    for fileURL in fileURLs {
      let filename = fileURL.lastPathComponent
      if filename.hasPrefix(Self.portFilePrefix), filename.hasSuffix(Self.portFileSuffix) {
        try? fileManager.removeItem(at: fileURL)
      }
    }
  }

  /// Taps "Connect my glasses" to trigger registration via the fake handler, then
  /// waits for the camera screen to render in its registered-but-no-active-device
  /// state.
  private func registerViaUI() {
    let connectButton = app.buttons["Connect my glasses"]
    XCTAssertTrue(connectButton.waitForExistence(timeout: 10), "Should start on HomeScreenView")
    connectButton.tap()

    // The camera screen shows the waiting state until a device becomes active.
    let waitingText = app.staticTexts["Waiting for an active device"]
    XCTAssertTrue(waitingText.waitForExistence(timeout: 15), "Should show waiting state before a device is paired")
  }

  /// Registers, then pairs a mock device with default camera resources.
  private func pairDeviceWithCameraResources() async {
    registerViaUI()

    let deviceId = await mockClient.pairDevice()
    XCTAssertNotNil(deviceId, "pairDevice should return a deviceId")
    pairedDeviceId = deviceId

    _ = await mockClient.setCameraFeed(deviceId: pairedDeviceId, resourceName: "plant", ext: "mp4")
    _ = await mockClient.setCapturedImage(deviceId: pairedDeviceId, resourceName: "plant", ext: "png")
  }

  /// Waits for the camera screen idle state with an active device — the
  /// Start Session button is shown.
  @discardableResult
  private func waitForActiveDevice(timeout: TimeInterval = 15) -> XCUIElement {
    let startSession = app.buttons["start_session_button"]
    XCTAssertTrue(
      startSession.waitForExistence(timeout: timeout),
      "Start Session button should appear once a device is active"
    )
    return startSession
  }

  /// Waits for the camera screen to show the inactive-device waiting state.
  private func waitForInactiveDevice(timeout: TimeInterval = 15) {
    let waitingText = app.staticTexts["Waiting for an active device"]
    XCTAssertTrue(waitingText.waitForExistence(timeout: timeout), "Waiting-for-device state should appear")
  }

  /// Starts a session, then starts the preview, and waits until it is actively
  /// streaming — signalled by the Preview pill flipping from Start to Stop. (The
  /// Photo/Record controls exist but are disabled before streaming, so they aren't a
  /// reliable "streaming started" signal.)
  private func startSessionAndStream(timeout: TimeInterval = 20) {
    waitForActiveDevice(timeout: timeout).tap()

    let startPreview = app.buttons["start_preview_button"]
    XCTAssertTrue(startPreview.waitForExistence(timeout: timeout), "Start Preview should appear once the session is started")
    startPreview.tap()

    confirmCameraPermission()

    // Streaming runs over Wi-Fi (the high link level), so the first stream triggers
    // the iOS system Local Network permission dialog. It blocks the stream until
    // answered, so allow it before waiting for the streaming state.
    allowLocalNetworkPermissionIfNeeded()

    let stopPreview = app.buttons["stop_preview_button"]
    XCTAssertTrue(stopPreview.waitForExistence(timeout: timeout), "Preview should be streaming (Stop Preview shown)")
  }

  /// Allows the iOS system Local Network permission dialog on the first stream.
  /// The dialog is presented by SpringBoard, not the app, so it is tapped through
  /// the springboard element rather than `app.alerts`. Best-effort: once granted
  /// the dialog never reappears, so later calls return without waiting.
  private func allowLocalNetworkPermissionIfNeeded() {
    guard !Self.didAllowLocalNetwork else { return }
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons["Allow"]
    if allow.waitForExistence(timeout: 10) {
      allow.tap()
      Self.didAllowLocalNetwork = true
    }
  }

  /// Camera is denied by default in the mock, so the first preview surfaces the
  /// permission-redirect confirm alert. Tap "Continue" so the request proceeds
  /// (the mock then grants and persists it, so later previews skip the alert).
  private func confirmCameraPermission() {
    let allow = app.alerts.buttons["Continue"]
    XCTAssertTrue(allow.waitForExistence(timeout: 10), "Camera permission confirm should appear on first preview")
    allow.tap()
  }

  // MARK: - Device Pairing & Navigation Tests

  /// Verifies that launching without pairing a device shows the home screen.
  func testLaunchWithoutDeviceShowsHomeScreen() async {
    let connectButton = app.buttons["Connect my glasses"]
    XCTAssertTrue(
      connectButton.waitForExistence(timeout: 10),
      "HomeScreenView should show 'Connect my glasses' when no device is paired"
    )
  }

  /// Verifies that registering and pairing a device transitions the UI from the home
  /// screen to the camera screen with an active device.
  func testRegisterAndPairShowsCameraScreen() async {
    await pairDeviceWithCameraResources()
    waitForActiveDevice()
  }

  /// Verifies that the device state query reflects the correct number of paired devices.
  func testDeviceStateReflectsPairedDevices() async {
    // Initially no devices paired
    let state0 = await mockClient.getDeviceState()
    XCTAssertNotNil(state0, "getDeviceState should return a response")
    XCTAssertEqual(state0?["pairedDeviceCount"] as? Int, 0, "Should have 0 paired devices initially")

    // Register and pair a device
    await pairDeviceWithCameraResources()

    let state1 = await mockClient.getDeviceState()
    XCTAssertNotNil(state1, "getDeviceState should return a response after pairing")
    XCTAssertEqual(state1?["pairedDeviceCount"] as? Int, 1, "Should have 1 paired device")

    // Unpair
    _ = await mockClient.unpairDevice(deviceId: pairedDeviceId)
    pairedDeviceId = nil

    let state2 = await mockClient.getDeviceState()
    XCTAssertNotNil(state2, "getDeviceState should return a response after unpairing")
    XCTAssertEqual(state2?["pairedDeviceCount"] as? Int, 0, "Should have 0 paired devices after unpairing")
  }

  // MARK: - Device Activity Tests

  /// Verifies that doff is wear-only and keeps the device active — the transport
  /// and stream stay up across a doff/don, so the device never drops to the
  /// waiting state.
  func testDoffKeepsDeviceActive() async {
    await pairDeviceWithCameraResources()
    waitForActiveDevice()

    // Doff the device → device stays active (doff no longer tears down the link).
    _ = await mockClient.doff(deviceId: pairedDeviceId)
    XCTAssertFalse(
      app.staticTexts["Waiting for an active device"].exists,
      "Doff should not deactivate the device"
    )
    waitForActiveDevice()

    // Don the device → device remains active.
    _ = await mockClient.don(deviceId: pairedDeviceId)
    waitForActiveDevice()
  }

  /// Verifies that powering off makes the device inactive and powering on
  /// with don reactivates it.
  func testPowerCycleAffectsDeviceActivity() async {
    await pairDeviceWithCameraResources()
    waitForActiveDevice()

    // Power off → device becomes inactive
    let powerOffResult = await mockClient.powerOff(deviceId: pairedDeviceId)
    XCTAssertTrue(powerOffResult, "Power off should succeed")
    waitForInactiveDevice()

    // Power on + don → device becomes active again
    let powerOnResult = await mockClient.powerOn(deviceId: pairedDeviceId)
    XCTAssertTrue(powerOnResult, "Power on should succeed")
    let donResult = await mockClient.don(deviceId: pairedDeviceId)
    XCTAssertTrue(donResult, "Don should succeed")
    waitForActiveDevice()
  }

  // MARK: - Lifecycle Tests

  /// Verifies the explicit Start Session → Start Streaming flow brings up the
  /// live preview and capture controls.
  // TestRail: C1599889064, C1602923640, C1602923646
  func testStartSessionThenStreaming() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()
  }

  /// Verifies the capture row is disabled until the stream is streaming — starting
  /// a session shows the row greyed (present but not interactive).
  func testCaptureDisabledUntilStreaming() async {
    await pairDeviceWithCameraResources()
    waitForActiveDevice().tap()

    // Session started, no stream yet → Start Preview is offered; the capture row is
    // present but disabled until streaming begins.
    let startPreview = app.buttons["start_preview_button"]
    XCTAssertTrue(startPreview.waitForExistence(timeout: 15), "Start Preview should appear after starting a session")
    let capture = app.buttons["capture_button"]
    XCTAssertTrue(capture.exists, "Capture row should be present in session-ready")
    XCTAssertFalse(capture.isEnabled, "Capture should be disabled before streaming")
  }

  /// Verifies stopping the preview keeps the session alive, so the preview can be
  /// started again without starting a new session.
  func testStopStreamingKeepsSession() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    app.buttons["stop_preview_button"].tap()

    // Session stays active → Start Preview returns, Start Session does not.
    let startPreview = app.buttons["start_preview_button"]
    XCTAssertTrue(startPreview.waitForExistence(timeout: 15), "Start Preview should reappear after stopping the preview")
    XCTAssertFalse(app.buttons["start_session_button"].exists, "Session should remain active after stopping the preview")

    // Preview restarts on the same session.
    startPreview.tap()
    XCTAssertTrue(app.buttons["stop_preview_button"].waitForExistence(timeout: 20), "Preview should restart on the same session")
  }

  /// Verifies ending the session from session-ready returns the screen to the
  /// Start Session state. Stops the preview first, then ends via the bottom button.
  func testEndSession() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    app.buttons["stop_preview_button"].tap()
    XCTAssertTrue(
      app.buttons["start_preview_button"].waitForExistence(timeout: 15),
      "Should return to session-ready after stopping the preview"
    )

    app.buttons["end_session_button"].tap()
    XCTAssertTrue(
      app.buttons["start_session_button"].waitForExistence(timeout: 15),
      "Start Session should reappear after ending the session"
    )
  }

  /// Verifies End Session is available while streaming — the bottom button ends the
  /// session mid-preview on a single tap (the SDK cascades the stop to the stream).
  func testEndSessionAvailableWhileStreaming() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    let endSession = app.buttons["end_session_button"]
    XCTAssertTrue(endSession.exists, "End Session should be available while streaming")

    endSession.tap()
    XCTAssertTrue(
      app.buttons["start_session_button"].waitForExistence(timeout: 15),
      "Ending the session mid-stream should return to Start Session"
    )
  }

  // MARK: - Capture Tests

  /// Verifies starting and stopping a video recording while streaming.
  func testVideoRecordStartAndStop() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    // Start recording.
    let record = app.buttons["record_button"]
    record.tap()

    let recordingIndicator = app.staticTexts["recording_indicator"]
    XCTAssertTrue(
      recordingIndicator.waitForExistence(timeout: 10),
      "Recording indicator should appear after starting a recording"
    )
    XCTAssertTrue(waitUntilTimerCounting(recordingIndicator), "Recording should start writing before stopping")

    // Stop recording → a video preview/share sheet appears.
    record.tap()

    let closePreview = app.buttons["close_preview_button"]
    XCTAssertTrue(closePreview.waitForExistence(timeout: 15), "Video preview should appear after stopping a recording")
    closePreview.tap()

    // Back on the camera screen, ready to capture again.
    XCTAssertTrue(
      app.buttons["capture_button"].waitForExistence(timeout: 10),
      "Should return to the camera screen after dismissing the preview"
    )
  }

  /// Verifies the video preview offers Share after recording.
  func testVideoPreviewShowsShare() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    let record = app.buttons["record_button"]
    record.tap()
    XCTAssertTrue(app.staticTexts["recording_indicator"].waitForExistence(timeout: 10), "Recording should start")
    XCTAssertTrue(
      waitUntilTimerCounting(app.staticTexts["recording_indicator"]),
      "Recording should start writing before stopping"
    )
    record.tap()

    XCTAssertTrue(app.buttons["close_preview_button"].waitForExistence(timeout: 15), "Video preview should appear")
    XCTAssertTrue(app.buttons["share_button"].exists, "Preview should offer Share")

    app.buttons["close_preview_button"].tap()
  }

  /// Verifies a photo can still be captured while a video recording is in
  /// progress — capture stays available during recording.
  func testPhotoCaptureWhileRecording() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    app.buttons["record_button"].tap()

    let recordingIndicator = app.staticTexts["recording_indicator"]
    XCTAssertTrue(recordingIndicator.waitForExistence(timeout: 10), "Recording indicator should appear")

    // Capture a photo mid-recording → preview appears.
    app.buttons["capture_button"].tap()
    let closeButton = app.buttons["close_preview_button"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 15), "Photo preview should appear from a capture during recording")
    closeButton.tap()

    // Recording continues after dismissing the preview.
    XCTAssertTrue(recordingIndicator.waitForExistence(timeout: 10), "Recording should continue after capturing a photo")
    XCTAssertTrue(waitUntilTimerCounting(recordingIndicator), "Recording should still be writing after capturing a photo")

    // Stop the recording → video preview appears; dismiss it.
    app.buttons["record_button"].tap()
    let closeVideo = app.buttons["close_preview_button"]
    XCTAssertTrue(closeVideo.waitForExistence(timeout: 15), "Video preview should appear after stopping the recording")
    closeVideo.tap()
  }

  /// Verifies photo capture while streaming shows a preview and can be dismissed
  /// while remaining on the camera screen.
  // TestRail: C1619609872, C1619610952
  func testPhotoCaptureAndDismiss() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    app.buttons["capture_button"].tap()

    // Photo preview should appear.
    let closeButton = app.buttons["close_preview_button"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 15), "Photo preview close button should appear after capture")

    // The photo preview offers the same Share control as the video preview.
    XCTAssertTrue(app.buttons["share_button"].exists, "Photo preview should offer Share")

    // Dismiss the preview.
    closeButton.tap()

    // Should remain on the camera screen with capture available.
    XCTAssertTrue(
      app.buttons["capture_button"].waitForExistence(timeout: 10),
      "Should remain on the camera screen after dismissing the preview"
    )
  }

  /// Verifies that folding the glasses while previewing stops the stream and the device session,
  /// returning to the start-session screen (the device stays active).
  func testFoldDuringStreamingStopsStream() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    // Fold the glasses → the session ends by device, which stops streaming
    let foldResult = await mockClient.fold(deviceId: pairedDeviceId)
    XCTAssertTrue(foldResult, "Fold command should succeed")

    // The session-ended error surfaces an alert — dismiss it so the view hierarchy settles.
    let alertOK = app.alerts.buttons["OK"]
    XCTAssertTrue(alertOK.waitForExistence(timeout: 15), "Folding while streaming should surface the session-ended error alert")
    alertOK.tap()

    // Folding doffs the glasses and closes the hinge, tearing the session down (doff + fold); the
    // session-stop cascade then stops the stream. The device stays active, so the screen returns to
    // the start-session state.
    waitForActiveDevice()
  }

  // MARK: - Pause-while-recording

  /// Recording continues through a stream pause (single cap-touch tap), so the timer
  /// must keep counting — not freeze — for the whole pause. Guards the freeze-then-jump
  /// regression: a frame-driven timer stalls late in the pause; this one keeps ticking.
  func testRecordingTimerCountsThroughPause() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    let record = app.buttons["record_button"]
    record.tap()
    let timer = app.staticTexts["recording_indicator"]
    XCTAssertTrue(timer.waitForExistence(timeout: 10), "Recording indicator should appear")
    XCTAssertTrue(waitUntilTimerCounting(timer), "Recording clock should start counting before pausing")

    // Single tap → pause. Recording keeps running (held frame + audio).
    let pauseResult = await mockClient.captouchTap(deviceId: pairedDeviceId)
    XCTAssertTrue(pauseResult, "captouchTap (pause) should succeed")
    XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 10), "Paused overlay should appear")

    // Sample twice, both past the mock's feed-stop latency (~5s), so a frame-driven
    // timer would already be frozen. A steady timer is still advancing.
    let feedStopSettleSeconds: UInt32 = 6
    sleep(feedStopSettleSeconds)
    let firstSample = Self.seconds(timer.label)
    XCTAssertGreaterThanOrEqual(firstSample, 0, "Could not parse timer label '\(timer.label)' as mm:ss")
    let secondSampleGapSeconds: UInt32 = 3
    sleep(secondSampleGapSeconds)
    let secondSample = Self.seconds(timer.label)

    XCTAssertGreaterThan(
      secondSample,
      firstSample,
      "Recording timer stalled during the pause (first=\(firstSample)s, second=\(secondSample)s); "
        + "it should keep counting through the pause, not freeze-then-jump on resume."
    )

    // Tidy up: stop recording and dismiss the preview (Stop works while paused).
    record.tap()
    let closePreview = app.buttons["close_preview_button"]
    if closePreview.waitForExistence(timeout: 15) {
      closePreview.tap()
    }
  }

  /// Stopping a recording must work while the stream is paused (so a pause can't trap an
  /// in-progress recording): the Stop control stays enabled and finalizes the clip.
  func testStopRecordingWhilePaused() async {
    await pairDeviceWithCameraResources()
    startSessionAndStream()

    let record = app.buttons["record_button"]
    record.tap()
    let timer = app.staticTexts["recording_indicator"]
    XCTAssertTrue(timer.waitForExistence(timeout: 10), "Recording should start")
    XCTAssertTrue(waitUntilTimerCounting(timer), "Recording clock should start counting before pausing")

    // Single tap → pause mid-recording.
    let pauseResult2 = await mockClient.captouchTap(deviceId: pairedDeviceId)
    XCTAssertTrue(pauseResult2, "captouchTap (pause) should succeed")
    XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 10), "Paused overlay should appear")

    // Stop the recording while still paused → the clip finalizes and the preview opens.
    XCTAssertTrue(record.isEnabled, "Stop should stay enabled while paused")
    record.tap()
    XCTAssertTrue(
      app.buttons["close_preview_button"].waitForExistence(timeout: 15),
      "Stopping while paused should finalize the recording and open the capture preview"
    )
    app.buttons["close_preview_button"].tap()
  }

  /// Polls up to `maxSeconds` for the recording timer to start counting (first written
  /// frame), so pausing/sampling doesn't race the recorder's async start.
  private func waitUntilTimerCounting(_ timer: XCUIElement, maxSeconds: Int = 10) -> Bool {
    let predicate = NSPredicate { element, _ in
      guard let timer = element as? XCUIElement else { return false }
      return Self.seconds(timer.label) > 0
    }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: timer)
    return XCTWaiter.wait(for: [expectation], timeout: TimeInterval(maxSeconds)) == .completed
  }

  /// Parses an `mm:ss` recording-timer label into total seconds (-1 if malformed).
  private static func seconds(_ mmss: String) -> Int {
    let parts = mmss.split(separator: ":")
    guard parts.count == 2, let minutes = Int(parts[0]), let secs = Int(parts[1]) else { return -1 }
    return minutes * 60 + secs
  }
}
