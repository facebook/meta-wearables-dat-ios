/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CardSurface.swift
//  birdspotter
//

import SwiftUI

/// The card's own metrics. Not a token set: one value on one component, and a token set of
/// size one is ceremony.
enum CardMetrics {
  /// Barely rounded. A printed plate has a corner, not a pill.
  static let cornerRadius: CGFloat = 3
}

/// Raised paper inside a hairline rule — the one card treatment this app has.
///
/// Squared off rather than rounded, and ruled rather than shadowed: a floating card would
/// read as a slab of UI, where this wants to read as something printed.
struct CardSurface<Content: View>: View {
  @Environment(\.theme) private var theme

  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(theme.colors.paperRaised)
      .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
          .strokeBorder(theme.colors.rule, lineWidth: 1)
      }
  }
}

/// A one-point divider in the rule colour.
struct HairlineRule: View {
  @Environment(\.theme) private var theme

  var body: some View {
    Rectangle()
      .fill(theme.colors.rule)
      .frame(height: 1)
  }
}

/// The small letterspaced caps that head a section — "ABOUT", "HABITAT", "BIRD OF THE DAY".
///
/// Wraps the three modifiers `plate` always needs, since Cinzel is uppercase-only and unreadable
/// without the tracking.
struct PlateLabel: View {
  @Environment(\.theme) private var theme

  let text: String
  var color: Color?

  /// How many lines the plate may take. `nil` — the default — is as many as it needs, which is
  /// right for the ones that stand alone and read as a sentence in caps.
  ///
  /// **A plate that shares a row with anything wants `1`.** Set in caps at this tracking, a
  /// broken word does not read as a wrapped label; it reads as a rendering fault — `LINKIN` over
  /// a lone `G` is what the session's source switch was doing the moment its dots arrived and
  /// took the width the word was using.
  var lineLimit: Int?

  var body: some View {
    Text(text)
      .font(theme.type.plate)
      .tracking(2.2)
      .textCase(.uppercase)
      .lineLimit(lineLimit)
      .foregroundStyle(color ?? theme.colors.textFaint)
  }
}
