/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingPlayback.swift
//  birdspotter
//

import Foundation

/// One stretch of a saved outing's sound, decoded and placed: the samples, and the clock
/// reading they start at. What an `AUDIO` media row becomes once its file is read.
nonisolated struct PlaybackSegment: Sendable {
  /// ms from the outing's start — the media row's `offsetMs`.
  let offsetMs: Int64
  let samples: [Float]
}

/// A saved outing's audio as one continuous timeline.
///
/// Sorted by offset, an outing's segments say where there is sound and where there is none.
/// This answers *give me the audio at t*: the covering segment's samples where one covers it,
/// zeros where none does — silence played, never stored. The platform players pull from
/// ``read(fromFrame:into:)`` and know nothing about segments; the seam between a glasses
/// segment and a phone one is inaudible because both are 16 kHz mono by design.
///
/// A scheduler, not a player: it holds no engine and no position, so it is the same small,
/// boring arithmetic in both languages, and the whole thing is testable without a speaker.
/// `AVAudioEngine` and `AudioTrack` take it from here.
///
/// Frames rather than ms at this seam, because ms cannot name a sample: at 16 kHz a
/// millisecond is sixteen of them. ``frameOf(ms:)`` is the one place the conversion lives.
nonisolated final class OutingPlayback: Sendable {

  private let segments: [PlaybackSegment]

  /// The playable length in frames. The outing's own duration when it is the longer —
  /// a session can end in silence worth honouring — but never shorter than the last
  /// segment's end, so a duration recorded slightly shy of the audio cannot cut it off.
  let totalFrames: Int

  /// Makeup gain applied on ``read(fromFrame:into:)`` — because the capture is
  /// deliberately unprocessed (no AGC; see ``MicrophoneCapture``) and a quiet morning
  /// records tens of decibels under full scale. The strip hides that: it draws against a
  /// −70 dB floor, which is a visual AGC, so a recording that *looks* vivid can be nearly
  /// inaudible played back raw. The gain is the playback half of that honesty: the file
  /// keeps what the microphone heard; the speaker gets what an ear needs.
  ///
  /// Aimed so the outing's **``playbackLoudnessPercentile`` loudness** lands at
  /// ``playbackTargetPeak`` — a high percentile rather than the absolute peak, because
  /// one thump of the phone against a table is one sample run that would otherwise pin
  /// the gain for the whole walk while everything worth hearing stayed faint. What
  /// overshoots full scale under the lift (that thump) is clamped in
  /// ``read(fromFrame:into:)``, which distorts the transient and nothing else.
  ///
  /// Never below 1 — a hot capture plays as captured, clipping and all, because the
  /// distortion is the recording's fact, not this class's to soften. Capped at
  /// ``playbackMaxGain``, so an outing of near-silence is lifted into "quiet room" rather
  /// than blasted into hiss.
  let gain: Float

  var totalMs: Int64 { Int64(totalFrames) * 1000 / Int64(captureSampleRate) }

  init(segments: [PlaybackSegment], totalMs: Int64) {
    let sorted = segments.sorted { $0.offsetMs < $1.offsetMs }
    self.segments = sorted
    self.totalFrames = max(
      Self.frameOf(ms: totalMs),
      sorted.last.map { Self.frameOf(ms: $0.offsetMs) + $0.samples.count } ?? 0
    )

    // The loudness reading, by histogram rather than by sorting millions of samples:
    // 1000 buckets over 0..1 magnitude, walked from the top until the allowance of
    // louder-than-this samples is spent. O(n), no allocation proportional to n, and the
    // identical paragraph in both languages.
    var total = 0
    var histogram = [Int](repeating: 0, count: loudnessBuckets)
    for segment in sorted {
      for sample in segment.samples {
        let magnitude = sample < 0 ? -sample : sample
        let bucket = min(Int(magnitude * Float(loudnessBuckets)), loudnessBuckets - 1)
        histogram[bucket] += 1
        total += 1
      }
    }

    var allowed = Int(Double(total) * (1.0 - playbackLoudnessPercentile))
    var loudness: Float = 0
    var bucket = loudnessBuckets - 1
    while bucket >= 0 {
      allowed -= histogram[bucket]
      if allowed < 0 {
        loudness = Float(bucket + 1) / Float(loudnessBuckets)
        break
      }
      bucket -= 1
    }

    self.gain =
      loudness > 0
      ? min(max(playbackTargetPeak / loudness, 1), playbackMaxGain)
      : 1
  }

  /// Fills `into` with the timeline starting at `fromFrame`: segment samples where a
  /// segment covers, zeros where none does. Returns how many frames of the timeline remain
  /// valid — the full buffer until the end approaches, then the remainder, then `0`, which
  /// is how a player knows it has played out.
  func read(fromFrame: Int, into: inout [Float]) -> Int {
    for i in into.indices { into[i] = 0 }
    guard fromFrame < totalFrames else { return 0 }
    let frames = min(into.count, totalFrames - fromFrame)

    for segment in segments {
      let segmentStart = Self.frameOf(ms: segment.offsetMs)
      let segmentEnd = segmentStart + segment.samples.count
      if segmentEnd <= fromFrame { continue }
      if segmentStart >= fromFrame + frames { break }

      let copyFrom = max(fromFrame, segmentStart)
      let copyUntil = min(fromFrame + frames, segmentEnd)
      for frame in copyFrom..<copyUntil {
        into[frame - fromFrame] = segment.samples[frame - segmentStart]
      }
    }
    if gain != 1 {
      // Clamped, not left to the engine: the one transient the percentile ignored
      // overshoots full scale under the lift, and clipping it here is deterministic
      // and identical on both platforms.
      for i in 0..<frames { into[i] = min(max(into[i] * gain, -1), 1) }
    }
    return frames
  }

  /// The one ms-to-frames conversion. Floor, so a frame never starts before its clock time.
  static func frameOf(ms: Int64) -> Int {
    Int(ms * Int64(captureSampleRate) / 1000)
  }
}

/// Where the loudness reading is aimed: just shy of full scale, headroom for the seams.
nonisolated let playbackTargetPeak: Float = 0.9

/// The most ``OutingPlayback/gain`` will lift a recording — 32×, about +30 dB. Enough to
/// bring an unprocessed `.measurement` capture up to a level an AGC-assisted one arrives at
/// on its own; little enough that a near-silent outing plays back as a quiet room rather than
/// a wall of amplified hiss.
nonisolated let playbackMaxGain: Float = 32

/// Which loudness the gain normalises: the level all but the loudest 0.1 % of samples sit
/// under. High enough to be the recording's real content, deaf to the lone transient — a
/// knock of the phone against a table is a millisecond that would otherwise set the volume
/// of the whole walk.
nonisolated let playbackLoudnessPercentile = 0.999

/// Resolution of the loudness histogram — 1000 buckets is 0.001 of full scale each.
private let loudnessBuckets = 1000
