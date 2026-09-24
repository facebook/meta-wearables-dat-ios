/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FlowLayout.swift
//  birdspotter
//

import SwiftUI

/// Lays its subviews left to right, wrapping onto a new line when the next one will not
/// fit — each keeping its own ideal width rather than being squeezed to share a row.
///
/// A run of chips is the case this exists for: an `HStack` gives every child a share of one
/// line, so a fourth chip does not move down, it gets crushed until its text sets one
/// character to a line.
///
/// **Not part of the mirrored surface**, and it does not need to be: this is a wrapping row,
/// a behaviour a UI framework either ships or does not. The mirror is at the call site — the
/// chips wrap the same way wherever they are drawn.
struct FlowLayout: Layout {

  /// The gap between chips, along both axes — one of the roles on `theme.space`.
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(within: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y),
          anchor: .topLeading,
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  /// One line's worth: which subviews are on it, and how big it is.
  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      // A subview wider than the whole line still gets a line of its own rather than
      // an empty one above it — hence the check that the row already holds something.
      if !row.indices.isEmpty && needed > maxWidth {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }
}
