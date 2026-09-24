/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  VoiceDescriptionTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// How the vocalization card labels a recording from its sex and stage — the "who is singing"
/// line the bird page shows in place of restating "Song"/"Call".
///
/// Pure formatting, so it is reachable without driving a ViewModel through an async load or a
/// player. The capitalization case earns its place: a stock title-case helper raises every word
/// of a two-word value, so only the first letter is raised by hand, and this pins that.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("VoiceDescription")
struct VoiceDescriptionTests {

  private func recording(sex: String? = nil, stage: String? = nil) -> SpeciesMedia {
    SpeciesMedia(
      id: "x-song-01",
      speciesId: "x",
      type: .song,
      assetKey: "x/song-01",
      isPrimary: true,
      sex: sex,
      stage: stage,
      sortOrder: 0
    )
  }

  @Test func voiceDescription_withSexAndStage_joinsThemWithADot() {
    #expect(recording(sex: "male", stage: "adult").voiceDescription == "Male · Adult")
  }

  @Test func voiceDescription_withSexOnly_isTheSexAlone() {
    #expect(recording(sex: "female").voiceDescription == "Female")
  }

  @Test func voiceDescription_withStageOnly_isTheStageAlone() {
    #expect(recording(stage: "juvenile").voiceDescription == "Juvenile")
  }

  @Test func voiceDescription_withNeither_isNil() {
    #expect(recording().voiceDescription == nil)
  }

  @Test func voiceDescription_withBlankValues_ignoresThem() {
    #expect(recording(sex: "", stage: "adult").voiceDescription == "Adult")
  }

  @Test func voiceDescription_capitalizesOnlyTheFirstLetter() {
    // A Xeno-canto value can carry two words; only the first letter is raised, so both
    // platforms read "Male, female" rather than Swift's word-by-word "Male, Female".
    #expect(recording(sex: "male, female").voiceDescription == "Male, female")
  }
}
