/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The mock panel's one piece of policy: **which pair the controls are aimed at** as pairs
/// come and go.
///
/// The kit holds up to a handful of simulated pairs and reports the list whole, so every
/// change is a fresh list rather than an event, and the panel has to decide where its
/// controls point from the list alone. The rule under test: stay on the pair being driven for
/// as long as it exists, fall to the latest pair when it does not, and point at nothing when
/// there is nothing.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("MockDeviceViewModel")
struct MockDeviceViewModelTests {

  @Test func pairingSelectsTheNewPair() {
    // Nothing was selected; the first pair to arrive is the one the controls take.
    #expect(selectedDeviceId(after: [rayBan], current: nil) == rayBan.id)
  }

  @Test func aNewPairDoesNotStealTheSelection() {
    // Somebody is driving the Ray-Ban when a second pair arrives. The controls stay put:
    // a slider mid-drag must not switch glasses under the thumb.
    #expect(selectedDeviceId(after: [rayBan, display], current: rayBan.id) == rayBan.id)
  }

  @Test func unpairingTheSelectedPairFallsBackToTheLatest() {
    // The pair being driven is unpaired. The latest remaining one is the closest thing
    // to where the controls were.
    #expect(selectedDeviceId(after: [rayBan, display], current: "gone") == display.id)
  }

  @Test func noPairsMeansNoSelection() {
    // The kit holds nothing — disabled, or every pair unpaired. Nothing to aim at.
    #expect(selectedDeviceId(after: [], current: rayBan.id) == nil)
  }

  private let rayBan = MockDeviceInfo(id: "mock-1", model: .rayBanMeta)
  private let display = MockDeviceInfo(id: "mock-2", model: .metaRayBanDisplay)
}
