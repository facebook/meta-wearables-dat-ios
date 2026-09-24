/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesSettingsViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The glasses settings screen's one piece of policy: **when a Meta AI grant is worth
/// asking about**.
///
/// DAT reads a grant off a connected pair and cannot answer without one, so the reading
/// is a function of the link and has to follow it. The screen used to ask once, at
/// construction, which froze the row on whatever was true then — glasses connected
/// afterwards changed nothing until the app was restarted, and the unreadable state wore
/// "Not asked" and an `Allow` button that could not succeed.
///
/// Scenario names are fixed by the testing-parity rule.
@MainActor
@Suite("GlassesSettingsViewModel")
struct GlassesSettingsViewModelTests {

  @Test func theLinkComingUpReReadsTheGrant() async {
    // The reported bug, in one line: linked, nothing connected, then the glasses answer.
    let glasses = FakeGlassesSession(
      devices: [unreachable, reachable],
      answers: [.unknown, .granted]
    )
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()

    #expect(model.cameraAccess == .granted)
    #expect(glasses.reads(of: .camera) == 2)
  }

  @Test func theLinkDroppingMakesTheGrantUnreadableAgain() async {
    // Folding them, or walking out of range. The grant did not change; our ability to
    // read it did, and the row must not go on claiming a reading it can no longer take.
    let glasses = FakeGlassesSession(
      devices: [reachable, unreachable],
      answers: [.granted, .unknown]
    )
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()

    #expect(model.cameraAccess == .unknown)
    #expect(glasses.reads(of: .camera) == 2)
  }

  @Test func aLinkThatNeverChangesIsReadOnce() async {
    // Meta AI re-lists the same pair for reasons of its own — a rename, a metadata
    // refresh. Only reachability decides whether the answer could differ.
    let glasses = FakeGlassesSession(
      devices: [unreachable, unreachable, unreachable],
      answers: [.unknown]
    )
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()

    #expect(model.cameraAccess == .unknown)
    #expect(glasses.reads(of: .camera) == 1)
  }

  @Test func noPairAtAllIsUnreadableRatherThanDenied() async {
    // Nothing listed is not the wearer saying no — it is nobody to ask. `Allow` here
    // would raise a Meta AI flow with no device behind it.
    let glasses = FakeGlassesSession(devices: [nil], answers: [.unknown])
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()

    #expect(model.cameraAccess == .unknown)
  }

  @Test func eachGrantIsReadForItsOwnPermission() async {
    // Two rows, two grants, and DAT answers them separately — a wearer who allowed the
    // camera and refused the microphone must see exactly that, not one answer twice.
    let glasses = FakeGlassesSession(
      devices: [reachable],
      camera: [.granted],
      microphone: [.denied]
    )
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()

    #expect(model.cameraAccess == .granted)
    #expect(model.microphoneAccess == .denied)
    #expect(glasses.asked == [.camera, .microphone])
  }

  @Test func aRefreshReReadsEveryGrant() async {
    // What the screen does when one of its grant flows returns. Meta AI shows the
    // grants together, so the flow raised for one of them is an opportunity to give
    // the other — re-reading only the one that was raised leaves the other row stale.
    let glasses = FakeGlassesSession(
      devices: [reachable],
      camera: [.denied, .granted],
      microphone: [.denied, .granted]
    )
    let model = GlassesSettingsViewModel(glassesSession: glasses)

    await model.observe()
    await model.refreshAccess()

    #expect(model.cameraAccess == .granted)
    #expect(model.microphoneAccess == .granted)
    #expect(glasses.reads(of: .camera) == 2)
    #expect(glasses.reads(of: .microphone) == 2)
  }

  private let reachable = GlassesDeviceInfo(name: "Ray-Ban Meta", isAvailable: true)
  private let unreachable = GlassesDeviceInfo(name: "Ray-Ban Meta", isAvailable: false)
}

/// A pair Meta AI lists, and what DAT would say about each grant every time it is asked —
/// `answers` in the order the readings happen, the last one standing in for any read beyond
/// it. Scripting the answers rather than deriving them keeps the reading *count* visible,
/// which is half of what these scenarios are about.
///
/// `@unchecked Sendable` because the tests drive it from one actor at a time.
private final class FakeGlassesSession: GlassesSessionRepository, @unchecked Sendable {

  private let devices: [GlassesDeviceInfo?]
  private let answers: [GlassesPermission: [GlassesAccess]]

  /// Every grant asked about, in the order it was asked — which grant, and how many
  /// times, are the two things these scenarios pin.
  private(set) var asked: [GlassesPermission] = []

  init(devices: [GlassesDeviceInfo?], answers: [GlassesPermission: [GlassesAccess]]) {
    self.devices = devices
    self.answers = answers
  }

  convenience init(
    devices: [GlassesDeviceInfo?],
    camera: [GlassesAccess],
    microphone: [GlassesAccess]
  ) {
    self.init(devices: devices, answers: [.camera: camera, .microphone: microphone])
  }

  /// The one script, for the scenarios that are about the link rather than about which
  /// grant is which.
  convenience init(devices: [GlassesDeviceInfo?], answers: [GlassesAccess]) {
    self.init(
      devices: devices,
      answers: Dictionary(
        uniqueKeysWithValues: GlassesPermission.allCases.map { ($0, answers) }
      )
    )
  }

  func reads(of permission: GlassesPermission) -> Int {
    asked.filter { $0 == permission }.count
  }

  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { $0.finish() }
  }

  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) { continuation in
      devices.forEach { continuation.yield($0) }
      continuation.finish()
    }
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func access(_ permission: GlassesPermission) async -> GlassesAccess {
    let script = answers[permission] ?? [.unknown]
    let answer = script[min(reads(of: permission), script.count - 1)]
    asked.append(permission)
    return answer
  }
}
