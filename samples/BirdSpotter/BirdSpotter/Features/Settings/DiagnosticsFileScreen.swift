/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsFileScreen.swift
//  birdspotter
//

import SwiftUI

/// One recorded run, read back — the screen somebody opens after a demo went sideways.
///
/// **Newest first, and it says so.** See ``DiagnosticsFileViewModel`` for why.
///
/// **The category chips are the point of the whole feature.** One tap on *Glasses* is the
/// answer to "was that the wearable or the phone?", which is the first question anybody
/// asks. Only the categories the file actually contains are offered.
///
/// The share button hands out the file itself rather than what is on screen: a filtered
/// view is for reading here, and a log mailed to somebody else should be the whole thing.
struct DiagnosticsFileScreen: View {
  @Environment(\.theme) private var theme
  @State private var model: DiagnosticsFileViewModel

  init(store: DiagnosticsLogStore, fileName: String) {
    _model = State(initialValue: DiagnosticsFileViewModel(store: store, fileName: fileName))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: theme.space.related) {
        filters

        if model.isLoading {
          Text("Reading…")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
        } else if model.entries.isEmpty {
          Text(
            model.allEntries.isEmpty
              ? "This run recorded nothing."
              : "Nothing in this run matches those filters."
          )
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
        } else {
          ForEach(model.entries) { entry in
            row(entry)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Run")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ShareLink(item: model.shareURL) {
        Text("Share")
          .font(theme.type.label)
      }
    }
    .task { await model.load() }
  }

  /// The two filters, and the note that the newest line is at the top.
  private var filters: some View {
    VStack(alignment: .leading, spacing: theme.space.snug) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: theme.space.snug) {
          filterChip(title: "All", isOn: model.category == nil) {
            model.setCategory(nil)
          }
          ForEach(model.availableCategories, id: \.self) { category in
            filterChip(
              title: category.displayLabel,
              isOn: model.category == category
            ) {
              model.setCategory(category)
            }
          }
        }
      }

      HStack(spacing: theme.space.snug) {
        ForEach(LogLevel.allCases, id: \.self) { level in
          filterChip(title: level.displayLabel, isOn: model.level == level) {
            model.setLevel(level)
          }
        }
      }

      Text("Newest first · \(model.entries.count) of \(model.allEntries.count) lines")
        .font(theme.type.caption)
        .foregroundStyle(theme.colors.textFaint)
    }
  }

  /// A ``Chip`` wearing a tap. The tone carries the state — `answer` is the gilt the app
  /// names things in, which is what a chosen filter is.
  private func filterChip(
    title: String,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Chip(text: title, tone: isOn ? .answer : .neutral)
    }
    .buttonStyle(.plain)
  }

  /// One line: when, how loud, from where, and what happened.
  ///
  /// The time and the category sit on their own row above the message rather than beside
  /// it — a phone is 390 points wide, and a message pushed into the remaining third wraps
  /// to four lines and stops being scannable.
  private func row(_ entry: LogEntry) -> some View {
    VStack(alignment: .leading, spacing: theme.space.tight) {
      HStack(spacing: theme.space.snug) {
        Text(model.timestamp(for: entry))
          .font(theme.type.data)
          .foregroundStyle(theme.colors.textFaint)
        Text(entry.level.displayLabel)
          .font(theme.type.label)
          .foregroundStyle(ink(for: entry.level))
        Text(entry.category.displayLabel)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
      }
      Text(entry.message)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      HairlineRule()
    }
  }

  /// **Only the two that mean something get a colour.** `vermilion` is the ink of stopping
  /// and undoing everywhere else in the app, and an error is the one line here that is
  /// that; a warning takes gilt, the app's own emphasis. Debug and info stay in the body
  /// hand, because a screen where every row is coloured is a screen with no emphasis at
  /// all — see ``BirdSpotterColors/vermilion``.
  private func ink(for level: LogLevel) -> Color {
    switch level {
    case .error: theme.colors.vermilion
    case .warning: theme.colors.gilt
    case .info, .debug: theme.colors.textSecondary
    }
  }
}

#Preview {
  NavigationStack {
    DiagnosticsFileScreen(store: DiagnosticsLogStore.open(), fileName: "preview.log")
  }
  .birdSpotterTheme()
}
