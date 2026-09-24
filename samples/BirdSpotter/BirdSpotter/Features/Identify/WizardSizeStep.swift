/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WizardSizeStep.swift
//  birdspotter
//

import SwiftUI

/// Station three: apparent size, on the same seven stops the catalog's
/// `Species.sizeClass` uses — four silhouettes for the anchors (sparrow, robin, crow,
/// goose) and unlabeled stops between them. The match is a window, picked ± one stop;
/// see `SpeciesStore.identifyCandidates`.
///
/// Four species rather than one shape at four scales: the labels name real birds, and an
/// anchor you have to read the label to recognise is not doing its job. The drawings stay
/// coarse — posture and bulk, no plumage — so the row still asks "how big" rather than
/// "which shape".
///
/// They are drawn *to each other*, in one shared box with a common ground line, so all
/// four render at the same frame and the scale comes out of the artwork. See
/// `BirdSpotterGlyphs`' size anchors, and `assets/glyphs/README.md` for why that box is
/// the exception to the icon grid.
struct WizardSizeStep: View {
  @Environment(\.theme) private var theme

  let sizeClass: Int?
  let onChooseSizeClass: (Int) -> Void

  /// Index = sizeClass - 1. The words the picked stop turns into.
  static let sizeClassLabels = [
    "Sparrow-sized or smaller",
    "Between a sparrow and a robin",
    "Robin-sized",
    "Between a robin and a crow",
    "Crow-sized",
    "Between a crow and a goose",
    "Goose-sized or larger",
  ]

  // The anchors' shared box, drawn 1:1. Not a spacing role, and not four heights either
  // — the birds' sizes relative to one another are already in the drawings, so this is
  // one frame that all four take.
  private static let anchorBox = CGSize(width: 64, height: 56)

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      sizeScale

      CardSurface {
        Text(sizeClass.map { Self.sizeClassLabels[$0 - 1] } ?? "Pick the closest size")
          .font(theme.type.body)
          .foregroundStyle(
            sizeClass != nil ? theme.colors.textPrimary : theme.colors.textFaint
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(theme.space.cardInset)
      }
      .padding(.top, theme.space.section)
    }
    .padding(.horizontal, theme.space.gutter)
    .padding(.top, theme.space.section)
  }

  /// The anchor drawings, smallest to largest — one per odd stop.
  private var anchorGlyphs: [String] {
    [
      theme.glyphs.sizeSparrow,
      theme.glyphs.sizeRobin,
      theme.glyphs.sizeCrow,
      theme.glyphs.sizeGoose,
    ]
  }

  /// Seven stops under four anchor glyphs; glyphs sit over stops 1, 3, 5, 7.
  private var sizeScale: some View {
    VStack(spacing: theme.space.separate) {
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(1...7, id: \.self) { stop in
          Group {
            if stop % 2 == 1 {
              Image(glyph: anchorGlyphs[stop / 2])
                .resizable()
                .scaledToFit()
                .frame(
                  width: Self.anchorBox.width,
                  height: Self.anchorBox.height
                )
                .foregroundStyle(theme.colors.ink)
                // Decorative: the stop below carries the words.
                .accessibilityHidden(true)
            } else {
              Color.clear.frame(height: 1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .bottom)
        }
      }
      HStack(spacing: 0) {
        ForEach(1...7, id: \.self) { stop in
          SizeStop(
            selected: sizeClass == stop,
            label: Self.sizeClassLabels[stop - 1],
            action: { onChooseSizeClass(stop) }
          )
          .frame(maxWidth: .infinity)
        }
      }
    }
  }
}

/// A ring, filled while chosen — radio semantics without system radio styling.
private struct SizeStop: View {
  @Environment(\.theme) private var theme

  let selected: Bool
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .stroke(theme.colors.textSecondary, lineWidth: 2)
          .frame(width: 26, height: 26)
        if selected {
          Circle()
            .fill(theme.colors.textPrimary)
            .frame(width: 16, height: 16)
        }
      }
      // The visible ring is small; the touch target is the whole 44-point stop.
      .frame(width: 44, height: 44)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}
