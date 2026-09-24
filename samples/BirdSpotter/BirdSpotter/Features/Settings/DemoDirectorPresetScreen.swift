/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirectorPresetScreen.swift
//  birdspotter
//

import SwiftUI

/// What a row's ``DemoResult`` reads as in a card's summary.
///
/// Species print as their slugs (`american-robin`) rather than resolved names: this is a
/// developer panel, and the slug is the value actually stored — seeing it is how you catch
/// one the catalog cannot resolve.
nonisolated func resultLabel(_ result: DemoResult) -> String {
  switch result {
  case let .species(speciesId, _): speciesId
  case let .ambiguous(candidateIds): "ambiguous · \(candidateIds.joined(separator: " or "))"
  case .noIdentification: "no identification"
  }
}

/// The confidence a result carries, as a percentage chip, or nil where it carries none.
nonisolated func confidenceLabel(_ result: DemoResult) -> String? {
  switch result {
  case let .species(_, confidence): "\(Int((confidence * 100).rounded()))%"
  default: nil
  }
}

/// How an ambient row will open when it is said out loud, or nil where the row says nothing.
///
/// **The opening rather than the word "speaks".** Every heard bird speaks, so a chip saying so
/// would be a column of identical labels; what actually differs down the list is whether the app
/// sounds sure, and that is decided by a slider two screens away. Printing the first three words
/// puts the difference where it can be scanned — and the row's own editor holds the whole
/// sentence. See ``heardAloud(commonName:confidence:)``.
///
/// A row with a line of its own is read the same way, off its own words: what the chip promises is
/// the first thing the wearer hears, and a row that opens on somebody's own sentence is exactly
/// the one worth spotting from the list.
nonisolated func spokenOpeningLabel(_ call: DemoAmbientCall) -> String? {
  guard case let .species(_, confidence) = call.result else { return nil }
  guard let line = call.spokenLine else {
    return "\(SpokenCertainty.of(Float(confidence)).opening)…"
  }
  return "\(opening(of: line))…"
}

/// The first few words of a line, for a chip that has room for a few words.
///
/// Three, because that is the length of the composed openings this stands beside — a chip that
/// grew with the sentence would make one row of the list taller than the rest of it.
private nonisolated func opening(of line: String) -> String {
  line.split(separator: " ").prefix(3).joined(separator: " ")
}

/// `2200` ms as the page prints a duration: `2.2s`.
nonisolated func secondsLabel(_ millis: Int) -> String {
  let seconds = Double(millis) / 1000.0
  return seconds == seconds.rounded() ? "\(Int(seconds))s" : "\(seconds)s"
}

/// One preset's page: a card per section, each row summarised in chips, and every row a way
/// into its own editor.
///
/// The cards are the shape of the model — STT input, Photo, Ambient input — so the page
/// reads as the three lists the doc describes rather than as a form. What a row *is* stays
/// in chips (`green-jay`, `92%`, `2.2s`) so a run of rows can be scanned down a column
/// without reading sentences.
///
struct DemoDirectorPresetScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  @State private var model: DemoDirectorViewModel
  @State private var isRenaming = false
  @State private var isConfirmingDelete = false
  @State private var newName = ""

  let presetId: String

  init(presetId: String, store: DemoSettingsStore) {
    self.presetId = presetId
    _model = State(initialValue: DemoDirectorViewModel(store: store))
  }

  var body: some View {
    Group {
      if let preset = model.uiState.preset(presetId) {
        content(for: preset)
      } else {
        // Deleted out from under us (or a stale address): nothing to show, so leave.
        Color.clear.onAppear { dismiss() }
      }
    }
    .background(theme.colors.paper)
    .navigationTitle(model.uiState.preset(presetId)?.name ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { model.refresh() }
  }

  private func content(for preset: DemoPreset) -> some View {
    let totals = ambientRunningTotals(preset.ambientCalls)

    return ScrollView {
      VStack(alignment: .leading, spacing: theme.space.separate) {
        if model.uiState.armedId == presetId {
          Text("This preset is what the next session will play.")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
        }

        // MARK: STT input
        sectionCard(
          title: "STT input",
          heading: "Question From The User",
          subtitle: "matched on your words",
          isEmpty: preset.questions.isEmpty,
          emptyLabel: "No questions — spoken asks go unanswered",
          addRoute: .demoDirectorQuestion(presetId: presetId, questionId: nil)
        ) {
          ForEach(Array(preset.questions.enumerated()), id: \.element.id) { index, question in
            if index > 0 { HairlineRule() }
            rowSummary(
              headline: question.answer,
              chips: [
                question.speciesId.map { ($0, ChipTone.answer) },
                ("\(question.prompts.count) question\(question.prompts.count == 1 ? "" : "s")", .input),
                (secondsLabel(question.delayMillis), .neutral),
              ].compactMap { $0 },
              route: .demoDirectorQuestion(presetId: presetId, questionId: question.id)
            )
          }
        }

        // MARK: Photo
        sectionCard(
          title: "Photo",
          subtitle: "ordered by capture",
          isEmpty: preset.photoResponses.isEmpty,
          emptyLabel: "No rows yet",
          addRoute: .demoDirectorPhoto(presetId: presetId, photoId: nil),
          // Not a row anyone can open: what happens past the end is fixed, and
          // saying so here is the whole of what there is to know about it.
          footnote: "Once the list runs out, every further photo comes back with "
            + "no identification — however many are taken."
        ) {
          ForEach(Array(preset.photoResponses.enumerated()), id: \.element.id) { index, response in
            if index > 0 { HairlineRule() }
            rowSummary(
              headline: "\(index + 1) · \(response.caption)",
              chips: [
                (resultLabel(response.result), ChipTone.answer),
                confidenceLabel(response.result).map { ($0, ChipTone.answer) },
                response.spokenLine.map { _ in ("speaks", ChipTone.input) },
                (secondsLabel(response.delayMillis), .neutral),
              ].compactMap { $0 },
              route: .demoDirectorPhoto(presetId: presetId, photoId: response.id)
            )
          }
        }

        // MARK: Ambient input
        sectionCard(
          title: "Ambient input",
          subtitle: "fired on a clock",
          isEmpty: preset.ambientCalls.isEmpty,
          emptyLabel: "No calls — the session listens and stays quiet",
          addRoute: .demoDirectorAmbient(presetId: presetId, callId: nil)
        ) {
          ForEach(Array(preset.ambientCalls.enumerated()), id: \.element.id) { index, call in
            if index > 0 { HairlineRule() }
            rowSummary(
              headline: resultLabel(call.result),
              chips: [
                confidenceLabel(call.result).map { ($0, ChipTone.answer) },
                spokenOpeningLabel(call).map { ($0, ChipTone.input) },
                ("+\(secondsLabel(call.afterMillis))", .input),
                (sessionStamp(Double(totals[index]) / 1000.0), .neutral),
              ].compactMap { $0 },
              route: .demoDirectorAmbient(presetId: presetId, callId: call.id)
            )
          }
        }

        // The preset itself, rather than its rows. Ruled off so the foot of the page
        // is plainly about this preset and not a fourth section — the same reason the
        // Director's own escape hatch is ruled off from the list above it.
        VStack(alignment: .leading, spacing: theme.space.related) {
          HairlineRule()
          ActionButton(title: "Rename", tone: .secondary) {
            newName = preset.name
            isRenaming = true
          }
          ActionButton(title: "Delete preset", tone: .destructive) {
            isConfirmingDelete = true
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .alert("Rename preset", isPresented: $isRenaming) {
      TextField("Name", text: $newName)
      Button("Rename") {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { model.rename(presetId, to: trimmed) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Delete “\(preset.name)”?", isPresented: $isConfirmingDelete) {
      Button("Delete", role: .destructive) {
        model.delete(presetId)
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("If it is playing, nothing will be — the app stops identifying until another preset is chosen.")
    }
  }

  /// One section's card: its plate, its rows, and the one way to add another.
  ///
  /// `title` is the plate — what the section *is* in the model's words. `heading` is what
  /// the rows under it *are* in the operator's words, set larger below the plate, so a
  /// section can name its own contents ("STT input" → "Question From The User") without
  /// the plate losing the model's vocabulary.
  ///
  /// `footnote` closes the card: the behaviour the section has that no row of it can express.
  private func sectionCard<Content: View>(
    title: String,
    heading: String? = nil,
    subtitle: String,
    isEmpty: Bool,
    emptyLabel: String,
    addRoute: Route,
    footnote: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    CardSurface {
      VStack(alignment: .leading, spacing: theme.space.related) {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          PlateLabel(text: title, color: theme.colors.gilt)
          if let heading {
            Text(heading)
              .font(theme.type.title)
              .foregroundStyle(theme.colors.textPrimary)
          }
          Text(subtitle)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }

        if isEmpty {
          Text(emptyLabel)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
        } else {
          content()
        }

        NavigationLink(value: addRoute) {
          Text("＋ Add")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.gilt)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let footnote {
          HairlineRule()
          Text(footnote)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.space.cardInset)
    }
  }

  /// One row inside a card: what it says, what it carries, and the way into its editor.
  private func rowSummary(
    headline: String,
    chips: [(String, ChipTone)],
    route: Route
  ) -> some View {
    NavigationLink(value: route) {
      HStack(spacing: theme.space.related) {
        VStack(alignment: .leading, spacing: theme.space.snug) {
          Text(headline)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textPrimary)
            .multilineTextAlignment(.leading)
          // Flowing, not an HStack: four chips on a narrow phone would otherwise
          // squeeze the last one until its text set one character to a line.
          FlowLayout(spacing: theme.space.snug) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
              Chip(text: chip.0, tone: chip.1)
            }
          }
        }
        Spacer()
        Image(glyph: theme.glyphs.disclosure)
          .foregroundStyle(theme.colors.textSecondary)
      }
      .padding(.vertical, theme.space.snug)
      // Without this the gap between the text and the chevron is not hit-testable,
      // and the row only opens if you land on the ink.
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  NavigationStack {
    DemoDirectorPresetScreen(
      presetId: "starter-full-flow",
      store: DemoSettingsStore.open(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    )
  }
  .birdSpotterTheme()
}
