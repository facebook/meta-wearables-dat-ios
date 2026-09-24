/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PhotoZoom.swift
//  birdspotter
//

import CoreGraphics

/// How far a photograph is magnified, and how far it has been dragged under the magnification.
///
/// **The whole of the lightbox's arithmetic, in a value with no view attached to it.** Pinch,
/// pan, double-tap and the settle at the end of a gesture are four ways of asking the same two
/// questions — *how big* and *how far over* — and every one of them has to answer the same rule
/// about what is allowed. Kept as a value rather than as three `@State` numbers on the view
/// because the clamping is where this gets subtle, and clamping spread across four gesture
/// callbacks is four chances to get it slightly different.
///
/// The offset is in points, measured from the photograph sitting centred. Positive x moves the
/// picture right, positive y moves it down — the direction a finger travels.
nonisolated struct PhotoZoom: Sendable, Equatable {

  /// 1 is the whole photograph fitted to the viewport; ``maxScale`` is as close as it goes.
  var scale: Double

  var offsetX: Double
  var offsetY: Double

  /// The resting state: fitted, centred, and what a lightbox opens at.
  static let idle = PhotoZoom(scale: 1, offsetX: 0, offsetY: 0)

  /// Whether the picture is magnified at all — **the switch the drag gesture is hung on.**
  ///
  /// At rest a drag belongs to the dismissal, and once magnified it belongs to the pan. There
  /// is no third reading, so the two gestures never have to negotiate: exactly one of them is
  /// live at any moment, decided by this.
  ///
  /// The epsilon is not defensive noise — a pinch that returns to 1 lands on 0.9999999 as
  /// often as on 1, and a picture that could not be dismissed because it was a millionth
  /// magnified would be a bug nobody could reproduce.
  var isZoomed: Bool { scale > 1 + zoomEpsilon }

  /// This magnification, re-clamped for a viewport and a fitted picture.
  ///
  /// **Scale is clamped first and the offset is clamped against the result**, which is the
  /// ordering the whole type depends on: zooming back out has to pull the picture towards the
  /// centre, and it can only know how far once it knows how big. Doing it the other way leaves
  /// a photograph zoomed out to 1 sitting off-centre with a band of black down one side.
  func settled(in viewport: CGSize, fitting content: CGSize) -> PhotoZoom {
    let clampedScale = min(max(scale, 1), maxScale)
    let limitX = Self.panLimit(viewport: viewport.width, content: content.width, scale: clampedScale)
    let limitY = Self.panLimit(viewport: viewport.height, content: content.height, scale: clampedScale)
    return PhotoZoom(
      scale: clampedScale,
      offsetX: min(max(offsetX, -limitX), limitX),
      offsetY: min(max(offsetY, -limitY), limitY)
    )
  }

  /// Magnified by a step — what a pinch reporting *change* rather than *total* hands over.
  ///
  /// The offset is scaled with it so the magnification grows about the picture's centre rather
  /// than sliding the picture out from under the fingers.
  func scaled(by step: Double, in viewport: CGSize, fitting content: CGSize) -> PhotoZoom {
    PhotoZoom(
      scale: scale * step,
      offsetX: offsetX * step,
      offsetY: offsetY * step
    ).settled(in: viewport, fitting: content)
  }

  /// Dragged by a step, clamped so an edge of the photograph can never be pulled inside the
  /// viewport — the rule that makes a pan feel like moving a picture behind a window rather
  /// than like throwing it around a room.
  func panned(byX dx: Double, y dy: Double, in viewport: CGSize, fitting content: CGSize) -> PhotoZoom {
    PhotoZoom(
      scale: scale,
      offsetX: offsetX + dx,
      offsetY: offsetY + dy
    ).settled(in: viewport, fitting: content)
  }

  /// What a double tap does: all the way out if it is magnified at all, otherwise to
  /// ``doubleTapScale``, centred.
  ///
  /// **Out wins whenever there is any magnification**, rather than cycling through steps. A
  /// double tap is the gesture for *undo whatever I just did to this picture*, and a viewer
  /// that answered it by zooming further would be the one control here that cannot be trusted.
  func toggledZoom(in viewport: CGSize, fitting content: CGSize) -> PhotoZoom {
    isZoomed
      ? .idle
      : PhotoZoom(scale: doubleTapScale, offsetX: 0, offsetY: 0)
        .settled(in: viewport, fitting: content)
  }

  /// How far the picture may travel along one axis: half of whatever the magnification pushed
  /// past the viewport, and zero where the picture still fits.
  ///
  /// Half, because the offset is measured from centred — the overhang is split between the two
  /// edges, and either one may be brought to the viewport's edge but no further.
  private static func panLimit(viewport: Double, content: Double, scale: Double) -> Double {
    max(0, (content * scale - viewport) / 2)
  }
}

/// As close as a photograph goes. Four is generous for a picture that is usually a bird at the
/// far end of a lens, and short of the point where a phone capture is entirely pixels.
nonisolated let maxScale = 4.0

/// Where a double tap lands. Enough to be plainly a magnification rather than a nudge, and shy
/// of the ceiling so the pinch still has somewhere to go afterwards.
nonisolated let doubleTapScale = 2.5

/// How far from 1 still counts as *not magnified* — see ``PhotoZoom/isZoomed``.
private let zoomEpsilon = 0.0001
