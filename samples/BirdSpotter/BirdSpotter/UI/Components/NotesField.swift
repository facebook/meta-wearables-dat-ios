/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  NotesField.swift
//  birdspotter
//

import SwiftUI

/// How tall the box stands before anything is typed in it, and how far it will grow — the
/// numbers the notes on the review screen want, and the defaults every other caller inherits.
///
/// Two rows empty, because one row reads as a search box — that one is asking for a sentence,
/// and the shape should say so before a word is in it. Four is where it stops growing and starts
/// scrolling: past that it is eating the timeline above it, which is the thing the notes are
/// about.
///
/// A field asking for a name or a line takes `minLines: 1` and stays a line; nothing else about
/// it changes, which is the point.
enum NotesFieldMetrics {
  static let minLines = 2
  static let maxLines = 4
}

/// A washed box to write in — ``SearchField``'s box, given height.
///
/// The two are deliberately the same object at different sizes: one ruled `verdigrisWash`
/// rectangle is what typing into this app looks like, whether the thing being typed is a species, a
/// morning, or a line the Demo Director will say back. What changes here is that the text starts
/// at the top rather than centring, because it is going to grow downwards.
///
/// **Every field in the app that is not the search box is this one.** The line-limit arguments
/// are the only thing a caller varies — a name is `1...1`, a spoken line is `1...4`, the notes
/// are the defaults. A form whose boxes are drawn by three different systems is how the Demo
/// Director's editors came to look like a settings screen from another app.
///
/// **This replaced `.textFieldStyle(.roundedBorder)`, and that was the whole reason it exists.**
/// The rounded-border field is drawn by the system in the system's greys, against the system's
/// idea of light and dark — on the review screen, which forces the dark palette whatever the
/// phone is set to, it came out as a pale slab in the middle of the cabinet. A field that has
/// to know what palette it is standing in cannot be a system field.
///
/// `text` plus `onTextChange` rather than a `Binding`, matching ``SearchField``.
struct NotesField: View {
  @Environment(\.theme) private var theme

  let text: String
  let onTextChange: (String) -> Void
  let placeholder: String
  /// False while the outing is being written, and once it has been: the notes are part of
  /// what was saved, and a field still taking keystrokes would be promising otherwise.
  var isEnabled: Bool = true
  /// How tall the box stands empty, and where it stops growing. Defaulted to the notes'
  /// own two-to-four; a one-line field passes `1` to both.
  var minLines: Int = NotesFieldMetrics.minLines
  var maxLines: Int = NotesFieldMetrics.maxLines

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Drawn rather than passed as a `prompt`, for the reason ``SearchField`` gives:
      // a prompt takes the system's secondary colour, which is the one piece of text
      // on the screen that would not be coming from the palette.
      if text.isEmpty {
        Text(placeholder)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textFaint)
      }

      field
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
        .tint(theme.colors.verdigris)
        .disabled(!isEnabled)
        .accessibilityLabel(placeholder)
    }
    // `related` on every side rather than the search box's leading-only inset: this one
    // holds a block of text instead of a line, so the ink wants clearing from the rule
    // above and below it as much as from the side.
    .padding(theme.space.related)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.verdigrisWash)
    .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
        .strokeBorder(theme.colors.rule, lineWidth: 1)
    }
  }

  /// A one-line box is a horizontal field, so Return submits rather than typing a newline
  /// into a box that cannot show it — the reason the two are branched rather than clamped
  /// to `1...1`.
  @ViewBuilder private var field: some View {
    let binding = Binding(get: { text }, set: onTextChange)

    if maxLines == 1 {
      TextField("", text: binding)
    } else {
      TextField("", text: binding, axis: .vertical)
        .lineLimit(minLines...maxLines)
    }
  }
}

// MARK: - Previews

#Preview("Empty") {
  NotesField(
    text: "",
    onTextChange: { _ in },
    placeholder: "Notes — what the morning was like"
  )
  .padding()
  .birdSpotterTheme()
}

#Preview("Written in") {
  NotesField(
    text: "Cold, still, and the creek was loud. Three of us out before the light.",
    onTextChange: { _ in },
    placeholder: "Notes — what the morning was like"
  )
  .padding()
  .birdSpotterTheme()
}
