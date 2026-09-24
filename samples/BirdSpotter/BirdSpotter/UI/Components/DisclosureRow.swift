/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DisclosureRow.swift
//  birdspotter
//

import SwiftUI

/// A row's own metrics.
enum RowMetrics {
  /// The floor a row's tappable box is held to, whatever its ink measures.
  ///
  /// Not a spacing value and deliberately not on the scale: this is the size of a fingertip,
  /// which is a fact about hands rather than a decision about rhythm. 48 rather than the
  /// 44 the platform floor asks for, so every screen lays out to one number.
  static let minTapHeight: CGFloat = 48
}

/// A row that opens something: its content on the left, the disclosure caret on the right,
/// and — the whole reason it exists — **the entire width tappable**.
///
/// SwiftUI hit-tests the ink, not the frame. A row built as `HStack { text; Spacer(); caret }`
/// therefore has a hole in the middle of it: the gap beside the text swallows taps, and the
/// row only opens if you land on the words or on the caret itself. `contentShape` is what
/// closes that hole, and putting it here means no screen has to remember it.
///
/// A drawing, not a button — the same split ``CardSurface`` has. It is wrapped in a
/// `NavigationLink`, which is where the destination and the tap both come from.
struct DisclosureRow<Content: View>: View {
  @Environment(\.theme) private var theme

  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: theme.space.related) {
      VStack(alignment: .leading, spacing: theme.space.tight) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(glyph: theme.glyphs.disclosure)
        .foregroundStyle(theme.colors.textSecondary)
    }
    // A floor on the box, deliberately *not* padding: padding here would add to the
    // spacing its stack already sets and put a gap between two rows that neither of
    // them wrote down. The ink centres in whatever height this leaves.
    .frame(minHeight: RowMetrics.minTapHeight)
    .contentShape(Rectangle())
  }
}

#Preview {
  /// A wrapper, so the sample rows can set their ink from the theme the way a screen does.
  struct PreviewRows: View {
    @Environment(\.theme) private var theme

    var body: some View {
      VStack(alignment: .leading, spacing: theme.space.separate) {
        DisclosureRow {
          Text("Meta AI Glasses")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Status and connection")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
        HairlineRule()
        DisclosureRow {
          Text("Demo Director")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
        }
      }
      .padding(theme.space.gutter)
    }
  }

  return PreviewRows().birdSpotterTheme()
}
