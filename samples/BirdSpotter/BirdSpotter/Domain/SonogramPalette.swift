/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramPalette.swift
//  birdspotter
//

import Foundation

/// One colour on the sonogram ramp, 0–255 per channel — a value, not a `Color`, because the strip
/// is built as pixels and never as views.
nonisolated struct SonogramColour: Equatable, Sendable {
  var red: UInt8
  var green: UInt8
  var blue: UInt8
}

/// The colours a sonogram is drawn in: **magma**, black ground through purple and red to a pale
/// yellow, and the loudest thing on the strip is very nearly white.
///
/// **Not read off the theme, and that is the point.** The catalog's reference strips are rendered
/// by the seed pipeline with `ffmpeg`'s `showspectrumpic=color=magma` — see `render_sonogram` in
/// the bundled sonogram assets — so a live session drawn in the app's own gilt and verdigris
/// looked like a different instrument to the picture on the bird's page. A watcher comparing what
/// they just heard against the reference is comparing two spectrograms, and two spectrograms of the
/// same bird should not be two different colours. Matching the pipeline is worth more here than
/// matching the palette.
///
/// The stops are ffmpeg's own table, read back off the colour bar `showspectrumpic=legend=enabled`
/// draws, and thinned to the fewest that reproduce it: piecewise-linear through these eight is
/// within 3/255 of the real curve everywhere, which is under a quantization step of the 32-colour
/// PNGs the pipeline actually ships. The positions are uneven because magma is — it turns hard
/// through the purples and barely at all across the reds.
nonisolated enum SonogramPalette {

  /// Level, then the colour at it. Ascending, first at 0 and last at 1.
  static let stops: [(level: Double, colour: SonogramColour)] = [
    (0.0000, SonogramColour(red: 0, green: 0, blue: 0)),
    (0.1006, SonogramColour(red: 10, green: 14, blue: 105)),
    (0.2327, SonogramColour(red: 64, green: 22, blue: 94)),
    (0.3522, SonogramColour(red: 155, green: 46, blue: 101)),
    (0.4843, SonogramColour(red: 180, green: 53, blue: 94)),
    (0.6415, SonogramColour(red: 246, green: 75, blue: 81)),
    (0.9245, SonogramColour(red: 236, green: 204, blue: 117)),
    (1.0000, SonogramColour(red: 253, green: 253, blue: 243)),
  ]

  /// The colour at `level`, 0…1. Anything outside that clamps to an end — a magnitude is already
  /// normalised by the time it reaches here, and a strip needs an answer rather than a trap.
  static func colour(atLevel level: Double) -> SonogramColour {
    guard level > 0 else { return stops[0].colour }
    guard level < 1 else { return stops[stops.count - 1].colour }

    for index in 1..<stops.count where level <= stops[index].level {
      let (lowLevel, low) = stops[index - 1]
      let (highLevel, high) = stops[index]
      let span = highLevel - lowLevel
      let fraction = span > 0 ? (level - lowLevel) / span : 0
      return SonogramColour(
        red: mix(low.red, high.red, fraction),
        green: mix(low.green, high.green, fraction),
        blue: mix(low.blue, high.blue, fraction)
      )
    }
    return stops[stops.count - 1].colour
  }

  /// The whole ramp as one lookup, one entry per byte of magnitude.
  ///
  /// Built once and read per pixel: a window is 64,000 of them and interpolating at each would be
  /// 64,000 walks of the stop list to produce 256 distinct answers.
  static func ramp() -> [SonogramColour] {
    (0..<rampSize).map { colour(atLevel: Double($0) / Double(rampSize - 1)) }
  }

  /// One entry per value a magnitude byte can take.
  static let rampSize = 256

  private static func mix(_ from: UInt8, _ to: UInt8, _ fraction: Double) -> UInt8 {
    let value = Double(from) + (Double(to) - Double(from)) * fraction
    return UInt8(min(max(value.rounded(), 0), 255))
  }
}
