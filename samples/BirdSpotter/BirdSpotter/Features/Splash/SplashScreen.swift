/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// How the splash moves.
///
/// The curves are spelled as cubic béziers at the call sites (`0.42 / 0 / 0.58 / 1` for
/// the spin and the crossfade) because a named platform ease is whatever that platform
/// says it is; the numbers are the mirrored part.
enum SplashMotion {
  /// The rings' travel, eased in and out.
  static let spinMillis = 800

  /// One whole turn, so the rings land back in the badge's drawn orientation —
  /// hand-drawn blobs ending mid-turn would sit visibly askew of the mark.
  static let spinDegrees = 360

  /// A beat at rest before the reveal.
  static let holdMillis = 60

  /// The splash dissolving into the shell. The caller owns this one — see `ContentView`.
  static let crossfadeMillis = 160
}

/// The launch moment: the badge on bare paper, its rings turning about a still swallow while the
/// app opens, then a beat at rest before the caller crossfades the whole thing away.
///
/// The OS launch frame shown before any of this is the same paper *with the same badge* —
/// `UILaunchScreen` in BirdSpotter-Info.plist, showing `LaunchBadge` at this view's size
/// and safe-area centering. That frame is static by platform rule — nothing animates until
/// the process is up — so this view draws the identical frame and simply starts the rings
/// turning: a handoff, not an entrance, which is why the badge never fades in.
struct SplashScreen: View {
  @Environment(\.theme) private var theme

  /// Fired once the badge has landed and held. The caller owns the crossfade out.
  let onFinished: () -> Void

  @State private var spinDegrees = 0.0

  // Artwork, not layout: the badge is a plate drawn at the size the launch moment
  // wants, so it is deliberately not a `theme.space` role. It equals LaunchBadge's
  // intrinsic 168 pt exactly — change one without the other and the handoff jumps.
  private let badgeSize: CGFloat = 168

  var body: some View {
    ZStack {
      // Full-bleed on purpose: the splash owns the whole frame, bars and all.
      theme.colors.paper.ignoresSafeArea()

      ZStack {
        Image(glyph: theme.glyphs.markRings)
          .resizable()
          .rotationEffect(.degrees(spinDegrees))
        Image(glyph: theme.glyphs.markBird)
          .resizable()
      }
      .frame(width: badgeSize, height: badgeSize)
      .foregroundStyle(theme.colors.textPrimary)
    }
    // Decoration. VoiceOver users get the shell as soon as it is interactive; the
    // splash never holds focus.
    .accessibilityHidden(true)
    .onAppear(perform: run)
  }

  private func run() {
    withAnimation(
      .timingCurve(0.42, 0, 0.58, 1, duration: seconds(SplashMotion.spinMillis)),
      completionCriteria: .logicallyComplete
    ) {
      spinDegrees = Double(SplashMotion.spinDegrees)
    } completion: {
      Task {
        try? await Task.sleep(for: .milliseconds(SplashMotion.holdMillis))
        onFinished()
      }
    }
  }

  private func seconds(_ millis: Int) -> Double {
    Double(millis) / 1000
  }
}

#Preview {
  SplashScreen(onFinished: {})
    .birdSpotterTheme()
}
