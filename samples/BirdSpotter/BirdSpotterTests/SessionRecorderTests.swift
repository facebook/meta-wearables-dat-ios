/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionRecorderTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// What a session keeps for Save: one segment per unbroken stretch, split where the
/// microphone changed or genuinely stopped — and never for ordinary buffer jitter, because
/// the recorder and the strip share `placement`'s idea of a gap.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SessionRecorder")
struct SessionRecorderTests {

  @Test func record_oneMicrophoneIsOneSegment() {
    let recorder = SessionRecorder()

    // Three chunks of 2048 samples, arriving on an honest clock: 128 ms apart.
    recorder.record(chunk(2048, source: .phone), atSeconds: 1.0)
    recorder.record(chunk(2048, source: .phone), atSeconds: 1.128)
    recorder.record(chunk(2048, source: .phone), atSeconds: 1.256)

    let segments = recorder.segments()
    #expect(segments.count == 1)
    #expect(segments.first?.source == .phone)
    #expect(segments.first?.offsetMs == 1_000)
    #expect(segments.first?.samples.count == 3 * 2048)
    // Measured from the samples, not read off the clock a second time.
    #expect(segments.first?.durationMs == Int64(3 * 2048 * 1000 / captureSampleRate))
  }

  @Test func record_aSourceChangeSplitsTheTake() {
    let recorder = SessionRecorder()

    recorder.record(chunk(2048, source: .glasses), atSeconds: 0.5)
    recorder.record(chunk(2048, source: .phone), atSeconds: 0.628)

    let segments = recorder.segments()
    #expect(segments.count == 2)
    #expect(segments.first?.source == .glasses)
    #expect(segments.last?.source == .phone)
    // The incoming microphone starts on its own clock reading.
    #expect(segments.last?.offsetMs == 628)
  }

  @Test func record_aRealGapSplitsTheTake() {
    let recorder = SessionRecorder()

    recorder.record(chunk(2048, source: .phone), atSeconds: 0)
    // The microphone stopped for four seconds — far past the jitter allowance.
    recorder.record(chunk(2048, source: .phone), atSeconds: 4.128)

    let segments = recorder.segments()
    #expect(segments.count == 2)
    #expect(segments.first?.offsetMs == 0)
    #expect(segments.last?.offsetMs == 4_128)
    // The gap is the distance between the rows — no zeros were written into either.
    #expect(segments.first?.samples.count == 2048)
    #expect(segments.last?.samples.count == 2048)
  }

  @Test func record_bufferJitterDoesNotSplit() {
    let recorder = SessionRecorder()

    recorder.record(chunk(2048, source: .phone), atSeconds: 0)
    // 60 ms late — a microphone handing over buffers when it feels like it.
    recorder.record(chunk(2048, source: .phone), atSeconds: 0.188)

    #expect(recorder.segments().count == 1)
  }

  @Test func segments_answersTheSameTwice() {
    let recorder = SessionRecorder()
    recorder.record(chunk(2048, source: .phone), atSeconds: 0)

    // Save can fail and be retried; reading the segments must consume nothing.
    let first = recorder.segments()
    let second = recorder.segments()

    #expect(first.count == 1)
    #expect(second.count == 1)
    #expect(first.first?.samples.count == second.first?.samples.count)
    #expect(first.first?.offsetMs == second.first?.offsetMs)
  }

  @Test func reset_forgetsTheSession() {
    let recorder = SessionRecorder()
    recorder.record(chunk(2048, source: .phone), atSeconds: 0)

    recorder.reset()

    #expect(recorder.segments().isEmpty)
  }

  private func chunk(_ samples: Int, source: CaptureSourceKind) -> AudioChunk {
    AudioChunk(samples: [Float](repeating: 0.25, count: samples), source: source)
  }
}
