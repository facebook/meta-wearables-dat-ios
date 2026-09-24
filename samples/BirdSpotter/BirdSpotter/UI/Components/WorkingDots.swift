/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WorkingDots.swift
//  birdspotter
//

import SwiftUI

/// *Working on it.* Three dots, brightening and fading one after the other.
///
/// The app's one indeterminate indicator, and it is **drawn rather than borrowed**. A SwiftUI
/// `ProgressView` and a Material `CircularProgressIndicator` are two different pictures spinning at
/// two different rates — exactly the drift the glyph set exists to prevent — where a cosine over
/// three circles is the same arithmetic in both languages and therefore the same animation.
///
/// It says *waiting on something that has not answered*, and it is used in the two places on the
/// real-time screen where that is true: the source pill while a pair of glasses is being reached
/// for, and a photo on the log whose identification is still composing. It carries **no progress**
/// — nothing here knows how far along anything is, and a bar that filled would be inventing a
/// number.
///
/// A row of dots rather than a spinner, deliberately. It sits inline, beside a word or a thumbnail,
/// at the height of a line of text — a spinning ring at that size is a smudge, and three dots read
/// as *thinking* at any size a plate does.
struct WorkingDots: View {
  @Environment(\.theme) private var theme

  /// The ink. Defaulted at the call site rather than here, so the component carries no opinion
  /// about which of the palette's inks a wait is in.
  var color: Color?

  var body: some View {
    TimelineView(.animation) { context in
      Canvas { drawing, size in
        let radius = dotSize / 2
        let step = dotSize + dotGap
        // The date's own seconds rather than a `@State` animation: one number, wrapped
        // into the cycle. An `.repeatForever` on three opacities is three animations to
        // keep in step.
        let phase =
          context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: cyclePeriod) / cyclePeriod
        for index in 0..<dotCount {
          let centre = CGPoint(x: radius + step * CGFloat(index), y: size.height / 2)
          let dot = Path(
            ellipseIn: CGRect(
              x: centre.x - radius,
              y: centre.y - radius,
              width: dotSize,
              height: dotSize
            )
          )
          drawing.fill(
            dot,
            with: .color(
              (color ?? theme.colors.textSecondary)
                .opacity(dotOpacity(phase: phase, index: index))
            )
          )
        }
      }
    }
    .frame(
      width: dotSize * CGFloat(dotCount) + dotGap * CGFloat(dotCount - 1),
      height: dotSize
    )
    .accessibilityHidden(true)
  }
}

/// How lit a dot is at this point in the cycle: a cosine, so the wave has no corner in it and the
/// three dots hand off to one another rather than blinking.
///
/// The stagger is a third of a cycle per dot, which is what makes the light look like it is
/// *travelling* along the row rather than three lamps pulsing near each other.
func dotOpacity(phase: Double, index: Int) -> Double {
  let offset = phase - Double(index) / Double(dotCount)
  let wave = (cos(2 * .pi * offset) + 1) / 2
  return dimOpacity + (1 - dimOpacity) * wave
}

/// How many dots there are — and the stagger's denominator.
let dotCount = 3

/// A dot. Small enough to sit on a line of text without setting the line's height.
private let dotSize: CGFloat = 5

/// The air between them. Under a dot's width, so the three read as one mark.
private let dotGap: CGFloat = 3

/// How far down a dot goes at its dimmest. Never to nothing — a row that empties reads as broken.
private let dimOpacity: Double = 0.25

/// One pass of the light along the row. Unhurried; this is a wait, not an alarm.
private let cyclePeriod: Double = 1.2

#Preview("Working") {
  WorkingDots()
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}

#Preview("Working, in gilt") {
  WorkingDots(color: BirdSpotterTheme.resolve(for: .dark).colors.gilt)
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}
