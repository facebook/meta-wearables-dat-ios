/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingPlaybackTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// The edit decision list a saved outing plays back through: segment samples where a segment
/// covers the playhead, zeros where none does, and an end that means it.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("OutingPlayback")
struct OutingPlaybackTests {

  @Test func read_insideASegmentIsItsSamples() {
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: ramp(1600))],
      totalMs: 100
    )
    var buffer = [Float](repeating: -1, count: 100)

    let valid = playback.read(fromFrame: 100, into: &buffer)

    #expect(valid == 100)
    #expect(buffer[0] == 100)
    #expect(buffer[99] == 199)
  }

  @Test func read_aGapIsZeros() {
    // 100 ms of sound, 100 ms of nothing, 100 ms of sound.
    let playback = OutingPlayback(
      segments: [
        PlaybackSegment(offsetMs: 0, samples: ramp(1600)),
        PlaybackSegment(offsetMs: 200, samples: ramp(1600)),
      ],
      totalMs: 300
    )
    var buffer = [Float](repeating: -1, count: 1600)

    // Read the gap exactly: frames 1600..3200.
    let valid = playback.read(fromFrame: 1600, into: &buffer)

    #expect(valid == 1600)
    #expect(buffer[0] == 0)
    #expect(buffer[1599] == 0)
  }

  @Test func read_acrossASeamHearsBothSegments() {
    // Adjacent segments — a handover at one sample boundary. Full-scale-ish values, so
    // the makeup gain stays at 1 and the seam is the only thing under test.
    let playback = OutingPlayback(
      segments: [
        PlaybackSegment(offsetMs: 0, samples: [Float](repeating: 0.9, count: 1600)),
        PlaybackSegment(offsetMs: 100, samples: [Float](repeating: 0.45, count: 1600)),
      ],
      totalMs: 200
    )
    var buffer = [Float](repeating: -1, count: 200)

    _ = playback.read(fromFrame: 1500, into: &buffer)

    #expect(buffer[99] == 0.9)
    #expect(buffer[100] == 0.45)
  }

  @Test func gain_liftsAQuietRecordingToAudible() {
    // An unprocessed room capture: peak two orders under full scale. The lift is real
    // but capped — quiet becomes listenable, silence never becomes a wall of hiss.
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: [Float](repeating: 0.01, count: 1600))],
      totalMs: 100
    )
    var buffer = [Float](repeating: -1, count: 100)

    _ = playback.read(fromFrame: 0, into: &buffer)

    #expect(playback.gain == playbackMaxGain)
    #expect(abs(buffer[0] - 0.32) < 0.0001)
  }

  @Test func gain_isNotPinnedByALoneTransient() {
    // A quiet walk with one knock of the phone against a table. The percentile reads
    // the walk, not the knock — and the knock, lifted past full scale, clips to it.
    var samples = [Float](repeating: 0.01, count: 16000)
    samples[100] = 0.9
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: samples)],
      totalMs: 1000
    )
    var buffer = [Float](repeating: -1, count: 200)

    _ = playback.read(fromFrame: 0, into: &buffer)

    #expect(playback.gain == playbackMaxGain)
    #expect(abs(buffer[0] - 0.32) < 0.0001)
    #expect(buffer[100] == 1)
  }

  @Test func gain_neverTurnsARecordingDown() {
    // A hot capture plays as captured — the distortion is the recording's fact.
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: [Float](repeating: 1, count: 1600))],
      totalMs: 100
    )
    var buffer = [Float](repeating: -1, count: 100)

    _ = playback.read(fromFrame: 0, into: &buffer)

    #expect(playback.gain == 1)
    #expect(buffer[0] == 1)
  }

  @Test func read_shortensAtTheEndAndThenAnswersZero() {
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: ramp(1600))],
      totalMs: 100
    )
    var buffer = [Float](repeating: -1, count: 1200)

    // 1600 frames of outing, read from 1200: only 400 remain.
    #expect(playback.read(fromFrame: 1200, into: &buffer) == 400)
    // At the end there is nothing left — which is how a player knows it played out.
    #expect(playback.read(fromFrame: 1600, into: &buffer) == 0)
  }

  @Test func totalFrames_isTheLongerOfClockAndAudio() {
    // The outing's clock ran to 300 ms; the audio stops at 100 ms. The silence is real.
    let clockLonger = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: ramp(1600))],
      totalMs: 300
    )
    #expect(clockLonger.totalFrames == 4800)

    // A duration recorded shy of the audio must not cut the audio off.
    let audioLonger = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: ramp(1600))],
      totalMs: 50
    )
    #expect(audioLonger.totalFrames == 1600)
  }

  @Test func read_beyondTheLastSegmentIsSilenceUntilTheClockRunsOut() {
    let playback = OutingPlayback(
      segments: [PlaybackSegment(offsetMs: 0, samples: [Float](repeating: 1, count: 160))],
      totalMs: 100
    )
    var buffer = [Float](repeating: -1, count: 1600)

    let valid = playback.read(fromFrame: 0, into: &buffer)

    #expect(valid == 1600)
    #expect(buffer[159] == 1)
    #expect(buffer[160] == 0)
    #expect(buffer[1599] == 0)
  }

  /// Samples whose value is their absolute frame index — seams and offsets show themselves.
  private func ramp(_ count: Int) -> [Float] {
    (0..<count).map(Float.init)
  }
}
