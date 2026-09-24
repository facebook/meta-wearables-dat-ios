/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FocalPointAlignment.swift
//  birdspotter
//

import CoreGraphics

/// Places a fill-scaled image so its ``FocalPoint`` sits as close to the frame's center
/// as the image allows.
///
/// The ideal placement puts the focal point exactly on the frame's center line; each axis
/// then clamps so the image never pulls away from an edge — a bird by the top of its photo
/// pins the crop to the top rather than revealing a strip of nothing below. With the
/// default center point this lands exactly where a plain center crop would, which is why
/// an uncurated photo looks exactly as it always did.
nonisolated struct FocalPointAlignment {

  let focus: FocalPoint

  /// Top-left origin of the scaled content within the container.
  func offset(content: CGSize, container: CGSize) -> CGPoint {
    CGPoint(
      x: offsetFor(content: content.width, container: container.width, focus: focus.x),
      y: offsetFor(content: content.height, container: container.height, focus: focus.y)
    )
  }

  /// Top-left offset of the scaled content along one axis, in the container's space.
  private func offsetFor(content: CGFloat, container: CGFloat, focus: Double) -> CGFloat {
    let ideal = container / 2 - CGFloat(focus) * content
    let overflow = container - content
    // Fill scaling makes content >= container, so the range is [overflow, 0] — but
    // written order-agnostically, a rounding-thin or undersized image stays in bounds.
    return min(max(ideal, min(overflow, 0)), max(overflow, 0))
  }
}
