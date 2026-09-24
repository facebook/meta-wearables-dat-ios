/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SplashMotionTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// The splash's motion spec, pinned value by value.
///
/// These look like change-detector tests because they are: the launch moment is one
/// choreography, and it stays one only while the numbers agree. A deliberate retune edits
/// `SplashMotion` and this file together; a one-sided edit fails the suite, which is the
/// point.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SplashMotion")
struct SplashMotionTests {

  @Test func spin_landsOnAWholeNumberOfTurns() {
    // The rings must come to rest in the badge's drawn orientation — hand-drawn blobs
    // ending mid-turn sit visibly askew of the mark the app icon shows.
    #expect(SplashMotion.spinDegrees % 360 == 0)
  }

  @Test func timeline_matchesTheMirroredSpec() {
    #expect(SplashMotion.spinMillis == 800)
    #expect(SplashMotion.spinDegrees == 360)
    #expect(SplashMotion.holdMillis == 60)
    #expect(SplashMotion.crossfadeMillis == 160)
  }
}
