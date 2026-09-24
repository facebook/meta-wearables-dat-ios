/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatMockDeviceRepository.swift
//  birdspotter
//

import Foundation
import MWDATCore
import MWDATMockDevice
import UIKit

/// ``MockDeviceRepository`` over Meta's Mock Device Kit.
///
/// **Construction restores the last choice.** The kit is a process singleton that forgets
/// everything at exit, so an app relaunched with the mock switched on would otherwise come up
/// on real glasses until somebody found the switch again. Building this repository reads
/// ``MockDeviceSettingsStore``, and if the mock was on it enables the kit and pairs the model
/// that was paired last — powered, unfolded and worn, the way ``pair(model:)`` always leaves
/// a pair — before anything above it has asked a question.
///
/// **Flipping is ordered.** The kit swaps the SDK's registration and device providers live,
/// and the app's own streams follow the swap without being re-subscribed; what the swap does
/// not do is end a lease that is open at the moment — a session, or the voice channel, each
/// of which is bound to a device the swap is about to take away — which is why both directions
/// ask the session repository and the voice repository to close theirs and wait for them to go
/// before touching the kit.
///
/// The kit hands back its pairs as protocol objects with no lookup by identifier, so this
/// keeps its own table — the reason every control here is a dictionary read followed by one
/// SDK call.
nonisolated final class DatMockDeviceRepository: MockDeviceRepository, @unchecked Sendable {
  // @unchecked: every mutable field is read and written under `lock`.

  private let link: DatGlassesSessionRepository
  private let voice: DatGlassesVoiceRepository
  private let settings: MockDeviceSettingsStore
  private let kit: any MockDeviceKitInterface

  private let lock = NSLock()

  /// The pairs the kit holds, in the order they were paired — the order the panel lists.
  private var pairs: [(info: MockDeviceInfo, glasses: any MockGlasses)] = []

  private var enabledWatchers: [UUID: AsyncStream<Bool>.Continuation] = [:]
  private var devicesWatchers: [UUID: AsyncStream<[MockDeviceInfo]>.Continuation] = [:]

  init(
    link: DatGlassesSessionRepository,
    voice: DatGlassesVoiceRepository,
    settings: MockDeviceSettingsStore,
    kit: any MockDeviceKitInterface = MockDeviceKit.shared
  ) {
    self.link = link
    self.voice = voice
    self.settings = settings
    self.kit = kit
    // Off the launching thread: enabling the kit and pairing a device are the SDK's own
    // work, measured in whole seconds on a cold start, and the first frame must not wait
    // on them. The switch and the pair list are streams, so everything above here learns
    // of the restored pair the same way it would learn of one paired by hand.
    guard settings.isEnabled else { return }
    Task.detached(priority: .userInitiated) { [self] in
      restore()
    }
  }

  /// The relaunch path — see the type's own doc.
  private func restore() {
    let startedAt = ContinuousClock.now
    enableKit()
    do {
      _ = try pairNow(model: settings.model)
    } catch {
      BirdLog.error(.glasses, "mock device — could not restore the pair: \(error)")
    }
    publishEnabled()
    BirdLog.info(.glasses, "mock device — restored in \(ContinuousClock.now - startedAt)")
  }

  // MARK: - The switch

  var isEnabled: Bool { kit.isEnabled }

  func isEnabledStream() -> AsyncStream<Bool> {
    AsyncStream { continuation in
      let id = UUID()
      let current = lock.withLock {
        enabledWatchers[id] = continuation
        return kit.isEnabled
      }
      continuation.yield(current)
      continuation.onTermination = { [weak self] _ in
        self?.lock.withLock { _ = self?.enabledWatchers.removeValue(forKey: id) }
      }
    }
  }

  func setEnabled(_ enabled: Bool) async {
    guard enabled != kit.isEnabled else { return }
    // The two things the swap cannot do for itself — see the type's doc. The voice channel
    // stays closed for the length of the swap, so its reopen lands on the swapped-in pair.
    await link.endActiveSessions()
    let startedAt = ContinuousClock.now
    await voice.withChannelClosed {
      if !enabled {
        await kit.stopTestServer()
      }
      // Detached, so the swap — the SDK's own work, and slow — never runs on whichever
      // actor asked for it, which is the main one when it is the switch in Settings.
      await Task.detached(priority: .userInitiated) { [self] in
        if enabled {
          enableKit()
        } else {
          kit.disable()
          lock.withLock { pairs.removeAll() }
          publishDevices()
        }
      }.value
    }
    settings.isEnabled = enabled
    publishEnabled()
    BirdLog.info(
      .glasses,
      "mock device — kit \(enabled ? "enabled" : "disabled") in \(ContinuousClock.now - startedAt)"
    )
  }

  private func enableKit() {
    let startedAt = ContinuousClock.now
    kit.enable(
      config: MockDeviceKitConfig(
        initiallyRegistered: true,
        initialPermissionsGranted: true
      ))
    BirdLog.debug(.glasses, "mock device — kit.enable took \(ContinuousClock.now - startedAt)")
  }

  private func publishEnabled() {
    let (watchers, value) = lock.withLock { (Array(enabledWatchers.values), kit.isEnabled) }
    watchers.forEach { $0.yield(value) }
  }

  // MARK: - The pairs

  func devicesStream() -> AsyncStream<[MockDeviceInfo]> {
    AsyncStream { continuation in
      let id = UUID()
      let current = lock.withLock {
        devicesWatchers[id] = continuation
        return pairs.map(\.info)
      }
      continuation.yield(current)
      continuation.onTermination = { [weak self] _ in
        self?.lock.withLock { _ = self?.devicesWatchers.removeValue(forKey: id) }
      }
    }
  }

  func pair(model: MockGlassesModel) async throws(MockDeviceError) -> MockDeviceInfo {
    // Detached, for the reason the restore is: pairing is the SDK's own work — a whole
    // second on a cold start — and the thread that pressed the panel's button is the main
    // one.
    let pairing = Task.detached(priority: .userInitiated) { [self] in
      try pairNow(model: model)
    }
    do {
      return try await pairing.value
    } catch {
      throw error as? MockDeviceError ?? .notEnabled
    }
  }

  /// The pair itself, on whatever thread is calling — the restore's and ``pair(model:)``'s.
  private func pairNow(model: MockGlassesModel) throws(MockDeviceError) -> MockDeviceInfo {
    let startedAt = ContinuousClock.now
    let glasses: any MockGlasses
    do {
      glasses = try kit.pairGlasses(model: model.datModel)
    } catch {
      throw .notEnabled
    }
    BirdLog.debug(.glasses, "mock device — kit.pairGlasses took \(ContinuousClock.now - startedAt)")
    let info = MockDeviceInfo(id: glasses.deviceIdentifier, model: model)
    lock.withLock { pairs.append((info, glasses)) }
    // Up and ready, because a pair that has to be switched on, opened and put on before
    // it answers is three taps between the demo and the thing it is demonstrating.
    glasses.powerOn()
    glasses.unfold()
    glasses.don()
    // **And with a picture behind its camera, because a mock pair without one is a crash,
    // not an empty stream.** The kit refuses to stream from a pair whose feed was never
    // set, and it refuses fatally — so a session opened on a pair restored at launch, whose
    // feed choice the kit forgot with everything else, took the app down on the first tap
    // of the glasses. The phone's back camera is the default that always exists; the panel
    // can swap in a file or the front camera afterwards, the way it always could.
    glasses.services.camera.setCameraFeed(cameraFacing: .back)
    settings.model = model
    publishDevices()
    BirdLog.info(.glasses, "mock device — paired \(model.displayName) as \(info.id)")
    return info
  }

  func unpair(_ id: String) {
    guard
      let glasses = lock.withLock({ () -> (any MockGlasses)? in
        guard let index = pairs.firstIndex(where: { $0.info.id == id }) else { return nil }
        return pairs.remove(at: index).glasses
      })
    else { return }
    kit.unpairDevice(glasses)
    publishDevices()
  }

  private func publishDevices() {
    let (watchers, value) = lock.withLock { (Array(devicesWatchers.values), pairs.map(\.info)) }
    watchers.forEach { $0.yield(value) }
  }

  /// The pair a control is aimed at, or `nil` when it has gone — in which case the control
  /// is quietly a no-op, per the protocol's doc.
  private func glasses(_ id: String) -> (any MockGlasses)? {
    lock.withLock { pairs.first { $0.info.id == id }?.glasses }
  }

  // MARK: - Device state

  func powerOn(_ id: String) { glasses(id)?.powerOn() }
  func powerOff(_ id: String) { glasses(id)?.powerOff() }
  func don(_ id: String) { glasses(id)?.don() }
  func doff(_ id: String) { glasses(id)?.doff() }
  func fold(_ id: String) { glasses(id)?.fold() }
  func unfold(_ id: String) { glasses(id)?.unfold() }

  func setBatteryLevel(_ id: String, level: Int) {
    glasses(id)?.setBatteryLevel(min(max(level, 0), 100))
  }

  func setCharging(_ id: String, isCharging: Bool) {
    glasses(id)?.setChargingState(isCharging ? .charging : .notCharging)
  }

  func setThermal(_ id: String, level: GlassesThermalLevel) {
    // The app collapses the SDK's ladder to three rungs; this picks one rung per word,
    // chosen so the collapse reads back the word that was set.
    let datLevel: ThermalLevel =
      switch level {
      case .nominal: .none
      case .elevated: .moderate
      case .critical: .critical
      }
    glasses(id)?.setThermalLevel(datLevel)
  }

  // MARK: - Grants

  func setAccess(_ permission: GlassesPermission, _ access: GlassesAccess) {
    kit.permissions.set(permission.datPermission, access.datStatus)
  }

  func setRequestResult(_ permission: GlassesPermission, _ access: GlassesAccess) {
    kit.permissions.setRequestResult(permission.datPermission, result: access.datStatus)
  }

  // MARK: - Camera

  func setCameraFeed(_ id: String, fileURL: URL) {
    glasses(id)?.services.camera.setCameraFeed(fileURL: fileURL)
  }

  func setCameraFeed(_ id: String, facing: MockCameraFacing) {
    let datFacing: CameraFacing =
      switch facing {
      case .front: .front
      case .back: .back
      }
    glasses(id)?.services.camera.setCameraFeed(cameraFacing: datFacing)
  }

  func setCapturedPhoto(_ id: String, fileURL: URL) {
    guard let services = glasses(id)?.services else { return }
    // Both routes a photograph can take out of the mock — the stream's own still and the
    // capture capability's — so the same picture comes back whichever one the app asks.
    services.camera.setCapturedImage(fileURL: fileURL)
    services.cameraCapture.setCapturedPhoto(fileURL: fileURL)
  }

  func simulateCaptureFailure(_ id: String) {
    glasses(id)?.services.cameraCapture.simulateCaptureFailure()
  }

  // MARK: - Inputs

  func tap(_ id: String) { glasses(id)?.services.captouch.tap() }
  func tapAndHold(_ id: String) { glasses(id)?.services.captouch.tapAndHold() }

  func navigate(_ id: String, _ direction: MockNavDirection) {
    guard let input = glasses(id)?.services.input else { return }
    switch direction {
    case .up: input.navUp(source: .captouch)
    case .down: input.navDown(source: .captouch)
    case .left: input.navLeft(source: .captouch)
    case .right: input.navRight(source: .captouch)
    }
  }

  func select(_ id: String) { glasses(id)?.services.input.select(source: .captouch) }
  func back(_ id: String) { glasses(id)?.services.input.back(source: .captouch) }

  func pressCapture(_ id: String, _ press: MockCapturePress) {
    let pressType: CapturePressType =
      switch press {
      case .shortPress: .shortPress
      case .hold: .hold
      case .doublePress: .doublePress
      }
    glasses(id)?.services.input.capture(pressType: pressType)
  }

  func pressActionButton(_ id: String) {
    glasses(id)?.services.input.button(type: .action)
  }

  // MARK: - Speech

  func setSpeechSource(_ id: String, _ source: MockSpeechSource) {
    let datSource: MWDATMockDevice.MockSpeechSource =
      switch source {
      case .injected: .injected
      case .liveDeviceAsr: .liveDeviceAsr
      }
    glasses(id)?.services.speech.setTranscriptionSource(datSource)
  }

  func simulateTranscription(_ id: String, text: String, isFinal: Bool) {
    glasses(id)?.services.speech.simulateTranscription(
      text: text,
      isFinal: isFinal,
      confidence: 1
    )
  }

  func simulateSpeechError(_ id: String, message: String) {
    glasses(id)?.services.speech.simulateError(errorCode: 1, message: message)
  }

  func simulateSpeechCompletion(_ id: String) {
    glasses(id)?.services.speech.simulateCompletion()
  }

  // MARK: - Motion

  func setMotionPose(_ id: String, _ pose: MockMotionPose) {
    glasses(id)?.services.motion.setMotionFeed(motionSamples(for: pose))
  }

  // MARK: - Display

  func startDisplayServer() async -> UInt16? {
    try? await kit.startTestServer(port: mockDisplayServerPort)
  }

  func stopDisplayServer() async {
    await kit.stopTestServer()
  }

  @MainActor func displayPreview(_ id: String) -> UIView? {
    glasses(id)?.services.display.createPreviewView()
  }

  @discardableResult
  func sendDisplayClick(_ id: String, identifier: String) -> Bool {
    glasses(id)?.services.display.sendClick(identifier: identifier) ?? false
  }

  // MARK: - Voice

  func simulateVoiceLaunch(_ id: String) -> String? {
    glasses(id)?.services.voiceInvocation.sendLaunchAppAction()
  }
}

// MARK: - The poses, as samples

/// A second of a still head held at `pose`, at the rate the real sensor reports.
///
/// The axes are the ones ``GlassesAim`` measured off a worn pair: `+X` at the sky, `+Z` forward,
/// `Y` lateral. A level head therefore reads the whole of gravity's reaction on `X`; looking up
/// tips some of it onto `+Z`, looking down onto `-Z`, and a roll onto `±Y`.
private func motionSamples(for pose: MockMotionPose) -> [MotionSample] {
  let g = mockMotionGravityMetersPerSecondSquared
  let up: MWDATMockDevice.Vector3 =
    switch pose {
    case .level: .init(x: g, y: 0, z: 0)
    case .lookingUp: .init(x: g * cos(mockPitchRadians), y: 0, z: g * sin(mockPitchRadians))
    case .lookingDown: .init(x: g * cos(mockPitchRadians), y: 0, z: -g * sin(mockPitchRadians))
    case .tiltedLeft: .init(x: g * cos(mockRollRadians), y: g * sin(mockRollRadians), z: 0)
    case .tiltedRight: .init(x: g * cos(mockRollRadians), y: -g * sin(mockRollRadians), z: 0)
    }
  let intervalNs: Int64 = 1_000_000_000 / Int64(mockSampleHertz)
  return (0..<mockSampleHertz).map { index in
    MotionSample(
      timestampNs: Int64(index) * intervalNs,
      accelerometer: up,
      gyroscope: .init(x: 0, y: 0, z: 0),
      source: .glasses
    )
  }
}

/// How far the posed head looks up or down — past the gaze chip's canopy line, so the chip
/// visibly changes its word.
private let mockPitchRadians: Float = 45 * .pi / 180
private let mockRollRadians: Float = 30 * .pi / 180
private let mockSampleHertz = 50
private let mockDisplayServerPort: UInt16 = 9000

// MARK: - Domain ↔ SDK

private extension MockGlassesModel {
  var datModel: GlassesModel {
    switch self {
    case .rayBanMeta: .rayBanMeta
    case .oakleyMetaHSTN: .oakleyMetaHSTN
    case .oakleyMetaVanguard: .oakleyMetaVanguard
    case .rayBanMetaOptics: .rayBanMetaOptics
    case .metaGlasses: .metaGlasses
    case .metaRayBanDisplay: .metaRayBanDisplay
    }
  }
}

private extension GlassesAccess {
  /// The kit answers granted or denied, never unknown — so unknown is asked for as denied,
  /// the honest reading of a grant nobody has given.
  var datStatus: MWDATCore.PermissionStatus {
    self == .granted ? .granted : .denied
  }
}
