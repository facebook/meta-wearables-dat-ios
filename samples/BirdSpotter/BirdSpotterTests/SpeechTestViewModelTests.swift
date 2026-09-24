/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeechTestViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The ASR test screen's one piece of policy: **what an arriving transcript does to what is on
/// screen**.
///
/// The recogniser delivers the same utterance several times as it develops and once when it is
/// over, so a screen that treated every arrival alike would print a sentence a word at a time down
/// the page — and one that kept only finals would show nothing at all while somebody was speaking,
/// which is the reading this screen exists to give.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SpeechTestViewModel")
struct SpeechTestViewModelTests {

  @Test func aPartialReplacesTheUtteranceInProgress() {
    // The sentence developing. Three arrivals, one line — anything else is a page of
    // prefixes.
    let state = SpeechTestUiState()
      .hearing(Transcription(text: "its", isFinal: false))
      .hearing(Transcription(text: "its green", isFinal: false))
      .hearing(Transcription(text: "its green with", isFinal: false))

    #expect(state.partial == "its green with")
    #expect(state.heard.isEmpty)
  }

  @Test func aFinalClosesTheUtteranceAndJoinsTheList() {
    // The commit. The line in progress has to go with it, or the screen shows the same
    // sentence twice — once italic and once not.
    let state = SpeechTestUiState()
      .hearing(Transcription(text: "its green with a yellow", isFinal: false))
      .hearing(Transcription(text: "It's green with a yellow belly", isFinal: true))

    #expect(state.partial == nil)
    #expect(state.heard.map(\.text) == ["It's green with a yellow belly"])
  }

  @Test func theNewestUtteranceIsFirst() {
    // A diagnostic is read from the top: the thing just said is the thing being checked.
    let state = SpeechTestUiState()
      .hearing(Transcription(text: "first", isFinal: true))
      .hearing(Transcription(text: "second", isFinal: true))

    #expect(state.heard.map(\.text) == ["second", "first"])
  }

  @Test func theListStopsGrowingAtItsLimit() {
    // A test left running is a test nobody is watching, and an unbounded list is the one way
    // a diagnostic screen can itself become the fault.
    let state = (1...80).reduce(into: SpeechTestUiState()) { state, index in
      state = state.hearing(Transcription(text: "utterance \(index)", isFinal: true))
    }

    #expect(state.heard.count == 50)
    #expect(state.heard.first?.text == "utterance 80")
    #expect(state.heard.last?.text == "utterance 31")
  }

  @Test func aConfidenceTheRecogniserWithheldStaysWithheld() {
    // Carried rather than defaulted. A number the glasses would not give must not turn into a
    // number on screen, which is the whole reason the field is optional.
    let state = SpeechTestUiState()
      .hearing(Transcription(text: "what bird is that", isFinal: true, confidence: nil))

    #expect(state.heard.first?.confidence == nil)
  }
}
