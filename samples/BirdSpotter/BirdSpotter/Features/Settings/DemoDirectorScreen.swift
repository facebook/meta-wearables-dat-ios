/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirectorScreen.swift
//  birdspotter
//

import SwiftUI

/// What a picker row says a preset holds, at a glance: `1 question · 1 photo · 1 call`.
nonisolated func presetSummary(_ preset: DemoPreset) -> String {
  func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
  return [
    count(preset.questions.count, "question"),
    count(preset.photoResponses.count, "photo"),
    count(preset.ambientCalls.count, "call"),
  ].joined(separator: " · ")
}

/// Settings → Demo Director: which preset is playing, and the presets to edit.
///
/// **Arming is a dropdown, not a row's tap.** What plays is one decision — the presenter's
/// ninety-seconds-before-stage decision — and it belongs in one control at the top rather
/// than distributed across a list where selecting and opening compete for the same tap.
/// The rows below are for editing; opening one never changes what plays.
///
/// `None` is an option in that menu, and deleting the armed preset falls back to it: the
/// app then never identifies, which is a deliberate state rather than a broken one.
///
struct DemoDirectorScreen: View {
  @Environment(\.theme) private var theme
  @State private var model: DemoDirectorViewModel

  /// Held so the page for a just-created preset can be pushed with the same store the
  /// list is reading — see `newPresetId`.
  private let store: DemoSettingsStore

  init(store: DemoSettingsStore) {
    self.store = store
    _model = State(initialValue: DemoDirectorViewModel(store: store))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.separate) {
        // The honesty affordance: this panel is for the team, not hidden from it.
        Text("Everything a session identifies is scripted here. One preset plays at a time; None means the app never identifies.")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)

        armedPicker

        PlateLabel(text: "Presets", color: theme.colors.gilt)

        ForEach(model.uiState.presets) { preset in
          NavigationLink(value: Route.demoDirectorPreset(presetId: preset.id)) {
            presetRow(preset)
          }
          .buttonStyle(.plain)
        }

        if model.uiState.presets.isEmpty {
          Text("No presets. Add one, or put the shipped script back.")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
        }

        ActionButton(title: "New preset") {
          // Created here so the new preset's page is what opens.
          newPresetId = model.newPreset()
        }

        // Only once the shipped script is gone — edited or deleted. There is
        // nothing to reset while it is still sitting in the list untouched.
        //
        // Ruled off, and its own caption first: this is the page's escape hatch
        // rather than another item in the list above it, and running it straight on
        // from "New preset" in one rhythm of gilt lines is what made the foot of
        // this screen unreadable.
        if model.uiState.canResetToShipped {
          VStack(alignment: .leading, spacing: theme.space.related) {
            HairlineRule()
            Text("Puts the shipped script back. It does not change what is playing.")
              .font(theme.type.label)
              .foregroundStyle(theme.colors.textSecondary)
            ActionButton(title: "Reset to starter", tone: .secondary) {
              model.resetToShipped()
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Demo Director")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $newPresetId) { id in
      DemoDirectorPresetScreen(presetId: id, store: store)
    }
    // Editing happens on pages pushed from here, through their own state holders;
    // re-read on the way back so the list never shows the snapshot from before.
    .onAppear { model.refresh() }
  }

  /// Set by "New preset" so the freshly created page opens straight away.
  @State private var newPresetId: String?

  /// The one control that decides what plays: a menu listing every preset plus None.
  ///
  /// A menu rather than a row of choices because the answer is single-valued and the
  /// list grows — and because the closed state is itself the readout, so a presenter can
  /// see what is armed without opening anything.
  private var armedPicker: some View {
    Menu {
      ForEach(model.uiState.presets) { preset in
        Button {
          model.arm(preset.id)
        } label: {
          if model.uiState.armedId == preset.id {
            Label(preset.name, systemImage: "checkmark")
          } else {
            Text(preset.name)
          }
        }
      }
      Button {
        model.arm(nil)
      } label: {
        if model.uiState.armedId == nil {
          Label("None — never identify", systemImage: "checkmark")
        } else {
          Text("None — never identify")
        }
      }
    } label: {
      CardSurface {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          PlateLabel(text: "Playing", color: theme.colors.gilt)
          HStack(spacing: theme.space.related) {
            Text(model.uiState.armedName)
              .font(theme.type.title)
              .foregroundStyle(
                model.uiState.armedId == nil
                  ? theme.colors.textSecondary
                  : theme.colors.textPrimary
              )
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

  /// One preset in the list: what it holds, and the way into editing it.
  ///
  /// The whole row opens the preset — the gap beside the caret included; see
  /// ``DisclosureRow``.
  private func presetRow(_ preset: DemoPreset) -> some View {
    DisclosureRow {
      HStack(spacing: theme.space.snug) {
        Text(preset.name)
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
        if model.uiState.armedId == preset.id {
          Chip(text: "Playing", tone: .answer)
        }
      }
      Text(presetSummary(preset))
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }
}

#Preview {
  NavigationStack {
    DemoDirectorScreen(store: DemoSettingsStore.open(defaults: UserDefaults(suiteName: "preview") ?? .standard))
  }
  .birdSpotterTheme()
}
