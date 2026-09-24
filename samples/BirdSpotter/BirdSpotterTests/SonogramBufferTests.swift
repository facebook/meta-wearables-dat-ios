/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramBufferTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The ring the session's strip is drawn from: what it remembers, what it has forgotten, and what
/// a gap in the audio does to it.
///
/// Scenario names are fixed by the testing-parity rule.
@MainActor
@Suite("SonogramBuffer")
struct SonogramBufferTests {

  // MARK: - Writing and reading

  @Test func append_countsColumnsForever() {
    let buffer = SonogramBuffer(capacity: 4)

    for _ in 0..<6 { buffer.append(column(1)) }

    // Absolute indices: column 0 stays column 0 even once it has been overwritten.
    #expect(buffer.count == 6)
    #expect(buffer.oldest == 2)
  }

  @Test func magnitude_answersSilenceOutsideTheSession() {
    let buffer = SonogramBuffer(capacity: 4)
    buffer.append(column(1))

    // The strip scrolls past both ends of a session and drawing needs an answer, not a trap.
    #expect(buffer.magnitude(column: -1, bin: 0) == 0)
    #expect(buffer.magnitude(column: 5, bin: 0) == 0)
    #expect(buffer.magnitude(column: 0, bin: 0) == 1)
  }

  @Test func level_answersSilenceOutsideTheSession() {
    let buffer = SonogramBuffer(capacity: 4)
    buffer.append(column(1, level: 0.5))

    // The waveform scrolls past both ends of the session exactly as the sonogram does.
    #expect(buffer.level(column: -1) == 0)
    #expect(buffer.level(column: 5) == 0)
    #expect(abs(buffer.level(column: 0) - 0.5) < 0.005)
  }

  // MARK: - What the live trace reads

  @Test func recent_averagesTheNewestColumns() {
    let buffer = SonogramBuffer(capacity: 100)
    buffer.append(column(0, level: 0))
    buffer.append(column(1, level: 1))
    buffer.append(column(0.5, level: 0.5))

    // The two newest, meaned — the trace's whole smoothing, and it is a fact about the data
    // rather than an animation with a clock in it.
    #expect(abs(buffer.recentBins(columns: 2)[0] - 0.75) < 0.005)
    #expect(abs(buffer.recentLevel(columns: 2) - 0.75) < 0.005)
  }

  @Test func recent_takesWhatThereIsWhenTheSessionIsYounger() {
    let buffer = SonogramBuffer(capacity: 100)
    buffer.append(column(1, level: 1))

    // Asked for four columns into a session one column old, the mean is over the one that
    // happened — not over three imaginary silences that would drag it to a quarter.
    #expect(abs(buffer.recentBins(columns: 4)[0] - 1) < 0.005)
    #expect(abs(buffer.recentLevel(columns: 4) - 1) < 0.005)
  }

  @Test func recent_answersSilenceForASessionWithNothingInIt() {
    let buffer = SonogramBuffer(capacity: 100)

    // A flat trace, which is the honest picture of a microphone that has not opened yet.
    #expect(buffer.recentBins(columns: 4)[0] == 0)
    #expect(buffer.recentLevel(columns: 4) == 0)
  }

  // MARK: - Gaps

  @Test func advance_leavesSilenceWhereTheAudioStopped() {
    let buffer = SonogramBuffer(capacity: 100)
    buffer.append(column(1))

    buffer.advance(to: 5)
    buffer.append(column(1))

    // The columns either side of a dropout must not end up adjacent — the session did not get
    // shorter because the microphone stopped.
    #expect(buffer.count == 6)
    #expect(buffer.magnitude(column: 0, bin: 0) == 1)
    for silent in 1..<5 {
      #expect(buffer.magnitude(column: silent, bin: 0) == 0)
    }
    #expect(buffer.magnitude(column: 5, bin: 0) == 1)
  }

  @Test func advance_clearsWhatTheRingWasStillHolding() {
    let buffer = SonogramBuffer(capacity: 4)
    for _ in 0..<4 { buffer.append(column(1)) }

    // Column 5 lands in the slot column 1 used, so a skip that only moved the head would draw
    // a buffer-old song inside the silence.
    buffer.advance(to: 6)

    #expect(buffer.magnitude(column: 5, bin: 0) == 0)
    #expect(buffer.count == 6)
  }

  @Test func advance_neverMovesBackwards() {
    let buffer = SonogramBuffer(capacity: 100)
    for _ in 0..<10 { buffer.append(column(1)) }

    buffer.advance(to: 3)

    // A written column is a column that happened.
    #expect(buffer.count == 10)
    #expect(buffer.magnitude(column: 9, bin: 0) == 1)
  }

  @Test func reset_forgetsTheSession() {
    let buffer = SonogramBuffer(capacity: 4)
    buffer.append(column(1))
    buffer.advance(to: 3)

    buffer.reset()

    #expect(buffer.count == 0)
    #expect(buffer.magnitude(column: 0, bin: 0) == 0)
  }

  // MARK: - Keeping it

  @Test func encoded_survivesTheRoundTrip() throws {
    let buffer = SonogramBuffer(capacity: 8)
    buffer.append(column(1, level: 0.5))
    buffer.append(column(0.25, level: 1))
    // A gap, which has to come back just as dark as it went in.
    buffer.advance(to: 4)
    buffer.append(column(0.75, level: 0.25))

    let restored = try #require(SonogramBuffer.decoded(from: buffer.encoded()))

    #expect(restored.count == buffer.count)
    #expect(restored.oldest == buffer.oldest)
    for column in 0..<buffer.count {
      #expect(restored.magnitude(column: column, bin: 0) == buffer.magnitude(column: column, bin: 0))
      #expect(restored.level(column: column) == buffer.level(column: column))
    }
  }

  @Test func encoded_keepsWhatTheRingStillHolds() throws {
    let buffer = SonogramBuffer(capacity: 4)
    for i in 0..<6 { buffer.append(column(Float(i + 1) / 6)) }

    let restored = try #require(SonogramBuffer.decoded(from: buffer.encoded()))

    // The two overwritten columns are gone from the file too, and column 2 is still column 2 —
    // which is what lets an event's timestamp keep landing where it did during the session.
    #expect(restored.oldest == 2)
    #expect(restored.count == 6)
    for column in 2..<6 {
      #expect(restored.magnitude(column: column, bin: 0) == buffer.magnitude(column: column, bin: 0))
    }
    #expect(restored.magnitude(column: 1, bin: 0) == 0)
  }

  @Test func decoded_refusesBytesThatAreNotAStrip() {
    #expect(SonogramBuffer.decoded(from: Data("not a sonogram at all".utf8)) == nil)
  }

  @Test func decoded_refusesAVersionItDoesNotKnow() {
    var bytes = [UInt8](SonogramBuffer(capacity: 4).encoded())
    bytes[4] = 99

    // A strip from a build that laid the bytes out differently is recomputed, not drawn wrong.
    #expect(SonogramBuffer.decoded(from: Data(bytes)) == nil)
  }

  @Test func decoded_refusesAFileThatWasCutShort() {
    let buffer = SonogramBuffer(capacity: 4)
    for _ in 0..<4 { buffer.append(column(1)) }

    // What a crash between `write` and the file being flushed leaves behind.
    #expect(SonogramBuffer.decoded(from: buffer.encoded().dropLast(10)) == nil)
  }

  private func column(_ magnitude: Float, level: Float = 0) -> SonogramColumn {
    SonogramColumn(
      magnitudes: [Float](repeating: magnitude, count: sonogramBins),
      level: level
    )
  }
}
