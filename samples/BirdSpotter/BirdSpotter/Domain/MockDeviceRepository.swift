/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceRepository.swift
//  birdspotter
//

import Foundation
import UIKit

/// The glasses the mock can stand in for — one case per model the kit knows how to fake.
///
/// A model rather than a device: what is chosen here is which *kind* of pair to simulate,
/// and only one of them carries a display. Choosing the display model is what turns the
/// Display row on the glasses screen into something the mock can answer.
nonisolated enum MockGlassesModel: String, CaseIterable, Sendable {
  case rayBanMeta
  case oakleyMetaHSTN
  case oakleyMetaVanguard
  case rayBanMetaOptics
  case metaGlasses
  case metaRayBanDisplay

  /// What the picker calls it.
  var displayName: String {
    switch self {
    case .rayBanMeta: "Ray-Ban Meta"
    case .oakleyMetaHSTN: "Oakley Meta HSTN"
    case .oakleyMetaVanguard: "Oakley Meta Vanguard"
    case .rayBanMetaOptics: "Ray-Ban Meta Optics"
    case .metaGlasses: "Meta Glasses"
    case .metaRayBanDisplay: "Meta Ray-Ban Display"
    }
  }

  /// Whether this model has a panel to draw on — the one fact the panel needs before
  /// offering the display preview.
  var hasDisplay: Bool {
    self == .metaRayBanDisplay
  }
}

/// A simulated pair the kit is holding: enough to name it in a list and address it in a
/// call. The readings themselves — worn, battery, heat — land in ``GlassesDeviceInfo`` like
/// any real pair's, because the whole point is that nothing above the data layer can tell.
nonisolated struct MockDeviceInfo: Equatable, Sendable, Identifiable {
  /// The kit's own identifier for the pair, the key every control takes.
  let id: String
  let model: MockGlassesModel
}

/// Which phone camera stands in for the glasses' when no video file has been chosen.
nonisolated enum MockCameraFacing: Sendable, CaseIterable {
  case front
  case back
}

/// The ways the capture button can be pressed, as the inputs capability distinguishes them.
nonisolated enum MockCapturePress: Sendable, CaseIterable {
  case shortPress
  case hold
  case doublePress
}

/// A swipe on the temple.
nonisolated enum MockNavDirection: Sendable, CaseIterable {
  case up
  case down
  case left
  case right
}

/// Where the mock recogniser's words come from: strings typed into the panel, or the
/// phone's own recogniser hearing the room — the way to rehearse the ASR flow out loud.
nonisolated enum MockSpeechSource: Sendable, CaseIterable {
  case injected
  case liveDeviceAsr
}

/// A head position the motion feed can hold — the handful the aim readings care about.
///
/// Poses rather than raw samples because the app only ever reads gravity out of the
/// accelerometer to answer *how high is the wearer looking*; a panel offering three floats
/// per axis would be an instrument nobody could play during a demo.
nonisolated enum MockMotionPose: Sendable, CaseIterable {
  case level
  case lookingUp
  case lookingDown
  case tiltedLeft
  case tiltedRight

  var displayName: String {
    switch self {
    case .level: "Level"
    case .lookingUp: "Looking up"
    case .lookingDown: "Looking down"
    case .tiltedLeft: "Tilted left"
    case .tiltedRight: "Tilted right"
    }
  }
}

/// What went wrong with the mock, in the cases the panel can say something about.
nonisolated enum MockDeviceError: Error, Equatable, Sendable {
  /// A control was used with the kit switched off.
  case notEnabled
  /// The pair the control named is no longer held by the kit.
  case noSuchDevice
}

/// Meta's Mock Device Kit, as the app drives it: a switch that swaps the SDK's registration
/// and connectivity for simulated ones, and the controls on the simulated pair.
///
/// **The switch is live.** Enabling swaps the providers under the running SDK, and every
/// stream this app already holds open — registration, the device list — carries the change on
/// its own; disabling swaps them back. What the swap does *not* do is end a session that was
/// open at the moment of the flip, so both directions end the app's own leases first.
///
/// Every device control takes the pair's ``MockDeviceInfo/id``, because the kit holds more
/// than one and the panel chooses which is being driven. A control on a pair the kit no
/// longer holds does nothing, deliberately: the panel's list is a beat behind the kit, and a
/// press on a row that has just gone is not an error worth an alert.
nonisolated protocol MockDeviceRepository: Sendable {

  /// Whether the kit is standing in for the real SDK right now.
  var isEnabled: Bool { get }

  /// Cold stream of ``isEnabled``, current value first.
  func isEnabledStream() -> AsyncStream<Bool>

  /// Flips the kit, ending any open session first. Enabling remembers the choice, so the
  /// next launch comes up simulated too.
  func setEnabled(_ enabled: Bool) async

  /// Cold stream of the simulated pairs the kit holds, current list first.
  func devicesStream() -> AsyncStream<[MockDeviceInfo]>

  /// Adds a simulated pair and brings it up — powered, unfolded and worn — so it is a pair
  /// a session can start on straight away. Async because pairing is the kit's own work,
  /// measured in whole seconds on a cold start, and never the caller's thread to sit on.
  func pair(model: MockGlassesModel) async throws(MockDeviceError) -> MockDeviceInfo

  func unpair(_ id: String)

  // MARK: Device state

  func powerOn(_ id: String)
  func powerOff(_ id: String)
  func don(_ id: String)
  func doff(_ id: String)
  func fold(_ id: String)
  func unfold(_ id: String)
  func setBatteryLevel(_ id: String, level: Int)
  func setCharging(_ id: String, isCharging: Bool)
  func setThermal(_ id: String, level: GlassesThermalLevel)

  // MARK: Grants

  /// What ``GlassesSessionRepository/access(_:)`` will read back. ``GlassesAccess/unknown``
  /// is not settable — the kit answers with a grant or a refusal, never silence.
  func setAccess(_ permission: GlassesPermission, _ access: GlassesAccess)

  /// What the next request for the grant will come back with — the wearer's answer in
  /// the Meta AI app, scripted.
  func setRequestResult(_ permission: GlassesPermission, _ access: GlassesAccess)

  // MARK: Camera

  /// A video file the stream plays in place of the glasses' camera.
  func setCameraFeed(_ id: String, fileURL: URL)

  /// The phone's own camera in place of the glasses'.
  func setCameraFeed(_ id: String, facing: MockCameraFacing)

  /// The photograph every capture comes back with.
  func setCapturedPhoto(_ id: String, fileURL: URL)

  /// The next capture fails the way a real crossing can.
  func simulateCaptureFailure(_ id: String)

  // MARK: Inputs

  func tap(_ id: String)
  func tapAndHold(_ id: String)
  func navigate(_ id: String, _ direction: MockNavDirection)
  func select(_ id: String)
  func back(_ id: String)
  func pressCapture(_ id: String, _ press: MockCapturePress)
  func pressActionButton(_ id: String)

  // MARK: Speech

  func setSpeechSource(_ id: String, _ source: MockSpeechSource)
  func simulateTranscription(_ id: String, text: String, isFinal: Bool)
  func simulateSpeechError(_ id: String, message: String)
  func simulateSpeechCompletion(_ id: String)

  // MARK: Motion

  /// Holds the pair's motion feed at a pose for as long as something is listening.
  func setMotionPose(_ id: String, _ pose: MockMotionPose)

  // MARK: Display

  func startDisplayServer() async -> UInt16?
  func stopDisplayServer() async

  /// A live view of the simulated panel, drawn by the kit itself, or `nil` when the pair has
  /// no panel. The kit keeps it current as the app draws; the caller only hosts it. A fresh
  /// view per call — one per selection, dropped when the selection moves.
  @MainActor func displayPreview(_ id: String) -> UIView?

  /// Presses a button the app drew, by the identifier the app gave it. `false` when the
  /// panel holds no such button.
  @discardableResult
  func sendDisplayClick(_ id: String, identifier: String) -> Bool

  // MARK: Voice

  /// "Hey Meta, open BirdSpotter", spoken to the simulated pair. Returns the kit's own
  /// description of what it sent, or `nil` when nothing was listening.
  func simulateVoiceLaunch(_ id: String) -> String?
}
