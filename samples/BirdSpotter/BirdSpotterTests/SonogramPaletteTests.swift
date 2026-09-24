/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramPaletteTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The sonogram ramp: that it is magma, that it reaches both ends, and that it answers for every
/// byte a magnitude can be.
///
/// The point of these is **parity with the seed pipeline**. If a stop is
/// ever nudged, the live strip stops matching the catalog's rendered PNGs — which is the whole
/// reason the palette exists — and the endpoints below are what would catch it.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SonogramPalette")
struct SonogramPaletteTests {

  @Test func silenceIsBlack() {
    #expect(SonogramPalette.colour(atLevel: 0) == SonogramColour(red: 0, green: 0, blue: 0))
  }

  @Test func theLoudestIsMagmasPaleYellow() {
    #expect(
      SonogramPalette.colour(atLevel: 1)
        == SonogramColour(red: 253, green: 253, blue: 243)
    )
  }

  @Test func aStopIsReturnedExactly() {
    // The fourth stop, which is where magma turns from purple into red.
    #expect(
      SonogramPalette.colour(atLevel: 0.3522)
        == SonogramColour(red: 155, green: 46, blue: 101)
    )
  }

  @Test func betweenTwoStops_isMixedFromBoth() {
    // Exactly halfway from the black ground to the first stop, which lands blue on 52.5 —
    // deliberately a tie, so this also pins the two platforms to the same rounding.
    let colour = SonogramPalette.colour(atLevel: 0.0503)

    #expect(colour == SonogramColour(red: 5, green: 7, blue: 53))
  }

  @Test func outsideTheRange_clampsToAnEnd() {
    // A magnitude is normalised long before it reaches here; a strip needs an answer anyway.
    #expect(SonogramPalette.colour(atLevel: -1) == SonogramPalette.colour(atLevel: 0))
    #expect(SonogramPalette.colour(atLevel: 4) == SonogramPalette.colour(atLevel: 1))
  }

  @Test func theRampCoversEveryByte() {
    let ramp = SonogramPalette.ramp()

    #expect(ramp.count == 256)
    #expect(ramp.first == SonogramPalette.colour(atLevel: 0))
    #expect(ramp.last == SonogramPalette.colour(atLevel: 1))
  }

  @Test func theRampOnlyGetsBrighter() {
    // Magma is perceptually monotone, and a spectrogram whose ramp doubled back would read a
    // loud column as quieter than the one beside it.
    let ramp = SonogramPalette.ramp()
    let brightness = ramp.map { Int($0.red) + Int($0.green) + Int($0.blue) }

    #expect(zip(brightness, brightness.dropFirst()).allSatisfy { $0 <= $1 })
  }

  @Test func theStopsAreOrderedAndSpanTheWholeRange() {
    let levels = SonogramPalette.stops.map(\.level)

    #expect(levels.first == 0)
    #expect(levels.last == 1)
    #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 < $1 })
  }
}
