/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalFormattingTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// The pieces of ``JournalFormatting`` with real logic — the bearing bucketing, the duration
/// arithmetic, the wizard-answer unfolding — and the per-cent rounding beside them. The date
/// helpers are platform formatters and aren't asserted.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("JournalFormatting")
struct JournalFormattingTests {

  @Test func bearingLabel_readsTheFourCardinals() {
    #expect(JournalFormatting.bearingLabel(0) == "N")
    #expect(JournalFormatting.bearingLabel(90) == "E")
    #expect(JournalFormatting.bearingLabel(180) == "S")
    #expect(JournalFormatting.bearingLabel(270) == "W")
  }

  @Test func bearingLabel_readsTheIntercardinals() {
    #expect(JournalFormatting.bearingLabel(45) == "NE")
    #expect(JournalFormatting.bearingLabel(135) == "SE")
    #expect(JournalFormatting.bearingLabel(225) == "SW")
    #expect(JournalFormatting.bearingLabel(315) == "NW")
  }

  @Test func bearingLabel_readsTheSixteenPoint() {
    #expect(JournalFormatting.bearingLabel(22.5) == "NNE")
    #expect(JournalFormatting.bearingLabel(292.5) == "WNW")
  }

  @Test func bearingLabel_roundsToTheNearestBucket() {
    // Buckets are 22.5° wide, centred on each point; N and NNE part at 11.25.
    #expect(JournalFormatting.bearingLabel(11) == "N")
    #expect(JournalFormatting.bearingLabel(12) == "NNE")
  }

  @Test func bearingLabel_foldsPastNorthBackToNorth() {
    // 349 sits inside N's half-open bucket [348.75, 360); so does 360 itself.
    #expect(JournalFormatting.bearingLabel(349) == "N")
    #expect(JournalFormatting.bearingLabel(360) == "N")
  }

  @Test func bearingLabel_normalizesOutOfRange() {
    #expect(JournalFormatting.bearingLabel(405) == "NE") // 405 - 360 = 45
    #expect(JournalFormatting.bearingLabel(-45) == "NW") // -45 + 360 = 315
  }

  @Test func confidenceLabel_readsWholePerCent() {
    #expect(JournalFormatting.confidenceLabel(0.87) == "87%")
    #expect(JournalFormatting.confidenceLabel(1.0) == "100%")
    #expect(JournalFormatting.confidenceLabel(0.0) == "0%")
  }

  @Test func durationLabel_roundsUpToWholeMinutes() {
    #expect(JournalFormatting.durationLabel(45_000) == "1 min")
    #expect(JournalFormatting.durationLabel(61_000) == "2 min")
    #expect(JournalFormatting.durationLabel(14 * 60_000) == "14 min")
  }

  @Test func durationLabel_floorsAtOneMinute() {
    #expect(JournalFormatting.durationLabel(0) == "1 min")
    #expect(JournalFormatting.durationLabel(1) == "1 min")
  }

  @Test func durationLabel_foldsHours() {
    #expect(JournalFormatting.durationLabel(65 * 60_000) == "1 hr 5 min")
    #expect(JournalFormatting.durationLabel(120 * 60_000) == "2 hr")
  }

  @Test func wizardAnswerLabel_readsEachTrait() {
    #expect(JournalFormatting.wizardAnswerLabel(.size, "4") == "4 of 7")
    #expect(JournalFormatting.wizardAnswerLabel(.colors, "BLACK,RED") == "Black, red")
    #expect(JournalFormatting.wizardAnswerLabel(.behavior, "ON_FENCE_OR_WIRE") == "On fence or wire")
  }

  @Test func coordinates_readFixedToFourDecimals() {
    #expect(
      JournalFormatting.coordinates(Coordinate(latitude: 39.10312, longitude: -84.51200))
        == "39.1031, -84.5120"
    )
    // A dot decimal whatever the device's locale, so both phones print the same digits.
    #expect(JournalFormatting.coordinates(Coordinate(latitude: 0, longitude: 0)) == "0.0000, 0.0000")
  }

  @Test func labels_readEachEnum() {
    #expect(JournalFormatting.kindLabel(.live) == "Live outing")
    #expect(JournalFormatting.kindLabel(.manual) == "Wizard entry")
    #expect(JournalFormatting.sourceLabel(.glasses) == "Glasses")
  }

  /// All five, because this is the only place a stratum becomes words — the live chip reads it too.
  @Test func gazeLabel_namesEachOfTheFiveStrata() {
    #expect(
      GazeContext.allCases.map(JournalFormatting.gazeLabel)
        == ["Ground", "Understory", "Horizon", "Canopy", "Overhead"]
    )
  }
}
