/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionRecorder.swift
//  birdspotter
//

import Foundation

/// One unbroken stretch of recording: which microphone, where it starts on the session's
/// timeline, and every sample it heard.
///
/// ``durationMs`` is measured from the samples rather than read off the clock a second time —
/// `samples / 16000 × 1000`. Within a segment
/// the samples place themselves; only the start needs the clock.
nonisolated struct RecordedSegment: Sendable {
  let source: CaptureSourceKind
  /// The clock reading at the segment's first sample — ms from the session's start.
  let offsetMs: Int64
  let samples: [Float]

  var durationMs: Int64 { Int64(samples.count) * 1000 / Int64(captureSampleRate) }
}

/// Keeps what a session hears, as the segments the journal will store — one per unbroken
/// stretch, split where the microphone changed or genuinely stopped.
///
/// The strip and this recorder listen to the same chunks and must agree about time, so the
/// boundary rule is ``placement(clockColumn:written:)``'s, reused rather than restated:
/// ordinary buffer jitter never splits a segment, and a silence long enough to draw on the
/// strip is long enough to be a gap between two rows. A gap is never padded with zeros — that
/// would record a quiet that was never heard — it is simply the distance between one segment's
/// end and the next one's start.
///
/// Memory, not disk: at 16 kHz a minute of floats is under 4 MB, and the photos the session
/// already holds cost more. The staging directory the design doc asks for — where the media
/// lives before Save — is still the right answer for the forty-minute pocket session; when it
/// lands, this class is where the samples leave through.
///
/// Not thread-safe, and not required to be: chunks arrive on the session's one collect loop,
/// and ``segments()`` is read at Save, after they have stopped.
nonisolated final class SessionRecorder {

  private var closed: [RecordedSegment] = []

  private var openSource: CaptureSourceKind?
  private var openOffsetMs: Int64 = 0
  private var openSamples: [Float] = []

  /// Adds one chunk, splitting the take where the chunk says the microphone changed or the
  /// clock says it stopped. `atSeconds` is the session clock at the chunk's arrival — the
  /// same reading the strip places it with.
  func record(_ chunk: AudioChunk, atSeconds: Double) {
    guard !chunk.samples.isEmpty else { return }

    let clockColumn = Int(atSeconds * sonogramColumnsPerSecond)
    let headColumn = Int(Double(headMs()) / 1000.0 * sonogramColumnsPerSecond)
    let changedSource = openSource != nil && openSource != chunk.source
    let stopped =
      openSource != nil
      && placement(clockColumn: clockColumn, written: headColumn) != headColumn

    if openSource == nil || changedSource || stopped {
      close()
      openSource = chunk.source
      openOffsetMs = Int64(atSeconds * 1000)
    }

    openSamples.append(contentsOf: chunk.samples)
  }

  /// Every segment so far, the still-open one included — Save reads this, and a save that
  /// fails and is retried reads it again, so nothing is consumed.
  func segments() -> [RecordedSegment] {
    var all = closed
    if let source = openSource {
      all.append(
        RecordedSegment(source: source, offsetMs: openOffsetMs, samples: openSamples)
      )
    }
    return all
  }

  /// Forgets the session. The next one records onto nothing, like the strip.
  func reset() {
    closed = []
    openSource = nil
    openOffsetMs = 0
    openSamples = []
  }

  /// Where the open segment's audio has reached on the timeline.
  private func headMs() -> Int64 {
    openOffsetMs + Int64(openSamples.count) * 1000 / Int64(captureSampleRate)
  }

  private func close() {
    guard let source = openSource else { return }
    closed.append(
      RecordedSegment(source: source, offsetMs: openOffsetMs, samples: openSamples)
    )
    openSource = nil
    openSamples = []
  }
}
