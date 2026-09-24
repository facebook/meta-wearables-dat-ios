/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WavCodec.swift
//  birdspotter
//

import Foundation

/// The journal's audio segments as files: 16-bit PCM mono WAV at ``captureSampleRate``,
/// written and read by hand.
///
/// Hand-written for the reason the FFT is — a 44-byte RIFF header is a paragraph of code that
/// reads the same in both languages, where the platform encoders (`AVAudioFile`, `MediaMuxer`)
/// have no shared sentence. WAV rather than raw PCM so the file explains itself: a segment
/// pulled off a device opens in any editor, which is worth more to a demo than the 44 bytes.
///
/// 16-bit rather than the float the pipeline runs in, because these are files: half the bytes,
/// and nothing downstream keeps more than 8 bits per pixel anyway. The round trip costs one
/// quantisation step, inaudible at the levels a bird is recorded at.
///
/// ``decode(_:)`` reads only what ``encode(_:sampleRate:)`` writes — this is not a general WAV
/// reader. Anything but PCM 16-bit mono at the capture rate is refused, loudly, because the
/// only way such a file gets into the media store is a bug somewhere upstream. The one exception
/// is a segment saved before the capture rate rose to 16 kHz, which comes back upsampled — see
/// ``legacySampleRate``.
nonisolated enum WavCodec {

  enum WavError: Error {
    case notAWav
    case unsupportedFormat(String)
    case truncated
  }

  private static let headerBytes = 44
  private static let bytesPerSample = 2

  /// The rate every segment was written at before the capture rate rose to ``captureSampleRate``.
  ///
  /// **Read, and brought up to the current rate, rather than refused.** Those files are outings
  /// somebody kept, and the journal draws and plays everything at one rate — so a segment at the
  /// old one is doubled by linear interpolation on the way in. It gains no bandwidth it never
  /// recorded; it simply lines up with the columns and the playhead again.
  private static let legacySampleRate = 8000

  /// Samples in −1..1 to a complete WAV file.
  static func encode(_ samples: [Float], sampleRate: Int = captureSampleRate) -> Data {
    let dataBytes = samples.count * bytesPerSample
    var bytes = Data(count: headerBytes + dataBytes)

    bytes.putAscii(at: 0, "RIFF")
    bytes.putIntLe(at: 4, 36 + dataBytes)
    bytes.putAscii(at: 8, "WAVE")
    bytes.putAscii(at: 12, "fmt ")
    bytes.putIntLe(at: 16, 16) // fmt chunk size
    bytes.putShortLe(at: 20, 1) // PCM
    bytes.putShortLe(at: 22, 1) // mono
    bytes.putIntLe(at: 24, sampleRate)
    bytes.putIntLe(at: 28, sampleRate * bytesPerSample)
    bytes.putShortLe(at: 32, bytesPerSample) // block align
    bytes.putShortLe(at: 34, 16) // bits per sample
    bytes.putAscii(at: 36, "data")
    bytes.putIntLe(at: 40, dataBytes)

    for (i, sample) in samples.enumerated() {
      // Scaled by 32767 both ways, so a full-scale sample comes back full-scale; the
      // asymmetric −32768 is left unused rather than special-cased.
      let quantised = Int(min(max(sample, -1), 1) * Float(Int16.max))
      bytes.putShortLe(at: headerBytes + i * bytesPerSample, quantised)
    }
    return bytes
  }

  /// A WAV file back to samples in −1..1.
  ///
  /// Walks the chunk list rather than assuming `data` sits at byte 44 — that much
  /// generality is free — but throws ``WavError`` on any format this app does not write.
  static func decode(_ bytes: Data) throws -> [Float] {
    guard bytes.count >= headerBytes else { throw WavError.notAWav }
    guard bytes.ascii(at: 0, count: 4) == "RIFF", bytes.ascii(at: 8, count: 4) == "WAVE" else {
      throw WavError.notAWav
    }

    var formatSeen = false
    var sampleRate = captureSampleRate
    var dataAt = -1
    var dataBytes = 0

    var at = 12
    while at + 8 <= bytes.count {
      let id = bytes.ascii(at: at, count: 4)
      let size = bytes.intLe(at: at + 4)
      let body = at + 8
      switch id {
      case "fmt ":
        guard size >= 16, body + 16 <= bytes.count else { throw WavError.truncated }
        guard bytes.shortLe(at: body) == 1 else {
          throw WavError.unsupportedFormat("Not PCM")
        }
        guard bytes.shortLe(at: body + 2) == 1 else {
          throw WavError.unsupportedFormat("Not mono")
        }
        sampleRate = bytes.intLe(at: body + 4)
        guard sampleRate == captureSampleRate || sampleRate == legacySampleRate else {
          throw WavError.unsupportedFormat("Not \(captureSampleRate) Hz")
        }
        guard bytes.shortLe(at: body + 14) == 16 else {
          throw WavError.unsupportedFormat("Not 16-bit")
        }
        formatSeen = true

      case "data":
        dataAt = body
        dataBytes = size

      default:
        break
      }
      // Chunks are word-aligned; an odd size carries one pad byte.
      at = body + size + (size & 1)
    }

    guard formatSeen, dataAt >= 0 else { throw WavError.notAWav }
    guard dataAt + dataBytes <= bytes.count else { throw WavError.truncated }

    var samples = [Float](repeating: 0, count: dataBytes / bytesPerSample)
    for i in samples.indices {
      samples[i] = Float(bytes.shortLe(at: dataAt + i * bytesPerSample)) / Float(Int16.max)
    }
    return sampleRate == legacySampleRate ? doubled(samples) : samples
  }

  /// Twice as many samples, each new one halfway between its neighbours — see
  /// ``legacySampleRate``. The last sample has no neighbour after it, so it is held.
  private static func doubled(_ samples: [Float]) -> [Float] {
    (0..<(samples.count * 2)).map { i in
      let before = samples[i / 2]
      return i % 2 == 0 ? before : (before + samples[min(i / 2 + 1, samples.count - 1)]) / 2
    }
  }
}

// ── Little-endian plumbing ─────────────────────────────────────────────────

private extension Data {

  mutating func putAscii(at: Int, _ text: String) {
    for (i, scalar) in text.unicodeScalars.enumerated() {
      self[startIndex + at + i] = UInt8(scalar.value)
    }
  }

  func ascii(at: Int, count: Int) -> String {
    String(decoding: self[startIndex + at..<startIndex + at + count], as: UTF8.self)
  }

  mutating func putIntLe(at: Int, _ value: Int) {
    self[startIndex + at] = UInt8(value & 0xFF)
    self[startIndex + at + 1] = UInt8((value >> 8) & 0xFF)
    self[startIndex + at + 2] = UInt8((value >> 16) & 0xFF)
    self[startIndex + at + 3] = UInt8((value >> 24) & 0xFF)
  }

  func intLe(at: Int) -> Int {
    Int(self[startIndex + at])
      | Int(self[startIndex + at + 1]) << 8
      | Int(self[startIndex + at + 2]) << 16
      | Int(self[startIndex + at + 3]) << 24
  }

  mutating func putShortLe(at: Int, _ value: Int) {
    self[startIndex + at] = UInt8(value & 0xFF)
    self[startIndex + at + 1] = UInt8((value >> 8) & 0xFF)
  }

  func shortLe(at: Int) -> Int {
    Int(Int16(truncatingIfNeeded: Int(self[startIndex + at]) | Int(self[startIndex + at + 1]) << 8))
  }
}
