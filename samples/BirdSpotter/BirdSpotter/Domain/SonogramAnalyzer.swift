/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramAnalyzer.swift
//  birdspotter
//

import Foundation

/// How many samples go into one column. 512 at 16 kHz is **32 ms** — long enough to resolve a
/// warbler's trill, short enough that the strip keeps moving.
nonisolated let sonogramWindow = 512

/// How far the window advances between columns. Half a window, so consecutive columns overlap and
/// a call that starts mid-window still lands somewhere legible: **62.5 columns per second**.
nonisolated let sonogramHop = 256

/// Bins in a column — half the window, covering DC to 8 kHz in 31.25 Hz steps.
nonisolated let sonogramBins = sonogramWindow / 2

/// The quietest thing the strip draws, in decibels below full scale.
///
/// Bird song covers a range that linear amplitude renders as a black rectangle with three white
/// dots in it, so the strip is drawn in dB and everything under this is simply floor.
nonisolated let sonogramFloorDb: Float = -70

/// One column of the strip: ``sonogramBins`` magnitudes in 0..1, lowest frequency first, and the
/// one number that says how loud the whole column was.
///
/// **The level is not the magnitudes summed.** It is the window's own RMS, measured on the samples
/// before the Hann taper touches them — a fact about the sound rather than about the transform of
/// it. It rides here because the strip has two readings of one instrument and both come off one
/// pass of the analyzer: see ``StripReading``.
///
/// It is normalised on the *same* dB scale the magnitudes are, floor and all, so a column that
/// paints bright on the sonogram stands tall on the waveform. Two scales would be two instruments.
nonisolated struct SonogramColumn: Sendable {
  let magnitudes: [Float]

  /// How loud this column was, 0..1 on ``sonogramFloorDb``'s scale.
  ///
  /// Defaulted, so a test or a preview that only cares about the picture can still say
  /// `SonogramColumn(magnitudes:)` and mean silence.
  let level: Float

  init(magnitudes: [Float], level: Float = 0) {
    self.magnitudes = magnitudes
    self.level = level
  }
}

/// Turns a stream of ``AudioChunk``s into the columns a live sonogram is drawn from.
///
/// **Stateful on purpose.** Audio arrives in whatever slices the microphone feels like giving, and
/// a column needs exactly ``sonogramWindow`` samples starting every ``sonogramHop`` — so leftovers
/// carry from one chunk to the next. Feed it everything, in order, and it answers with however
/// many columns that made possible, which is often none.
///
/// **The transform is written out longhand.** This could call vDSP and be faster, and that is
/// exactly why it doesn't: this is the kind of code Meta puts on a slide, and a radix-2
/// Cooley–Tukey loop is readable as arithmetic where a framework call is readable only as a
/// framework call. It costs about 65k floating-point operations per column at 62 columns a
/// second, which is nothing on a phone.
///
/// Twiddle factors are `Double` even though samples and output are `Float`: the recurrence that
/// walks them around the unit circle accumulates error, and single precision shows it as a smear
/// across the top of the strip.
nonisolated final class SonogramAnalyzer {

  /// Samples seen but not yet consumed by a column.
  private var pending: [Float] = []

  /// Scratch for one column's transform, reused by every column the analyzer ever draws.
  ///
  /// The transform is in-place and its result is read out into a ``SonogramColumn`` before the
  /// next column begins, so these are never needed twice over — and allocating them per column
  /// meant two heap allocations sixty-two times a second live, and twice ``sonogramCapacity`` of
  /// them again every time the journal reopens the walk.
  ///
  /// Not part of the analyzer's state in any meaningful sense: ``reset()`` leaves them alone,
  /// because a column overwrites every element it reads.
  private var real = [Double](repeating: 0, count: sonogramWindow)
  private var imaginary = [Double](repeating: 0, count: sonogramWindow)

  init() {}

  /// Adds a chunk and returns every column it completed, oldest first.
  ///
  /// Empty is the ordinary answer for a short chunk — the samples are kept, not dropped.
  func analyze(_ chunk: AudioChunk) -> [SonogramColumn] {
    pending += chunk.samples

    var columns: [SonogramColumn] = []
    var offset = 0
    while pending.count - offset >= sonogramWindow {
      columns.append(columnAt(offset))
      offset += sonogramHop
    }

    // Keep the tail: the next window starts inside it.
    if offset > 0 { pending.removeFirst(offset) }
    return columns
  }

  /// Forgets everything buffered — a new session starts on silence, not on the last one's tail.
  func reset() {
    pending = []
  }

  private func columnAt(_ offset: Int) -> SonogramColumn {
    // `real` is written in full by the loop below, so it carries nothing across; `imaginary`
    // has to start each column at zero, which is what makes this a real-input transform.
    imaginary.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    // The level is taken in the same pass, off the untapered sample: the Hann window is there
    // to stop a tone leaking across the transform, and applying it to a loudness reading would
    // only mean the same second measured quieter at the edges of a window nobody chose.
    var sumOfSquares = 0.0
    for i in 0..<sonogramWindow {
      let sample = Double(pending[offset + i])
      sumOfSquares += sample * sample
      real[i] = sample * Self.hannWindow[i]
    }

    Self.transform(&real, &imaginary)

    var magnitudes = [Float](repeating: 0, count: sonogramBins)
    for bin in 0..<sonogramBins {
      // `magnitudeScale` puts a full-scale sine at 1.0, so 0 dB means "as loud as it gets"
      // rather than an arbitrary reference nobody can read off the strip.
      let magnitude =
        (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]).squareRoot()
        * Self.magnitudeScale
      let decibels = 20 * log10(magnitude + Self.silence)
      magnitudes[bin] = Self.normalise(decibels)
    }

    // RMS rather than peak: a peak is one sample of 512 and jitters a whole column's worth on
    // a single click, where the RMS is what the second actually sounded like. A full-scale sine
    // reads 0.707, which is -3 dB — near the top of the scale without pinning to it.
    let rms = (sumOfSquares / Double(sonogramWindow)).squareRoot()
    let level = Self.normalise(20 * log10(rms + Self.silence))

    return SonogramColumn(magnitudes: magnitudes, level: level)
  }

  // MARK: - The transform

  /// Hann, precomputed once. A rectangular window would leak every pure tone across the whole
  /// column and turn each bird into a vertical smudge.
  private static let hannWindow: [Double] = (0..<sonogramWindow).map { i in
    0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(sonogramWindow - 1)))
  }

  /// Two over the window's sum. The Hann window sums to half its length and a real signal splits
  /// its energy between the positive and negative frequency, so this is what puts a full-scale
  /// sine at magnitude 1.
  private static let magnitudeScale = 2.0 / (Double(sonogramWindow) / 2.0)

  /// Keeps `log10` off zero. Well below the floor, so it never shows.
  private static let silence = 1e-12

  private static func normalise(_ decibels: Double) -> Float {
    let floor = Double(sonogramFloorDb)
    let clamped = min(max(decibels, floor), 0)
    return Float((clamped - floor) / -floor)
  }

  /// In-place radix-2 Cooley–Tukey, decimation in time.
  ///
  /// Two halves: reorder the input into bit-reversed positions, then combine pairs, quads,
  /// octets and so on up to the whole array. ``sonogramWindow`` is a power of two, which is what
  /// lets the second half be a loop rather than a recursion.
  private static func transform(_ real: inout [Double], _ imaginary: inout [Double]) {
    let n = real.count

    var j = 0
    for i in 1..<n {
      var bit = n >> 1
      while j & bit != 0 {
        j ^= bit
        bit >>= 1
      }
      j |= bit
      if i < j {
        real.swapAt(i, j)
        imaginary.swapAt(i, j)
      }
    }

    var length = 2
    while length <= n {
      let angle = -2 * Double.pi / Double(length)
      let stepReal = cos(angle)
      let stepImaginary = sin(angle)
      var start = 0
      while start < n {
        var twiddleReal = 1.0
        var twiddleImaginary = 0.0
        for k in 0..<(length / 2) {
          let evenReal = real[start + k]
          let evenImaginary = imaginary[start + k]
          let oddIndex = start + k + length / 2
          let oddReal = real[oddIndex] * twiddleReal - imaginary[oddIndex] * twiddleImaginary
          let oddImaginary = real[oddIndex] * twiddleImaginary + imaginary[oddIndex] * twiddleReal

          real[start + k] = evenReal + oddReal
          imaginary[start + k] = evenImaginary + oddImaginary
          real[oddIndex] = evenReal - oddReal
          imaginary[oddIndex] = evenImaginary - oddImaginary

          let nextTwiddleReal = twiddleReal * stepReal - twiddleImaginary * stepImaginary
          twiddleImaginary = twiddleReal * stepImaginary + twiddleImaginary * stepReal
          twiddleReal = nextTwiddleReal
        }
        start += length
      }
      length <<= 1
    }
  }
}
