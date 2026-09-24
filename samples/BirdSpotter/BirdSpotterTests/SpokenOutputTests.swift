/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpokenOutputTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// The sentence the app says about a bird it heard: which of the two openings a confidence earns,
/// and the two-letter word in the middle that decides whether it sounds like English.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SpokenOutput")
struct SpokenOutputTests {

  @Test func heardAloud_wellAboveTheThreshold_saysItPlainly() {
    #expect(heardAloud(commonName: "Green Jay", confidence: 0.92) == "I just heard a Green Jay.")
  }

  @Test func heardAloud_belowTheThreshold_hedges() {
    #expect(
      heardAloud(commonName: "Green Jay", confidence: 0.74) == "I think I heard a Green Jay."
    )
  }

  @Test func heardAloud_exactlyAtTheThreshold_saysItPlainly() {
    // The boundary belongs to the sure side: the threshold is the point at which the app has
    // stopped hedging, not the last point at which it still is.
    #expect(
      heardAloud(commonName: "Green Jay", confidence: sureAloudConfidence)
        == "I just heard a Green Jay."
    )
  }

  @Test func heardAloud_carriesTheArticleTheNameNeeds() {
    #expect(
      heardAloud(commonName: "American Robin", confidence: 0.9)
        == "I just heard an American Robin."
    )
  }

  @Test func spokenCertainty_readsTheConfidence() {
    #expect(SpokenCertainty.of(0.9) == .sure)
    #expect(SpokenCertainty.of(0.5) == .hedged)
  }

  @Test func indefiniteArticle_aConsonantTakesA() {
    #expect(indefiniteArticle("Green Jay") == "a")
    #expect(indefiniteArticle("Northern Cardinal") == "a")
  }

  @Test func indefiniteArticle_aVowelTakesAn() {
    #expect(indefiniteArticle("American Robin") == "an")
    #expect(indefiniteArticle("Osprey") == "an")
    #expect(indefiniteArticle("Indigo Bunting") == "an")
    #expect(indefiniteArticle("Eastern Bluebird") == "an")
  }

  @Test func indefiniteArticle_theOnesSpeltWithAVowelAndSaidWithAYTakeA() {
    // The whole reason the rule is not "does it start with a vowel" — and the only two names
    // in the catalog that need the exception.
    #expect(indefiniteArticle("European Starling") == "a")
    #expect(indefiniteArticle("Eurasian Collared-Dove") == "a")
  }

  @Test func indefiniteArticle_anEmptyNameFallsBackRatherThanFailing() {
    #expect(indefiniteArticle("") == "a")
  }
}
