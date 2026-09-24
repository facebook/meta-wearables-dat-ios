/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LiveWaveform.swift
//  birdspotter
//

import Foundation

/// The shape of *right now*: three travelling waves through one envelope, the way a phone has drawn
/// "I am listening" since Siri did it.
///
/// **This is not the sonogram with the time axis removed — it is a different kind of picture.** The
/// sonogram is a *reading*: every pixel is a measured magnitude at a measured second, and a watcher
/// compares it against the strip on a bird's page. This is an *indicator*: a shape the eye already
/// knows, which moves when the room moves. It is here because a sonogram cannot be read from the
/// back of a room and does not obviously say the microphone is open — and that is a thing a demo
/// needs to say every second it is running.
///
/// **What is real in it, and what is drawing.** The drawing is a sine: ``wavelengths`` of it across
/// the strip, travelling — some of it one way and some the other, see ``curveSpeeds`` — under a
/// fixed envelope that dies at both ends. Nothing about the *shape* is measured — a sine is a sine.
/// What is measured is **how tall each wave stands**:
///
/// - Every curve's height is scaled by the moment's overall level, so the whole picture swells and
///   falls with the room.
/// - Each curve also carries **one third of the spectrum** — low, middle, high. They swell
///   independently, so a voice lifts the first curve, a bird lifts the third, and wind lifts all
///   three. Three curves that merely differed in phase would be decoration; these carry the same
///   three numbers a listener would describe the sound with.
///
/// The bands are normalised against the loudest of the three, so the picture always uses its full
/// height and the *level* is what says how loud it actually was. That is what stops a silent room
/// drawing a confident portrait of its own noise floor.
///
/// **Smooth by construction.** A sine has no jitter in it and the envelope never moves, so the only
/// thing here that can change suddenly is a band's height — and the caller averages those over a
/// fraction of a second before they arrive. There is no state, no easing and no animator inside
/// this: the same numbers in always draw the same frame out.
///
/// **The travel is the caller's clock, and it wants to be the display's.** This screen's own tick
/// is thirty a second, which is right for a strip that scrolls four pixels at a time and visibly
/// wrong for a wave that is meant to glide. So the screen drives `phase` from the per-frame
/// animation clock — `TimelineView(.animation)` — which is plumbing rather than surface,
/// because "the next frame" has no spelling a shared design could pin down.
nonisolated enum LiveWaveform {

  /// Points across the strip's full width. At ``wavelengths`` of sine that is thirty-two points
  /// per wave, which draws as a curve with straight segments between them and no visible corners.
  static let resolution = 128

  /// How many waves fit across the strip. Four: enough that the picture is plainly a *wave* rather
  /// than a single swelling blob, few enough that each lobe is still wide enough to have colour in
  /// it on a phone.
  static let wavelengths = 4

  /// How many curves are laid over each other, and therefore how many bands the spectrum is split
  /// into. Three — low, middle, high — because that is as many as can be told apart at this size,
  /// and because it is the same three a person would use to describe a sound out loud.
  static let curveCount = 3

  /// Every curve's signed heights in -1..1, left edge to right edge, outermost curve first.
  ///
  /// `bins` is a column of the sonogram — magnitudes 0..1, lowest frequency first. `level` is how
  /// loud that column was, on the same scale. `phase` is **seconds from any fixed origin** — the
  /// only thing that makes the waves travel, and the only thing that has to arrive at the display's
  /// refresh rate rather than the session's.
  ///
  /// **A `Double`, and reduced to one cycle before it meets a `Float`.** A per-frame clock hands
  /// over whatever epoch it counts from, which can be hundreds of millions of seconds; a `Float`
  /// has about seven digits, so at that magnitude it would quantise to something like a minute and
  /// the waves would sit dead still between jumps. Taking the fraction of a cycle first means the
  /// caller can pass a raw frame timestamp and never think about it.
  ///
  /// An empty or silent column answers flat lines, which is the honest picture of a microphone
  /// that is open and hearing nothing.
  static func curves(bins: [Float], level: Float, phase: Double) -> [[Float]] {
    let flat = [[Float]](repeating: [Float](repeating: 0, count: resolution), count: curveCount)
    guard !bins.isEmpty, level > 0 else { return flat }

    let bands = bandLevels(bins: bins)
    guard let loudest = bands.max(), loudest > 0 else { return flat }

    return (0..<curveCount).map { curve in
      let amplitude = level * (bands[curve] / loudest) * curveScales[curve]
      let cycles = (phase * Double(curveSpeeds[curve])).truncatingRemainder(dividingBy: 1)
      let travelled = Float(cycles) * 2 * .pi + curveOffsets[curve]

      return (0..<resolution).map { i in
        let t = Float(i) / Float(resolution - 1)
        let angle = t * Float(wavelengths) * 2 * .pi + travelled
        return amplitude * sin(angle) * envelope(t)
      }
    }
  }

  /// The spectrum in ``curveCount`` bands, each the mean of the bins it covers.
  ///
  /// Plain equal thirds of the bins rather than anything logarithmic: the strip already spends its
  /// frequency axis linearly, and a second, cleverer axis here would be two ideas of what "high"
  /// means in one feature.
  static func bandLevels(bins: [Float]) -> [Float] {
    (0..<curveCount).map { band in
      let from = band * bins.count / curveCount
      let to = max(from + 1, (band + 1) * bins.count / curveCount)
      var sum: Float = 0
      for bin in from..<to { sum += bins[bin] }
      return sum / Float(to - from)
    }
  }

  /// What holds the waves down at the two ends: one at the centre, nothing at either edge.
  ///
  /// `cos²` rather than a window with a flat top — the envelope *is* the silhouette here, and it
  /// should be a single swell rather than a plateau with shoulders. Its slope is zero at the
  /// centre and at both ends, so the waves fade in and out of it without a crease.
  private static func envelope(_ t: Float) -> Float {
    let distance = abs(2 * t - 1)
    let taper = cos(distance * .pi / 2)
    return taper * taper
  }

  /// How tall each curve stands relative to its band, outermost first. Only gently stepped: the
  /// bands already differ, and scaling them hard as well would bury whichever one is quiet.
  private static let curveScales: [Float] = [1, 0.85, 0.72]

  /// How fast each curve travels, in waves per second, **signed**: positive runs right to left,
  /// negative left to right. Deliberately unrelated numbers, so the three drift through each other
  /// rather than moving as one striped object — that drift is most of what makes the picture read
  /// as alive.
  ///
  /// **The signs are mixed on purpose, and that is the whole point of them.** Three curves all
  /// travelling the same way read as one thing *scrolling*, and a scroll is a claim about time —
  /// which this reading does not have and the sonogram beside it does. Sending the middle curve
  /// against the other two leaves the eye no coherent direction to lock onto: the picture churns
  /// in place, the way a listening indicator does, instead of appearing to run backwards. Two of
  /// the three go left to right so that whatever direction does briefly read is the one the page
  /// is read in.
  ///
  /// Slower than they were, too. The old set crossed half a wave a second at its fastest, which
  /// is a scroll rate; these glide.
  private static let curveSpeeds: [Float] = [-0.19, 0.27, -0.11]

  /// Where each curve starts, so they are not stacked on top of each other at second zero.
  private static let curveOffsets: [Float] = [0, 2.1, 4.2]
}
