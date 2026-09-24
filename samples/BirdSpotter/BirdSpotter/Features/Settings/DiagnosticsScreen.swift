/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsScreen.swift
//  birdspotter
//

import SwiftUI

/// Settings → Diagnostics: how the log is set, and the runs it has recorded.
///
/// **Deliberately not called "Logs".** In this codebase logging already means the Journal —
/// logging *sightings* — and a second "Logs" in the same Settings screen is a genuine
/// ambiguity, not a pedantic one.
///
/// The controls sit above the list because they change what the next run records, and the
/// list is history. "Delete all" sits last, for the same reason emptying the Journal does on
/// the screen this is pushed from: nothing you were scrolling for should be underneath the
/// one control that throws it away.
struct DiagnosticsScreen: View {
  @Environment(\.theme) private var theme
  @State private var model: DiagnosticsViewModel
  @State private var confirmingDeleteAll = false

  init(store: DiagnosticsLogStore, settings: DiagnosticsSettingsStore, reinstall: @escaping () -> Void) {
    _model = State(
      initialValue: DiagnosticsViewModel(
        store: store,
        settings: settings,
        reinstall: reinstall
      ))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.section) {
        intro
        recordingSection
        filesSection
        if !model.files.isEmpty { deleteSection }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Diagnostics")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.refresh() }
    .alert("Delete all diagnostic logs?", isPresented: $confirmingDeleteAll) {
      Button("Delete everything", role: .destructive) {
        Task { await model.deleteAll() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Every recorded run goes, including this one. It can't be undone — share anything you still need first.")
    }
  }

  /// What this is, in the two sentences somebody reads once.
  private var intro: some View {
    Text("What the app did, run by run — the glasses, the microphones, the journal. A new file each launch; the oldest are dropped once there are \(DiagnosticsLogStore.maxFiles).")
      .font(theme.type.body)
      .foregroundStyle(theme.colors.textSecondary)
  }

  private var recordingSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Recording", color: theme.colors.gilt)

      Toggle(
        isOn: Binding(
          get: { model.isFileLoggingEnabled },
          set: { model.setFileLogging($0) }
        )
      ) {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          Text("Write to files")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Off means only Xcode's console sees these — nothing is kept on the phone.")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .tint(theme.colors.verdigris)

      levelPicker
    }
  }

  /// The floor. A menu rather than a row of four, because the closed state is itself the
  /// readout — the same reasoning as the Demo Director's armed picker.
  private var levelPicker: some View {
    Menu {
      ForEach(model.levels, id: \.self) { level in
        Button {
          model.setMinimumLevel(level)
        } label: {
          if model.minimumLevel == level {
            Label(levelDescription(level), systemImage: "checkmark")
          } else {
            Text(levelDescription(level))
          }
        }
      }
    } label: {
      CardSurface {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          PlateLabel(text: "Detail", color: theme.colors.gilt)
          HStack(spacing: theme.space.related) {
            Text(levelDescription(model.minimumLevel))
              .font(theme.type.title)
              .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Image(glyph: theme.glyphs.disclosure)
              .foregroundStyle(theme.colors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.space.cardInset)
        .contentShape(Rectangle())
      }
    }
    .buttonStyle(.plain)
  }

  private var filesSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Runs", color: theme.colors.gilt)

      if model.files.isEmpty {
        Text(
          model.isFileLoggingEnabled
            ? "Nothing recorded yet."
            : "Nothing recorded — writing to files is off."
        )
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
      }

      ForEach(model.files) { file in
        NavigationLink(value: Route.diagnosticsFile(name: file.name)) {
          DisclosureRow {
            HStack(spacing: theme.space.snug) {
              Text(model.title(for: file))
                .font(theme.type.headline)
                .foregroundStyle(theme.colors.textPrimary)
              if file.isCurrent { Chip(text: "Now", tone: .answer) }
            }
            Text(model.summary(for: file))
              .font(theme.type.label)
              .foregroundStyle(theme.colors.textSecondary)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var deleteSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      HairlineRule()
      Text("Every recorded run, including the one happening now.")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
      ActionButton(title: "Delete all logs", tone: .destructive) {
        confirmingDeleteAll = true
      }
    }
  }
}

/// What a level promises, in the reader's terms rather than the logger's — "Errors only"
/// says what you will get where "error" says what you will not.
nonisolated func levelDescription(_ level: LogLevel) -> String {
  switch level {
  case .debug: "Everything"
  case .info: "The main beats"
  case .warning: "Warnings and errors"
  case .error: "Errors only"
  }
}

#Preview {
  NavigationStack {
    DiagnosticsScreen(
      store: DiagnosticsLogStore.open(),
      settings: DiagnosticsSettingsStore.open(defaults: UserDefaults(suiteName: "preview") ?? .standard),
      reinstall: {}
    )
  }
  .birdSpotterTheme()
}
