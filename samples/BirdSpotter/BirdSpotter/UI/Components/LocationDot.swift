/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LocationDot.swift
//  birdspotter
//

import SwiftUI

/// *We know where this is.* A small verdigris dot with a halo breathing out of it.
///
/// It appears only once a fix has actually landed. There is no searching state and no failed
/// state, because ``LocationProvider`` answers `nil` for every way of not knowing — denied,
/// disabled, or simply never arrived — and a dot that stayed lit to mean "still trying" would be
/// the one dishonest mark on a screen whose whole job is saying what it really heard.
///
/// Verdigris rather than a signal green: the palette's green is the palette's green, and a colour
/// borrowed from a system status bar would be the first thing on this screen not drawn from the
/// cabinet. It is a drawn shape rather than a glyph for the same reason a rule is — there is no
/// icon here to name, only a circle and a ring, and the pulse is the half that carries the meaning.
///
/// **It belongs beside the pin and nowhere else.** The dot is a fact about the fix, so it goes next
/// to the thing that means *where*; beside the source plate it read as a second, vaguer claim about
/// the session in general.
struct LocationDot: View {
  @Environment(\.theme) private var theme

  /// Whether the fix has landed. False draws nothing, and keeps the space it would take.
  let isLocated: Bool

  /// Drives the halo. Held here rather than derived from `isLocated` so the pulse is already
  /// running when the fix lands and the dot fades in mid-breath, the way a live indicator does.
  @State private var pulsing = false

  var body: some View {
    ZStack {
      Circle()
        .fill(theme.colors.verdigris)
        .frame(width: dotSize, height: dotSize)
        .scaleEffect(pulsing ? haloScale : 1)
        .opacity(pulsing ? 0 : haloOpacity)

      Circle()
        .fill(theme.colors.verdigris)
        .frame(width: dotSize, height: dotSize)
    }
    // The halo's full extent, reserved: a frame that grew with the pulse would push the pin
    // beside it back and forth once a second.
    .frame(width: dotSize * haloScale, height: dotSize * haloScale)
    .opacity(isLocated ? 1 : 0)
    .animation(.easeOut(duration: 0.4), value: isLocated)
    .onAppear {
      withAnimation(.easeOut(duration: pulsePeriod).repeatForever(autoreverses: false)) {
        pulsing = true
      }
    }
    .accessibilityHidden(!isLocated)
    .accessibilityLabel("Location found")
  }
}

/// The dot itself. Small — it is a state, not a control.
private let dotSize: CGFloat = 8

/// How far the halo travels before it is gone, and how much of it there is to begin with.
private let haloScale: CGFloat = 2.6
private let haloOpacity: Double = 0.5

/// One breath. Slow enough to read as alive rather than as an alert.
private let pulsePeriod: Double = 1.8

#Preview("Located") {
  LocationDot(isLocated: true)
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}

#Preview("No fix") {
  LocationDot(isLocated: false)
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}
