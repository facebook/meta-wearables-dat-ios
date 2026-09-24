/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WizardBehaviorStep.swift
//  birdspotter
//

import SwiftUI

/// Station five: what the bird was doing, one answer. The six contexts mirror
/// ``BirdBehavior`` one to one — the row order here is the enum's order, so the list and
/// the schema can never disagree about what the choices are.
struct WizardBehaviorStep: View {
  @Environment(\.theme) private var theme

  let behavior: BirdBehavior?
  let onChooseBehavior: (BirdBehavior) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(BirdBehavior.allCases, id: \.self) { candidate in
        BehaviorRow(
          label: candidate.label,
          selected: candidate == behavior,
          action: { onChooseBehavior(candidate) }
        )
        HairlineRule()
      }
    }
    .padding(.horizontal, theme.space.gutter)
  }
}

private struct BehaviorRow: View {
  @Environment(\.theme) private var theme

  let label: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: theme.space.separate) {
        Text(label)
          .font(selected ? theme.type.headline : theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
        Spacer()
        if selected {
          Image(glyph: theme.glyphs.selected)
            .foregroundStyle(theme.colors.verdigris)
        }
      }
      .padding(.vertical, theme.space.separate)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

extension BirdBehavior {
  var label: String {
    switch self {
    case .atFeeder: "Eating at a feeder"
    case .swimmingOrWading: "Swimming or wading"
    case .onGround: "On the ground"
    case .inTreesOrBushes: "In trees or bushes"
    case .onFenceOrWire: "On a fence or wire"
    case .soaringOrFlying: "Soaring or flying"
    }
  }
}
