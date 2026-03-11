/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class CameraAccessUITests: XCTestCase {

  private let app = XCUIApplication()

  override func setUpWithError() throws {
    continueAfterFailure = false
    app.launchArguments = ["--ui-testing"]
  }

  // MARK: - Helpers

  /// Waits for the "Start streaming" button to exist and be enabled (mock device active).
  private func waitForStartStreamingEnabled(timeout: TimeInterval = 15) -> XCUIElement {
    let startButton = app.buttons["Start streaming"]
    XCTAssertTrue(startButton.waitForExistence(timeout: timeout), "Start streaming button should appear")

    let enabledPredicate = NSPredicate(format: "isEnabled == true")
    expectation(for: enabledPredicate, evaluatedWith: startButton)
    waitForExpectations(timeout: timeout)

    return startButton
  }

  /// Starts streaming and waits for the StreamView to appear.
  private func startStreaming(timeout: TimeInterval = 15) {
    let startButton = waitForStartStreamingEnabled(timeout: timeout)
    startButton.tap()

    let stopButton = app.buttons["Stop streaming"]
    XCTAssertTrue(stopButton.waitForExistence(timeout: timeout), "Stop streaming button should appear after starting")
  }

  // MARK: - Tests

  /// Verifies the app launches directly to the streaming screen (NonStreamView)
  /// when MockDeviceKit is auto-configured via --ui-testing launch argument.
  @MainActor
  func testAppLaunchShowsStreamingScreen() {
    app.launch()

    // Mock device auto-paired → should skip HomeScreenView and show NonStreamView
    let title = app.staticTexts["Stream Your Glasses Camera"]
    XCTAssertTrue(title.waitForExistence(timeout: 10), "NonStreamView title should be visible")

    let startButton = app.buttons["Start streaming"]
    XCTAssertTrue(startButton.exists, "Start streaming button should be present")
  }

  /// Verifies the complete start → stop streaming flow.
  @MainActor
  func testStartAndStopStreaming() {
    app.launch()

    // Wait for device to become active and start streaming
    startStreaming()

    // Stop streaming
    let stopButton = app.buttons["Stop streaming"]
    stopButton.tap()

    // Should return to NonStreamView
    let startButton = app.buttons["Start streaming"]
    XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Should return to NonStreamView after stopping")
    XCTAssertTrue(app.staticTexts["Stream Your Glasses Camera"].exists, "NonStreamView title should reappear")
  }

  /// Verifies photo capture shows a preview and can be dismissed while continuing to stream.
  @MainActor
  func testPhotoCaptureAndDismiss() {
    app.launch()

    // Start streaming
    startStreaming()

    // Tap the capture button
    let captureButton = app.buttons["capture_photo_button"]
    XCTAssertTrue(captureButton.waitForExistence(timeout: 10), "Capture button should be visible during streaming")
    captureButton.tap()

    // Photo preview should appear
    let closeButton = app.buttons["close_preview_button"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 15), "Photo preview close button should appear after capture")

    // Dismiss the preview
    closeButton.tap()

    // Should still be streaming after dismissing preview
    let stopButton = app.buttons["Stop streaming"]
    XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Should still be streaming after dismissing photo preview")

    // Stop streaming
    stopButton.tap()

    // Should return to NonStreamView
    let startButton = app.buttons["Start streaming"]
    XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Should return to NonStreamView after stopping")
  }
}
