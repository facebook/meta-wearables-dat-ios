/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FocalPointAlignmentTests.swift
//  birdspotterTests
//

import CoreGraphics
import Testing
@testable import birdspotter

/// The crop arithmetic behind every `CatalogPhoto`: a 400×600 portrait or an 800×300
/// panorama landing in a 400×300 frame, the shapes fill scaling actually produces.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("FocalPointAlignment")
struct FocalPointAlignmentTests {

  private func align(_ focus: FocalPoint, content: CGSize, container: CGSize) -> CGPoint {
    FocalPointAlignment(focus: focus).offset(content: content, container: container)
  }

  /// An uncurated photo must land on the exact point the old center crop chose.
  @Test func align_centeredFocus_matchesCenterCrop() {
    let content = CGSize(width: 400, height: 600)
    let container = CGSize(width: 400, height: 300)

    let center = CGPoint(
      x: (container.width - content.width) / 2,
      y: (container.height - content.height) / 2
    )
    #expect(align(FocalPoint(x: 0.5, y: 0.5), content: content, container: container) == center)
    #expect(center == CGPoint(x: 0, y: -150))
  }

  /// With room to move, the focal point sits exactly on the frame's center line.
  @Test func align_offCenterFocus_centersTheSubject() {
    // Focus at 0.4 of a 600pt-tall image is point 240; offset -90 puts it at the
    // 300pt frame's midline (240 - 90 = 150).
    #expect(
      align(
        FocalPoint(x: 0.5, y: 0.4),
        content: CGSize(width: 400, height: 600),
        container: CGSize(width: 400, height: 300)
      ) == CGPoint(x: 0, y: -90)
    )
  }

  /// A bird by the photo's edge pins the crop there rather than revealing a void.
  @Test func align_focusNearTheEdge_clampsToTheImageEdge() {
    let content = CGSize(width: 400, height: 600)
    let container = CGSize(width: 400, height: 300)

    #expect(align(FocalPoint(x: 0.5, y: 0.05), content: content, container: container) == .zero)
    #expect(align(FocalPoint(x: 0.5, y: 0.95), content: content, container: container) == CGPoint(x: 0, y: -300))
  }

  /// The same arithmetic, sideways — a panorama pans instead of lifting.
  @Test func align_landscapeCrop_pansHorizontally() {
    #expect(
      align(
        FocalPoint(x: 0.7, y: 0.5),
        content: CGSize(width: 800, height: 300),
        container: CGSize(width: 400, height: 300)
      ) == CGPoint(x: -360, y: 0)
    )
  }
}
