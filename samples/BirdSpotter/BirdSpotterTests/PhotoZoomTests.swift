/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PhotoZoomTests.swift
//  birdspotterTests
//

import CoreGraphics
import Testing
@testable import birdspotter

/// The lightbox's arithmetic: what magnification is allowed, how far a magnified picture may be
/// dragged, and what the two gestures agree about at the boundary between them.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("PhotoZoom")
struct PhotoZoomTests {

  /// A viewport wider than it is tall, and a picture fitted into it letterboxed — the shape a
  /// 4:3 capture actually takes on a phone held upright, and the one where the two axes have
  /// genuinely different answers.
  private let viewport = CGSize(width: 400, height: 800)
  private let content = CGSize(width: 400, height: 300)

  @Test func idle_isFittedAndCentred() {
    #expect(PhotoZoom.idle.scale == 1)
    #expect(PhotoZoom.idle.offsetX == 0)
    #expect(PhotoZoom.idle.offsetY == 0)
    #expect(!PhotoZoom.idle.isZoomed)
  }

  @Test func isZoomed_ignoresTheResidueOfAPinchThatReturned() {
    // What a pinch back to 1 actually lands on. Reading this as magnified would leave a
    // picture that cannot be dismissed for a reason nobody can see.
    let settled = PhotoZoom(scale: 1.00000001, offsetX: 0, offsetY: 0)

    #expect(!settled.isZoomed)
  }

  @Test func settled_clampsScaleToTheCeiling() {
    let zoomed = PhotoZoom(scale: 99, offsetX: 0, offsetY: 0)
      .settled(in: viewport, fitting: content)

    #expect(zoomed.scale == maxScale)
  }

  @Test func settled_clampsScaleToTheFittedPicture() {
    let shrunk = PhotoZoom(scale: 0.2, offsetX: 0, offsetY: 0)
      .settled(in: viewport, fitting: content)

    #expect(shrunk.scale == 1)
  }

  @Test func settled_holdsAnUnmagnifiedPictureCentred() {
    // At 1 the picture fits by construction, so there is nowhere to drag it — every offset
    // clamps back to nothing.
    let dragged = PhotoZoom(scale: 1, offsetX: 120, offsetY: -90)
      .settled(in: viewport, fitting: content)

    #expect(dragged.offsetX == 0)
    #expect(dragged.offsetY == 0)
  }

  @Test func settled_letsAnEdgeReachTheViewportAndNoFurther() {
    // 400 wide at 2× is 800 across a 400 viewport: 400 of overhang, split between two edges.
    let dragged = PhotoZoom(scale: 2, offsetX: 999, offsetY: 0)
      .settled(in: viewport, fitting: content)

    #expect(dragged.offsetX == 200)
  }

  @Test func settled_clampsEachAxisAgainstItsOwnOverhang() {
    // The picture is letterboxed: at 2× it overhangs the width and still falls short of the
    // height, so one axis pans and the other cannot.
    let dragged = PhotoZoom(scale: 2, offsetX: 999, offsetY: 999)
      .settled(in: viewport, fitting: content)

    #expect(dragged.offsetX == 200)
    #expect(dragged.offsetY == 0)
  }

  @Test func settled_pullsThePictureBackAsItShrinks() {
    // The ordering this type depends on: a picture dragged to its limit at 4× and then zoomed
    // out has to be brought back towards the centre, or it sits off to one side with a band of
    // black beside it.
    let atLimit = PhotoZoom(scale: 4, offsetX: 999, offsetY: 0)
      .settled(in: viewport, fitting: content)
    let zoomedOut = PhotoZoom(scale: 2, offsetX: atLimit.offsetX, offsetY: 0)
      .settled(in: viewport, fitting: content)

    #expect(atLimit.offsetX == 600)
    #expect(zoomedOut.offsetX == 200)
  }

  @Test func scaledBy_magnifiesAboutTheCentre() {
    let stepped = PhotoZoom(scale: 1.5, offsetX: 40, offsetY: 20)
      .scaled(by: 2, in: viewport, fitting: content)

    #expect(stepped.scale == 3)
    // The offset grew with the picture, so whatever was under the fingers stayed there.
    #expect(stepped.offsetX == 80)
    #expect(stepped.offsetY == 40)
  }

  @Test func pannedBy_movesWithTheFinger() {
    // 3× rather than 2×, because the picture is letterboxed: at 2× it is 600 tall in an 800
    // viewport and the vertical drag has nowhere to go, which would test the clamp instead of
    // the travel. At 3× both axes genuinely overhang.
    let dragged = PhotoZoom(scale: 3, offsetX: 0, offsetY: 0)
      .panned(byX: 30, y: -15, in: viewport, fitting: content)

    #expect(dragged.offsetX == 30)
    #expect(dragged.offsetY == -15)
  }

  @Test func pannedBy_cannotPullAnEdgeInsideTheViewport() {
    let dragged = PhotoZoom(scale: 2, offsetX: 150, offsetY: 0)
      .panned(byX: 500, y: 0, in: viewport, fitting: content)

    #expect(dragged.offsetX == 200)
  }

  @Test func toggledZoom_magnifiesFromRest() {
    let tapped = PhotoZoom.idle.toggledZoom(in: viewport, fitting: content)

    #expect(tapped.scale == doubleTapScale)
    #expect(tapped.offsetX == 0)
    #expect(tapped.offsetY == 0)
  }

  @Test func toggledZoom_goesAllTheWayOutFromAnyMagnification() {
    // Out wins whether the picture was double-tapped to 2.5 or pinched past it — a double tap
    // is the gesture for undoing what was just done, so it never zooms further.
    let fromDoubleTap = PhotoZoom(scale: doubleTapScale, offsetX: 0, offsetY: 0)
      .toggledZoom(in: viewport, fitting: content)
    let fromCeiling = PhotoZoom(scale: maxScale, offsetX: 600, offsetY: 0)
      .toggledZoom(in: viewport, fitting: content)

    #expect(fromDoubleTap == .idle)
    #expect(fromCeiling == .idle)
  }

  @Test func settled_survivesAViewportWithNoAreaYet() {
    // The first layout pass hands over zeroes, and the arithmetic runs before the picture has
    // been measured. Nothing here may divide by that.
    let measured = PhotoZoom(scale: 2, offsetX: 50, offsetY: 50)
      .settled(in: .zero, fitting: .zero)

    #expect(measured.scale == 2)
    #expect(measured.offsetX == 0)
    #expect(measured.offsetY == 0)
  }
}
