/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  StopControl.swift
//  birdspotter
//

import SwiftUI

/// *This is recording, and this is how you stop it.* A vermilion square and the word, in a dark
/// capsule — the camcorder's own sign, set as a plate rather than as a button.
///
/// It replaced an `✕` at the head of the real-time session, and the difference is what the two say.
/// A close mark means *put this away*; it belongs on a panel that was covering something. A session
/// is not covering anything — it is **running**, with a microphone open — and the honest control for
/// a thing that is running is one that says stop.
///
/// **It used to be a 32-point vermilion disc in the header, and this is the same idea said
/// quietly.** The control now sits on the instrument itself, at the foot of the strip, where a
/// filled red disc would be the brightest thing on a screen whose whole point is a picture that
/// changes — a pool of red beside a live sonogram reads as an alarm rather than as a way out. The
/// square keeps the vermilion, because that is the one mark on it that has to be unmistakable;
/// everything around it is a plate like any other plate in the app.
///
/// **Drawn rather than glyphed**, for the same reason ``LocationDot`` is: there is no icon here to
/// name, only a square, and a rounded rectangle is a primitive any platform draws identically —
/// which is the test the glyph rule actually cares about.
///
/// The capsule is `ink` at ``stopGroundOpacity``, the depth every other piece of chrome laid over a
/// picture in this feature uses — the gaze chip's capsule and the camera foot's gradient both end
/// there — so a control over the strip and a control over the viewfinder sit at the same height.
///
/// A drawing, not a button: the screen wraps it in whatever control it needs, and keeps the tap
/// target and the accessibility label where the action is.
struct StopControl: View {
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: theme.space.snug) {
      RoundedRectangle(cornerRadius: stopSquareRadius, style: .continuous)
        .fill(theme.colors.vermilion)
        .frame(width: stopSquareSize, height: stopSquareSize)

      PlateLabel(text: "Stop", color: theme.colors.textPrimary)
    }
    .padding(.horizontal, theme.space.snug)
    .padding(.vertical, theme.space.tight)
    .background(theme.colors.ink.opacity(stopGroundOpacity), in: .capsule)
  }
}

/// The square, and its corners. Set to the plate's own cap height rather than to a fraction of some
/// larger shape, so the mark and the word read as one line of type.
private let stopSquareSize: CGFloat = 10
private let stopSquareRadius: CGFloat = 2

/// How dark the capsule is. The same value the gaze chip and the camera foot's gradient use — one
/// depth for everything this feature lays over a picture.
private let stopGroundOpacity: Double = 0.6

#Preview("Stop") {
  StopControl()
    .padding(BirdSpotterSpacing().page)
    .birdSpotterTheme()
    .preferredColorScheme(.dark)
}
