/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SearchField.swift
//  birdspotter
//

import SwiftUI

/// The search field's own metrics. Not a token set: two values on one component, and a
/// token set of size two is ceremony.
enum SearchFieldMetrics {
  /// The row's height, held constant rather than left to its contents.
  ///
  /// A tap target rather than a gap, so it is a *size* and legitimately not on the spacing
  /// scale — and 48 rather than Apple's own 44, so one number clears every platform floor
  /// this design has to sit inside. Fixing the height also means the field does not grow the
  /// moment the clear button appears.
  static let fieldHeight: CGFloat = 48

  /// The magnifier and the clear button. Sized against the line beside them — the whole
  /// row is the target, so these do not have to be.
  static let iconSize: CGFloat = 18
}

/// A washed box to type in, with a magnifier at one end — the ruled box of a printed form.
///
/// **Deliberately not `.searchable`.** That draws into the navigation bar, which Explore hides
/// on purpose, and what the system offers is an expanding overlay rather than a line in the
/// page. Building the field out of this app's own vocabulary is what lets the design render the
/// same everywhere.
///
/// `text` plus `onTextChange` rather than a `Binding`, so the text itself stays on the
/// ViewModel. That is also what will let the glasses' speech capability drop a spoken query
/// straight in here later, with no keyboard involved.
struct SearchField: View {
  @Environment(\.theme) private var theme

  let text: String
  let onTextChange: (String) -> Void
  /// The empty-field prompt. Defaulted so Explore's call stays a two-argument one; the
  /// Journal passes "Find a sighting".
  var placeholder: String = "Find a bird"

  var body: some View {
    HStack(spacing: theme.space.snug) {
      Image(glyph: theme.glyphs.search)
        .font(.system(size: SearchFieldMetrics.iconSize))
        // Verdigris rather than faint: it is the box's one mark, and it wants to be
        // the same pigment as the wash it sits in — a gilt magnifier in a green box
        // is the field wearing two accents at once.
        .foregroundStyle(theme.colors.verdigris)

      // The placeholder is drawn rather than passed as a `prompt`, because a prompt
      // takes the system's secondary colour and would be the one piece of text on
      // this screen not coming from the palette.
      ZStack(alignment: .leading) {
        if text.isEmpty {
          Text(placeholder)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textFaint)
        }

        TextField("", text: Binding(get: { text }, set: onTextChange))
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
          .tint(theme.colors.verdigris)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .submitLabel(.search)
          .accessibilityLabel(placeholder)
      }

      if !text.isEmpty {
        Button {
          onTextChange("")
        } label: {
          Image(glyph: theme.glyphs.clearSearch)
            .font(.system(size: SearchFieldMetrics.iconSize))
            .foregroundStyle(theme.colors.textFaint)
            // The glyph is 18pt; the target is the full height of the box and
            // a `snug` either side of the mark, which is what carries it past
            // the minimum without a metric of its own.
            .frame(
              width: SearchFieldMetrics.iconSize + theme.space.snug * 2,
              height: SearchFieldMetrics.fieldHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    // `related` rather than `cardInset`: 20 is scaled for a card's block of text, and on
    // a 48pt control it pushes the magnifier conspicuously clear of the headline's left
    // edge. The trailing inset comes off when the clear button is up, because that
    // button already carries a `snug` of its own on that side.
    .padding(.leading, theme.space.related)
    .padding(.trailing, text.isEmpty ? theme.space.related : 0)
    .frame(height: SearchFieldMetrics.fieldHeight)
    // Washed rather than raised, and squared off like everything else here: a printed
    // form has a ruled box you write in, which is the same idea as `CardSurface` at a
    // lower volume — the card treatment stays reserved for the bird of the day.
    //
    // Green rather than gold — see ``BirdSpotterColors/verdigrisWash``. The wash is the
    // one thing every typing surface in the app shares, so it is the token that says
    // "this is yours to fill in", and gilt was already saying something else.
    .background(theme.colors.verdigrisWash)
    .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
        .strokeBorder(theme.colors.rule, lineWidth: 1)
    }
  }
}

// MARK: - Previews

#Preview("Empty") {
  SearchField(text: "", onTextChange: { _ in })
    .padding()
    .birdSpotterTheme()
}

#Preview("Typed") {
  SearchField(text: "warbler", onTextChange: { _ in })
    .padding()
    .birdSpotterTheme()
}
