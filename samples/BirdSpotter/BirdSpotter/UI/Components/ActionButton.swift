/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  ActionButton.swift
//  birdspotter
//

import SwiftUI

/// How much weight an ``ActionButton`` carries. Not a palette — three ranks, and the caller
/// picks by which action the screen would rather you took.
enum ActionButtonTone {
  /// The action the screen is offering. Verdigris, filled, one to a section.
  case primary

  /// Available, but not what you came for — a reset, a revert, an escape hatch. Ruled and
  /// unfilled, so it reads as the same plate with the fill taken out of it — the ink stays
  /// the primary's verdigris, because it is the same offer at a lower volume.
  case secondary

  /// The one that takes something away and does not give it back. Ruled and unfilled like
  /// ``secondary``, but inked and ruled in `vermilion`.
  ///
  /// **Unfilled deliberately.** A solid vermilion bar would be the loudest mark on the
  /// page — louder than the card it sits under, and louder than the primary action, which
  /// is not the ranking a delete deserves. The colour is doing the warning; the plate
  /// stays the shape every other action on the page has.
  case destructive
}

/// A full-width squared button — the app's one button treatment.
///
/// Cut to ``CardMetrics/cornerRadius`` and ruled like ``CardSurface``, for the same reason:
/// a pill would read as a slab of UI where this wants to read as something printed. It fills
/// the width it is given so a section's action lands as a bar rather than as a line of text
/// that happens to be tappable — which is what an accent `Text` in a stack of accent `Text`s
/// looks like, and is exactly how the Demo Director's foot became unreadable.
///
/// **The plate is verdigris, not gilt.** Gilt is the ink the app *labels* in — every eyebrow,
/// every section plate, every named bird — and a gilt bar in a page of gilt plates is one more
/// warm mark rather than the thing to press. Verdigris is already the app's colour for *this
/// commits something*: the wizard's claim and the review screen's Save both wear it, and a
/// button is the same sentence wherever it is offered.
///
/// **Primary reverses the page out of the verdigris.** The ink is `paper`, which sits at the far
/// end of the ramp from `verdigris` in both appearances — light on the day palette's deep green,
/// dark on the night palette's pale one — so one token reads correctly in both without an
/// on-verdigris colour of its own.
struct ActionButton: View {
  @Environment(\.theme) private var theme

  let title: String
  var tone: ActionButtonTone = .primary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(theme.type.headline)
        .foregroundStyle(ink)
        .padding(.vertical, theme.space.related)
        .padding(.horizontal, theme.space.cardInset)
        .frame(maxWidth: .infinity, minHeight: RowMetrics.minTapHeight)
        .background(fill)
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .strokeBorder(stroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var ink: Color {
    switch tone {
    case .primary: theme.colors.paper
    case .secondary: theme.colors.verdigris
    case .destructive: theme.colors.vermilion
    }
  }

  private var fill: Color {
    switch tone {
    case .primary: theme.colors.verdigris
    case .secondary, .destructive: .clear
    }
  }

  private var stroke: Color {
    switch tone {
    case .primary: .clear
    case .secondary: theme.colors.rule
    case .destructive: theme.colors.vermilion
    }
  }
}

#Preview {
  VStack(spacing: 16) {
    ActionButton(title: "New preset") {}
    ActionButton(title: "Reset to starter", tone: .secondary) {}
    ActionButton(title: "Delete preset", tone: .destructive) {}
  }
  .padding()
  .birdSpotterTheme()
}
