/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WizardColorsStep.swift
//  birdspotter
//

import SwiftUI

/// Station four: main colors, up to three. Every pick must be on the bird — the query's
/// all-of rule, which is why more picks mean a shorter list (see
/// `SpeciesStore.identifyCandidates`).
struct WizardColorsStep: View {
  @Environment(\.theme) private var theme

  let colors: Set<PlumageColor>
  let onToggleColor: (PlumageColor) -> Void

  /// Three fixed rows of three, not an adaptive grid: nine swatches is a constant of
  /// the palette, and a grid that can never reflow has nothing to compute.
  private static let rows: [[PlumageColor]] = [
    [.black, .gray, .white],
    [.brown, .red, .orange],
    [.yellow, .green, .blue],
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Pick up to three.")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)

      VStack(spacing: theme.space.gutter) {
        ForEach(Self.rows, id: \.self) { row in
          HStack(spacing: theme.space.separate) {
            ForEach(row, id: \.self) { color in
              ColorSwatch(
                color: color,
                selected: colors.contains(color),
                action: { onToggleColor(color) }
              )
              .frame(maxWidth: .infinity)
            }
          }
        }
      }
      .padding(.top, theme.space.section)
    }
    .padding(.horizontal, theme.space.gutter)
  }
}

/// A filled disc with its name under it; a check badges the chosen ones.
private struct ColorSwatch: View {
  @Environment(\.theme) private var theme

  let color: PlumageColor
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: theme.space.snug) {
        ZStack {
          Circle()
            .fill(color.swatch)
            .frame(width: 52, height: 52)
          // Every disc carries the hairline so the white swatch has an edge;
          // the chosen ones trade it for a heavier ring in the page's own ink.
          Circle()
            .stroke(
              selected ? theme.colors.textPrimary : theme.colors.rule,
              lineWidth: selected ? 2 : 1
            )
            .frame(width: 52, height: 52)
          if selected {
            Image(glyph: theme.glyphs.selected)
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(color.checkTint)
          }
        }
        Text(color.label)
          .font(theme.type.caption)
          .foregroundStyle(theme.colors.textSecondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(color.label)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

extension PlumageColor {
  var label: String {
    switch self {
    case .black: "Black"
    case .gray: "Gray"
    case .white: "White"
    case .brown: "Brown"
    case .red: "Red"
    case .orange: "Orange"
    case .yellow: "Yellow"
    case .green: "Green"
    case .blue: "Blue"
    }
  }

  /// Feather colors, not brand colors — muted toward what plumage actually looks like,
  /// and the same hex values on both platforms. Data visualization, not theme, which is
  /// why they live beside the step that draws them rather than in `BirdSpotterColors`.
  var swatch: Color {
    switch self {
    case .black: Color(hex: 0x23282A)
    case .gray: Color(hex: 0x97A0A2)
    case .white: Color(hex: 0xF4F2EA)
    case .brown: Color(hex: 0x77502E)
    case .red: Color(hex: 0xB13A2C)
    case .orange: Color(hex: 0xD07A2C)
    case .yellow: Color(hex: 0xE0B33C)
    case .green: Color(hex: 0x5B7147)
    case .blue: Color(hex: 0x48708F)
    }
  }

  /// Ink on the light swatches, paper on the dark — the check has to survive its disc.
  var checkTint: Color {
    switch self {
    case .white, .yellow, .gray: Color(hex: 0x10171A)
    default: Color(hex: 0xF3F5F0)
    }
  }
}
