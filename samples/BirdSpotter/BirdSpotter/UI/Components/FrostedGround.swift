/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FrostedGround.swift
//  birdspotter
//

import CoreGraphics
import SwiftUI

/// The surface a panel stands on before it has anything to show: the lacquer, **screened** — an
/// ordered dither laid over it in the app's cream, fine enough to read as frost rather than as
/// pattern.
///
/// **Dither, not blur.** A frosted panel usually means a backdrop blur, and a backdrop blur is a
/// thing each OS hands over on its own terms, or not at all — so building one would be choosing
/// the exact drift the mirrored-architecture rule exists to prevent. An ordered dither is
/// arithmetic: the same 8×8 matrix, the same tile, the same picture anywhere, with nothing
/// borrowed from the OS.
///
/// It is also the *better* answer for this cabinet. Everything here is printed — plate labels,
/// engraved rules, a sonogram rendered like a plate — and a screened tone is how printing has made
/// a half-tint since the aquatint. Apple's glass would be the one surface in the app that came from
/// somewhere else.
///
/// **Bayer, specifically**, because it is the dither with no randomness in it: a `Math.random()`
/// speckle would be a different picture on each platform, on each launch, and on each redraw. The
/// matrix below is the standard 8×8 — every value 0–63 exactly once, arranged so that thresholding
/// it at any level gives the most even spread of dots that level allows.
///
/// The tile carries **alpha only** and is used as a mask, so the colour still comes from the theme
/// rather than being baked into pixels. That is what lets the ink be `textPrimary` and follow the
/// palette instead of being a cream hex sitting outside it.
struct FrostedGround: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ZStack {
      theme.colors.lacquerRaised

      if let tile = Self.tile {
        theme.colors.textPrimary
          .opacity(frostOpacity)
          .mask {
            Image(decorative: tile, scale: 1, orientation: .up)
              .resizable(resizingMode: .tile)
          }
      }
    }
  }

  /// The screen itself: one 8×8 tile, built once. White throughout, carrying the matrix in its
  /// alpha — which is the half a mask reads.
  private static let tile: CGImage? = {
    let side = bayerSide
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    for i in 0..<(side * side) {
      let alpha = UInt8(bayerMatrix[i] * 255 / (side * side - 1))
      // Premultiplied: white at this alpha is that alpha in every channel.
      pixels[i * 4] = alpha
      pixels[i * 4 + 1] = alpha
      pixels[i * 4 + 2] = alpha
      pixels[i * 4 + 3] = alpha
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: side,
      height: side,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      // Nearest neighbour: the whole point of a dither is that its cells are cells. Let a
      // renderer smooth them and it is a grey wash with extra steps.
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }()
}

/// The standard 8×8 Bayer threshold matrix, row-major — every value 0–63 exactly once.
///
/// If one side is ever changed the two grounds stop being the same picture, which is the only thing
/// this drawing has to get right.
private let bayerMatrix: [Int] = [
  0, 32, 8, 40, 2, 34, 10, 42,
  48, 16, 56, 24, 50, 18, 58, 26,
  12, 44, 4, 36, 14, 46, 6, 38,
  60, 28, 52, 20, 62, 30, 54, 22,
  3, 35, 11, 43, 1, 33, 9, 41,
  51, 19, 59, 27, 49, 17, 57, 25,
  15, 47, 7, 39, 13, 45, 5, 37,
  63, 31, 55, 23, 61, 29, 53, 21,
]

private let bayerSide = 8

/// How much cream the screen carries at its heaviest. Frost is a *hint* of light on a dark ground —
/// past this the panel stops reading as lacquer with a tint and starts reading as grey.
private let frostOpacity: Double = 0.12

#Preview("Frosted") {
  FrostedGround()
    .frame(width: 300, height: 200)
    .clipShape(.rect(cornerRadius: BirdSpotterSpacing().gutter))
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}
