/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/*
 * Spacing — "The Subscriber's Plate".
 *
 * Every value is a multiple of 4. Eight roles, each with one job; if a gap on screen is not one
 * of these, it is a bug rather than a decision. One rule goes with them above all others: that
 * a stack sets its rhythm with `spacing:` *or* with per-child padding, never both.
 */

/// The mirrored spacing scale — one role per gap the design names, and the numbers behind them.
///
/// Roles, not sizes: the space under a section heading is `related`, which is what lets Meta's
/// docs show the same design whichever snippet a reader is looking at. A screen that reaches
/// for a literal is a screen that will drift.
struct BirdSpotterSpacing {

  /// 4 — two lines that are one thought: a species name and its binomial.
  let tight: CGFloat = 4

  /// 8 — a mark and its label: an icon and the word beside it.
  let snug: CGFloat = 8

  /// 12 — a heading and the thing it heads.
  let related: CGFloat = 12

  /// 16 — two items in the same block, and the air around a rule.
  let separate: CGFloat = 16

  /// 20 — inside a card's rule. One step under the gutter on purpose, so a card's text
  /// sits *within* the page margin instead of lining up with it.
  let cardInset: CGFloat = 20

  /// 24 — the page margin. Nothing but a deliberate full-bleed element gets closer to
  /// the screen edge than this.
  let gutter: CGFloat = 24

  /// 32 — between the sections of a page, and above the first one.
  let section: CGFloat = 32

  /// 40 — the foot of a scrolling page, so the last line clears the tab bar.
  let page: CGFloat = 40
}
