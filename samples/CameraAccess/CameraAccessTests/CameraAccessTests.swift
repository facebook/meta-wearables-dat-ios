/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CameraAccess
import Foundation
import MWDATCamera
import MWDATCore
import MWDATMockDevice
import Observation
import SwiftUI
import UIKit
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

@MainActor
final class ViewModelIntegrationTests: XCTestCase {

  private var mockDevice: MockGlasses?
  private var cameraKit: MockCameraKit?
  private var viewModel: CameraViewModel?

  override func setUp() async throws {
    try await super.setUp()
    try? Wearables.configure()

    MockDeviceKit.shared.enable()

    // Pair mock device and set up camera kit
    let pairedMockDevice = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
    mockDevice = pairedMockDevice
    cameraKit = pairedMockDevice.services.camera

    // Power on and don the device to make it available for session start.
    pairedMockDevice.powerOn()
    pairedMockDevice.don()

    // Wait for device to be available in Wearables
    try await Task.sleep(nanoseconds: 1_000_000_000)
  }

  override func tearDown() async throws {
    viewModel?.endSession()
    viewModel = nil
    await MockDeviceKit.shared.disable()
    mockDevice = nil
    cameraKit = nil
    try await super.tearDown()
  }

  // MARK: - Video Streaming Flow Tests

  func testVideoStreamingFlow() async throws {
    guard let camera = cameraKit else {
      XCTFail("Mock device and camera should be available")
      return
    }

    guard let videoURL = Bundle.main.url(forResource: "plant", withExtension: "mp4")
    else {
      XCTFail("Test resources not found")
      return
    }

    // Setup camera feed
    camera.setCameraFeed(fileURL: videoURL)

    let viewModel = CameraViewModel(wearables: Wearables.shared)
    self.viewModel = viewModel

    // Wait for the mock device to be detected
    await observeUntil(timeout: 5) { viewModel.hasActiveDevice }

    // Initially nothing is running
    XCTAssertEqual(viewModel.streamState, .stopped)
    XCTAssertFalse(viewModel.hasSession)
    XCTAssertFalse(viewModel.isStreaming)
    XCTAssertFalse(viewModel.hasReceivedFirstFrame)
    XCTAssertNil(viewModel.currentVideoFrame)

    // Step 1: start a session (no stream yet)
    viewModel.startSession()
    await observeUntil(timeout: 5) { viewModel.isSessionActive }
    XCTAssertTrue(viewModel.isSessionActive)
    XCTAssertFalse(viewModel.hasStream)

    // Step 2: start streaming
    await viewModel.startStreaming()

    // Wait for streaming to establish
    await observeUntil(timeout: 10) {
      viewModel.isStreaming && viewModel.hasReceivedFirstFrame && viewModel.currentVideoFrame != nil
    }

    // Verify streaming is active and receiving frames
    XCTAssertTrue(viewModel.isStreaming)
    XCTAssertTrue(viewModel.hasReceivedFirstFrame)
    XCTAssertNotNil(viewModel.currentVideoFrame)

    // Stop streaming — session stays connected
    viewModel.stopStreaming()
    await observeUntil(timeout: 5) { !viewModel.isStreaming && !viewModel.hasStream }

    XCTAssertFalse(viewModel.isStreaming)
    XCTAssertEqual(viewModel.streamState, .stopped)
    XCTAssertTrue(viewModel.isSessionActive)

    // End the session
    viewModel.endSession()
    await observeUntil(timeout: 5) { !viewModel.hasSession }
    XCTAssertFalse(viewModel.hasSession)
  }

  // MARK: - Photo Capture Flow Tests

  func testStreamingAndPhotoCaptureFlow() async throws {
    guard let camera = cameraKit else {
      XCTFail("Mock device and camera should be available")
      return
    }

    guard let videoURL = Bundle.main.url(forResource: "plant", withExtension: "mp4"),
      let imageURL = Bundle.main.url(forResource: "plant", withExtension: "png")
    else {
      XCTFail("Test resources not found")
      return
    }

    // Setup camera feed
    camera.setCameraFeed(fileURL: videoURL)
    camera.setCapturedImage(fileURL: imageURL)

    let viewModel = CameraViewModel(wearables: Wearables.shared)
    self.viewModel = viewModel

    // Wait for the mock device to be detected
    await observeUntil(timeout: 5) { viewModel.hasActiveDevice }

    // Initially nothing is running
    XCTAssertEqual(viewModel.streamState, .stopped)
    XCTAssertFalse(viewModel.isStreaming)
    XCTAssertNil(viewModel.activePreview)

    // Start a session, then start streaming
    viewModel.startSession()
    await observeUntil(timeout: 5) { viewModel.isSessionActive }
    await viewModel.startStreaming()

    // Wait for streaming to establish
    await observeUntil(timeout: 10) {
      viewModel.isStreaming && viewModel.hasReceivedFirstFrame && viewModel.currentVideoFrame != nil
    }

    XCTAssertTrue(viewModel.isStreaming)
    XCTAssertTrue(viewModel.hasReceivedFirstFrame)
    XCTAssertNotNil(viewModel.currentVideoFrame)

    // Capture photo while streaming — opens the capture preview
    viewModel.capturePhoto()
    await observeUntil(timeout: 10) { viewModel.activePreview != nil }

    // Verify a photo preview opened while the stream stayed live
    if case .photo = viewModel.activePreview {
      // expected
    } else {
      XCTFail("Expected a photo capture preview")
    }
    XCTAssertTrue(viewModel.isStreaming)

    // Dismiss the preview, then tear down
    viewModel.dismissCapturePreview()
    XCTAssertNil(viewModel.activePreview)

    viewModel.endSession()
    await observeUntil(timeout: 5) { !viewModel.isStreaming && !viewModel.hasSession }

    XCTAssertFalse(viewModel.isStreaming)
    XCTAssertFalse(viewModel.hasSession)
  }

  // MARK: - Pause/Resume Flow Tests

  func testStreamPausedViaSingleTapKeepsPreviewVisible() async throws {
    guard let camera = cameraKit, let device = mockDevice else {
      XCTFail("Mock device and camera should be available")
      return
    }

    guard let videoURL = Bundle.main.url(forResource: "plant", withExtension: "mp4") else {
      XCTFail("Test resources not found")
      return
    }

    camera.setCameraFeed(fileURL: videoURL)

    let viewModel = CameraViewModel(wearables: Wearables.shared)
    self.viewModel = viewModel

    await observeUntil(timeout: 5) { viewModel.hasActiveDevice }
    viewModel.startSession()
    await observeUntil(timeout: 5) { viewModel.isSessionActive }
    await viewModel.startStreaming()
    await observeUntil(timeout: 10) {
      viewModel.isStreaming && viewModel.hasReceivedFirstFrame && viewModel.currentVideoFrame != nil
    }

    // Single tap on the touchpad pauses the stream.
    device.services.captouch.tap()
    await observeUntil(timeout: 5) { viewModel.streamState == .paused }

    // Regression: paused must keep the last frame visible (the bug hid it).
    XCTAssertTrue(viewModel.isPaused)
    XCTAssertNotNil(viewModel.currentVideoFrame, "Last frame should be retained while paused")
    XCTAssertTrue(viewModel.showsLivePreview, "Preview should remain visible when paused")

    // Single tap again → resumes streaming, preview still visible.
    device.services.captouch.tap()
    await observeUntil(timeout: 5) { viewModel.isStreaming }
    XCTAssertFalse(viewModel.isPaused, "Second tap should exit the paused state")
    XCTAssertTrue(viewModel.showsLivePreview)

    viewModel.endSession()
    await observeUntil(timeout: 5) { !viewModel.hasSession }
    XCTAssertFalse(viewModel.hasSession)
  }

  func testBackgroundingActiveStreamStopsSessionWithoutShowingError() async throws {
    guard let camera = cameraKit else {
      XCTFail("Mock device and camera should be available")
      return
    }

    guard let videoURL = Bundle.main.url(forResource: "plant", withExtension: "mp4") else {
      XCTFail("Test resources not found")
      return
    }

    camera.setCameraFeed(fileURL: videoURL)

    let viewModel = CameraViewModel(wearables: Wearables.shared)
    self.viewModel = viewModel

    await observeUntil(timeout: 5) { viewModel.hasActiveDevice }
    viewModel.startSession()
    await observeUntil(timeout: 5) { viewModel.isSessionActive }
    await viewModel.startStreaming()
    await observeUntil(timeout: 10) {
      viewModel.isStreaming && viewModel.hasReceivedFirstFrame && viewModel.currentVideoFrame != nil
    }

    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

    await observeUntil(timeout: 5) { !viewModel.hasSession }
    XCTAssertFalse(viewModel.hasSession)
    XCTAssertEqual(viewModel.sessionState, .stopped)
    XCTAssertEqual(viewModel.streamState, .stopped)
    XCTAssertFalse(viewModel.showError)
  }
}

// MARK: - Test Helpers

/// Thread-safe one-shot flag for protecting continuation resumption.
private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var resumed = false
  func tryResume() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !resumed else { return false }
    resumed = true
    return true
  }
}

/// Reactively waits for a condition on @Observable objects to become true.
/// Uses `withObservationTracking` to wake up immediately on property changes
/// instead of polling on a fixed interval.
@MainActor
private func observeUntil(
  timeout: TimeInterval,
  file: StaticString = #filePath,
  line: UInt = #line,
  condition: @escaping () -> Bool
) async {
  guard !condition() else { return }

  let deadline = ContinuousClock.now + .seconds(timeout)

  while !condition() {
    guard ContinuousClock.now < deadline else {
      XCTFail("Condition not met within \(timeout) seconds", file: file, line: line)
      return
    }

    await withUnsafeContinuation { cont in
      let once = ResumeOnce()

      withObservationTracking {
        _ = condition()
      } onChange: {
        if once.tryResume() { cont.resume() }
      }

      // Periodic fallback so we can re-evaluate the deadline
      Task {
        try? await Task.sleep(for: .milliseconds(100))
        if once.tryResume() { cont.resume() }
      }
    }
  }
}
