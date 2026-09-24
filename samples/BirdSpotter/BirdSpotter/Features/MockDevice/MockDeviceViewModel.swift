/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceViewModel.swift
//  birdspotter
//

import Foundation
import UIKit

/// What the mock panel shows: the kit's switch, the pairs it holds and which one the controls
/// are aimed at, and the last value each control was set to — so a slider reads what the
/// glasses were told, not a default that has drifted from it.
nonisolated struct MockDeviceUiState: Equatable, Sendable {
  /// Whether the kit is standing in for the real SDK.
  var isEnabled = false

  /// Set while a flip is in flight — the kit waits for the open session to end first, and
  /// the switch must not be thrown twice into that wait.
  var isFlipping = false

  /// The pairs the kit holds, in the order they were paired.
  var devices: [MockDeviceInfo] = []

  /// The pair every control below is aimed at — `nil` when the kit holds none.
  var selectedDeviceId: String?

  /// The model the next **Pair** makes.
  var model: MockGlassesModel = .rayBanMeta

  var batteryLevel = 80
  var isCharging = false
  var thermal: GlassesThermalLevel = .nominal

  var cameraAccess: GlassesAccess = .granted
  var microphoneAccess: GlassesAccess = .granted

  var speechSource: MockSpeechSource = .injected
  var speechText = ""

  var pose: MockMotionPose = .level
  var displayServerPort: UInt16?

  /// The last thing the panel has to say — a file that was set, what the kit answered a
  /// voice launch with. One line, replaced by the next.
  var notice: String?

  var selectedDevice: MockDeviceInfo? {
    devices.first { $0.id == selectedDeviceId }
  }

  /// Whether the controls have a pair to act on.
  var hasSelection: Bool {
    selectedDevice != nil
  }
}

/// Drives the Mock Device Kit panel: the switch, the pairs, and every control the kit offers
/// on the selected pair.
///
/// **Thin on purpose.** Each control is one call on ``MockDeviceRepository``; what this class
/// adds is the choice of *which* pair the call goes to, kept steady as pairs come and go (see
/// ``selectedDeviceId(after:current:)``), and the last-set values the panel reads back.
@MainActor
@Observable
final class MockDeviceViewModel {

  private let mockDevice: any MockDeviceRepository

  private(set) var uiState = MockDeviceUiState()

  init(mockDevice: any MockDeviceRepository) {
    self.mockDevice = mockDevice
    uiState.isEnabled = mockDevice.isEnabled
  }

  /// Follows the switch and the pair list for as long as the panel is up. Cold, per the
  /// architecture contract: the caller's task is the subscription's whole life.
  func observe() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { @MainActor [self] in
        for await isEnabled in mockDevice.isEnabledStream() {
          uiState.isEnabled = isEnabled
          #if targetEnvironment(simulator)
          if isEnabled, uiState.displayServerPort == nil {
            let port = await mockDevice.startDisplayServer()
            uiState.displayServerPort = port
            if port == nil {
              uiState.notice = displayServerErrorMessage
            }
          } else if uiState.displayServerPort != nil {
            await mockDevice.stopDisplayServer()
            uiState.displayServerPort = nil
          }
          #endif
        }
      }
      group.addTask { @MainActor [self] in
        for await devices in mockDevice.devicesStream() {
          uiState.devices = devices
          select(selectedDeviceId(after: devices, current: uiState.selectedDeviceId))
        }
      }
    }
  }

  // MARK: The switch

  func setEnabled(_ enabled: Bool) {
    guard !uiState.isFlipping, enabled != uiState.isEnabled else { return }
    uiState.isFlipping = true
    Task {
      await mockDevice.setEnabled(enabled)
      uiState.isFlipping = false
    }
  }

  // MARK: The pairs

  func choose(model: MockGlassesModel) {
    uiState.model = model
  }

  func pair() {
    let model = uiState.model
    Task {
      do {
        let paired = try await mockDevice.pair(model: model)
        select(paired.id)
      } catch {
        uiState.notice = "The kit is not enabled."
      }
    }
  }

  func unpair() {
    guard let id = uiState.selectedDeviceId else { return }
    mockDevice.unpair(id)
  }

  func select(_ id: String?) {
    uiState.selectedDeviceId = id
  }

  /// The selected pair's panel as the kit draws it, or `nil` when the pair has none. The view
  /// belongs to the pair it was made for, so the screen asks again whenever the selection
  /// moves.
  func displayPreview() -> UIView? {
    guard let device = uiState.selectedDevice, device.model.hasDisplay else { return nil }
    return mockDevice.displayPreview(device.id)
  }

  // MARK: Device state

  func powerOn() { onSelected(mockDevice.powerOn) }
  func powerOff() { onSelected(mockDevice.powerOff) }
  func don() { onSelected(mockDevice.don) }
  func doff() { onSelected(mockDevice.doff) }
  func fold() { onSelected(mockDevice.fold) }
  func unfold() { onSelected(mockDevice.unfold) }

  func setBatteryLevel(_ level: Int) {
    uiState.batteryLevel = level
    onSelected { mockDevice.setBatteryLevel($0, level: level) }
  }

  func setCharging(_ isCharging: Bool) {
    uiState.isCharging = isCharging
    onSelected { mockDevice.setCharging($0, isCharging: isCharging) }
  }

  func setThermal(_ level: GlassesThermalLevel) {
    uiState.thermal = level
    onSelected { mockDevice.setThermal($0, level: level) }
  }

  // MARK: Grants

  /// Sets both what a read answers and what a request comes back with: the panel offers
  /// one switch per grant, and a grant that reads denied but is granted on request is a
  /// state nobody demoing needs.
  func setAccess(_ permission: GlassesPermission, _ access: GlassesAccess) {
    switch permission {
    case .camera: uiState.cameraAccess = access
    case .microphone: uiState.microphoneAccess = access
    }
    mockDevice.setAccess(permission, access)
    mockDevice.setRequestResult(permission, access)
  }

  // MARK: Camera

  func useCameraFeed(_ url: URL) {
    guard let stashed = stash(url) else { return }
    onSelected { mockDevice.setCameraFeed($0, fileURL: stashed) }
    uiState.notice = "Camera feed: \(url.lastPathComponent)"
  }

  func usePhoneCamera(_ facing: MockCameraFacing) {
    onSelected { mockDevice.setCameraFeed($0, facing: facing) }
    uiState.notice = "Camera feed: the phone's \(facing == .front ? "front" : "back") camera"
  }

  func useCapturedPhoto(_ url: URL) {
    guard let stashed = stash(url) else { return }
    onSelected { mockDevice.setCapturedPhoto($0, fileURL: stashed) }
    uiState.notice = "Captured photo: \(url.lastPathComponent)"
  }

  func failNextCapture() {
    onSelected(mockDevice.simulateCaptureFailure)
    uiState.notice = "The next capture will fail."
  }

  // MARK: Inputs

  func tap() { onSelected(mockDevice.tap) }
  func tapAndHold() { onSelected(mockDevice.tapAndHold) }
  func navigate(_ direction: MockNavDirection) { onSelected { mockDevice.navigate($0, direction) } }
  func select() { onSelected(mockDevice.select) }
  func back() { onSelected(mockDevice.back) }
  func pressCapture(_ press: MockCapturePress) { onSelected { mockDevice.pressCapture($0, press) } }
  func pressActionButton() { onSelected(mockDevice.pressActionButton) }

  // MARK: Speech

  func setSpeechSource(_ source: MockSpeechSource) {
    uiState.speechSource = source
    onSelected { mockDevice.setSpeechSource($0, source) }
  }

  func setSpeechText(_ text: String) {
    uiState.speechText = text
  }

  func sendTranscription(isFinal: Bool) {
    let text = uiState.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    onSelected { mockDevice.simulateTranscription($0, text: text, isFinal: isFinal) }
    if isFinal { uiState.speechText = "" }
  }

  func sendSpeechError() {
    onSelected { mockDevice.simulateSpeechError($0, message: "Simulated recogniser failure") }
  }

  func completeSpeech() {
    onSelected(mockDevice.simulateSpeechCompletion)
  }

  // MARK: Motion

  func setPose(_ pose: MockMotionPose) {
    uiState.pose = pose
    onSelected { mockDevice.setMotionPose($0, pose) }
  }

  // MARK: Voice

  func simulateVoiceLaunch() {
    guard let id = uiState.selectedDeviceId else { return }
    let answer = mockDevice.simulateVoiceLaunch(id)
    uiState.notice = answer.map { "Voice launch: \($0)" } ?? "Voice launch: nothing was listening."
  }

  // MARK: -

  private func onSelected(_ control: (String) -> Void) {
    guard let id = uiState.selectedDeviceId else { return }
    control(id)
  }

  /// A copy of a picked file the kit can read whenever it likes.
  ///
  /// The picker hands over a security-scoped URL that stops answering the moment the scope
  /// is released, and the kit opens the file later — when a stream starts, when a capture
  /// is asked for — so the bytes have to be somewhere of the app's own by then.
  private func stash(_ url: URL) -> URL? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let directory = URL.cachesDirectory.appending(path: "mock-device", directoryHint: .isDirectory)
    let target = directory.appending(path: url.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: url, to: target)
      return target
    } catch {
      BirdLog.error(.glasses, "mock device — could not copy \(url.lastPathComponent)", error)
      uiState.notice = "Could not read \(url.lastPathComponent)."
      return nil
    }
  }
}

/// Which pair the controls should be aimed at once the kit's list has changed.
///
/// The current pair, for as long as the kit still holds it — a new pair being added must not
/// yank the controls off the one somebody is driving. When it has gone, the pair added most
/// recently: after a pair, that is the pair just made, and after an unpair it is the closest
/// thing to where the controls were. Nothing, when the kit holds nothing.
nonisolated func selectedDeviceId(after devices: [MockDeviceInfo], current: String?) -> String? {
  if let current, devices.contains(where: { $0.id == current }) {
    return current
  }
  return devices.last?.id
}

private let displayServerErrorMessage = "The Chrome preview server could not be started."
