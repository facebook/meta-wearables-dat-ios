/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  Chip.swift
//  birdspotter
//

import SwiftUI

/// Which ink a ``Chip`` is set in. Not a palette — three roles, and the caller picks by
/// meaning rather than by colour.
enum ChipTone {
  /// The default: a fact about the row, in the quiet hand.
  case neutral

  /// The app's own answer — a bird, a confidence. Gilt, as everywhere else.
  case answer

  /// Something the watcher or the device supplies — an input, a source.
  case input
}

/// A chip's own metrics.
enum ChipMetrics {
  /// Squared off like ``CardMetrics``, for the same reason: printed, not padded.
  static let cornerRadius: CGFloat = 2
}

/// A small ruled tag carrying one fact — `92%`, `2.2s`, `green-jay`.
///
/// Chips are how a summary row says several short things without becoming a sentence: the
/// Demo Director's preset page prints a row's confidence, delay and species as three of
/// these rather than one comma-spliced line.
///
/// Ruled and washed rather than filled, so a run of them reads as annotation beside the
/// row's own text rather than as a row of buttons.
struct Chip: View {
  @Environment(\.theme) private var theme

  let text: String
  var tone: ChipTone = .neutral

  var body: some View {
    Text(text)
      .font(theme.type.label)
      .foregroundStyle(ink)
      .padding(.horizontal, theme.space.snug)
      .padding(.vertical, theme.space.tight)
      .background(tone == .neutral ? Color.clear : theme.colors.giltWash)
      .clipShape(.rect(cornerRadius: ChipMetrics.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: ChipMetrics.cornerRadius)
          .strokeBorder(theme.colors.rule, lineWidth: 1)
      }
  }

  private var ink: Color {
    switch tone {
    case .neutral: theme.colors.textSecondary
    case .answer: theme.colors.gilt
    case .input: theme.colors.verdigris
    }
  }
}

#Preview {
  Chip(text: "green-jay · 92%", tone: .answer)
    .birdSpotterTheme()
}
