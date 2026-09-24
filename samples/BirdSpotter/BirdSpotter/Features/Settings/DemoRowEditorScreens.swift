/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoRowEditorScreens.swift
//  birdspotter
//

import SwiftUI

/// Which kind of answer a result row lands. The editor picks the *kind* first, because the
/// fields that follow depend on it — a species needs a bird and a confidence, an ambiguous
/// pair needs two birds, and no identification needs neither.
///
/// There is no "low confidence" kind: that is a species with the slider down. Nor a
/// transport failure, which is not something a script says.
nonisolated enum DemoResultKind: String, CaseIterable {
  case species = "Species"
  case ambiguous = "Ambiguous"
  case noIdentification = "No identification"

  var label: String { rawValue }
}

/// The kinds a photo row may answer with: a bird, or nothing.
///
/// A photo is one capture and one answer. "Green Jay or Blue Jay?" is an exchange, and an
/// exchange is settled by the watcher saying which — so ambiguity belongs to the lanes a
/// spoken answer can reach, not to a shutter press.
nonisolated let photoResultKinds: [DemoResultKind] = [.species, .noIdentification]

/// The kind a stored result is.
nonisolated func kindOf(_ result: DemoResult) -> DemoResultKind {
  switch result {
  case .species: .species
  case .ambiguous: .ambiguous
  case .noIdentification: .noIdentification
  }
}

/// A result of `kind`, keeping whatever the old one can still carry.
///
/// The bird survives a switch to and from "Ambiguous", so changing your mind about the shape
/// of an answer does not make the operator pick the bird again.
nonisolated func resultOf(_ kind: DemoResultKind, _ previous: DemoResult) -> DemoResult {
  let speciesId: String
  switch previous {
  case let .species(id, _): speciesId = id
  case let .ambiguous(ids): speciesId = ids.first ?? ""
  default: speciesId = ""
  }
  let confidence: Double
  switch previous {
  case let .species(_, value): confidence = value
  default: confidence = 0.87
  }

  switch kind {
  case .species:
    return .species(speciesId: speciesId, confidence: confidence)
  case .ambiguous:
    if case let .ambiguous(ids) = previous { return .ambiguous(candidateIds: ids) }
    return .ambiguous(candidateIds: speciesId.isEmpty ? [] : [speciesId])
  case .noIdentification:
    return .noIdentification
  }
}

/// True once a result has everything it needs to be saved — a bird, where one is required.
private extension DemoResult {
  var isComplete: Bool {
    switch self {
    case let .species(speciesId, _): !speciesId.isEmpty
    case let .ambiguous(candidateIds): candidateIds.filter { !$0.isEmpty }.count >= 2
    default: true
    }
  }
}

// MARK: - STT input

/// The editor for one STT-input row: the questions that match it, the answer, an optional
/// bird, and the time to compose.
struct DemoQuestionEditorScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  @State private var model: DemoDirectorViewModel
  @State private var draft: DemoQuestion
  private let isNew: Bool

  let presetId: String
  let birdCatalog: any BirdCatalogRepository

  init(
    presetId: String,
    questionId: String?,
    store: DemoSettingsStore,
    birdCatalog: any BirdCatalogRepository
  ) {
    self.presetId = presetId
    self.birdCatalog = birdCatalog
    let viewModel = DemoDirectorViewModel(store: store)
    _model = State(initialValue: viewModel)
    let existing = questionId.flatMap { id in
      viewModel.uiState.preset(presetId)?.questions.first { $0.id == id }
    }
    isNew = existing == nil
    _draft = State(
      initialValue: existing
        ?? DemoQuestion(
          id: DemoDirectorViewModel.newId(),
          prompts: [""],
          answer: "",
          speciesId: nil,
          delayMillis: 1_500
        )
    )
  }

  var body: some View {
    DemoEditorScaffold(
      title: isNew ? "New question" : "Question",
      canSave: !draft.answer.trimmingCharacters(in: .whitespaces).isEmpty
        && draft.prompts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
      onSave: {
        var saved = draft
        saved.prompts = draft.prompts
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
        model.saveQuestion(presetId, saved)
        dismiss()
      },
      onDelete: isNew
        ? nil
        : {
          model.deleteQuestion(presetId, draft.id)
          dismiss()
        }
    ) {
      // The questions come first: the row is authored the way it plays — the watcher
      // asks, then the app answers.
      DemoEditorCard(
        title: "Questions",
        subtitle: "any of these, heard in a sentence, fires this row"
      ) {
        ForEach(draft.prompts.indices, id: \.self) { index in
          HStack(spacing: theme.space.snug) {
            NotesField(
              text: draft.prompts[index],
              onTextChange: { draft.prompts[index] = $0 },
              placeholder: "green with a yellow belly",
              minLines: 1,
              maxLines: 1
            )
            Button {
              draft.prompts.remove(at: index)
            } label: {
              Image(glyph: theme.glyphs.close)
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(draft.prompts.count <= 1)
            .accessibilityLabel("Remove question")
          }
        }
        Button {
          draft.prompts.append("")
        } label: {
          Text("＋ Add question")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.gilt)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }

      DemoEditorCard(title: "Answer", subtitle: "the one line the app says or shows") {
        NotesField(
          text: draft.answer,
          onTextChange: { draft.answer = $0 },
          placeholder: "That's likely a Green Jay.",
          minLines: 1
        )
      }

      DemoSpeciesField(
        title: "Bird",
        subtitle: "optional — surfaced as a card beside the answer, with no confidence, "
          + "because the watcher supplied it. Leave it empty for a words-only reply",
        speciesId: $draft.speciesId,
        allowClear: true,
        birdCatalog: birdCatalog
      )

      DemoMillisField(
        title: "Time to compose",
        millis: $draft.delayMillis,
        range: 0...5_000,
        subtitle: "how long the app waits before answering — an instant reply reads as canned"
      )
    }
  }
}

// MARK: - Photo

/// The editor for one photo row.
///
/// There is no editor for what happens past the end of the list: that is
/// ``DemoPhotoResponse/pastTheEnd``, fixed for every preset.
struct DemoPhotoEditorScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  @State private var model: DemoDirectorViewModel
  @State private var draft: DemoPhotoResponse
  private let isNew: Bool
  /// Which capture this row answers — the whole of what a photo row is, so it is the
  /// title. A new row takes the number it will have once it is saved.
  private let photoNumber: Int

  let presetId: String
  let birdCatalog: any BirdCatalogRepository

  init(
    presetId: String,
    photoId: String?,
    store: DemoSettingsStore,
    birdCatalog: any BirdCatalogRepository
  ) {
    self.presetId = presetId
    self.birdCatalog = birdCatalog
    let viewModel = DemoDirectorViewModel(store: store)
    _model = State(initialValue: viewModel)
    let preset = viewModel.uiState.preset(presetId)
    let rows = preset?.photoResponses ?? []
    let existing = photoId.flatMap { id in rows.first { $0.id == id } }
    isNew = existing == nil
    photoNumber = (rows.firstIndex { $0.id == photoId }.map { $0 + 1 }) ?? (rows.count + 1)
    _draft = State(
      initialValue: existing
        ?? DemoPhotoResponse(
          id: DemoDirectorViewModel.newId(),
          result: .species(speciesId: "", confidence: 0.87),
          caption: "",
          spokenLine: nil,
          delayMillis: 2_200
        )
    )
  }

  var body: some View {
    DemoEditorScaffold(
      title: "Photo \(photoNumber)",
      canSave: !draft.caption.trimmingCharacters(in: .whitespaces).isEmpty
        && draft.result.isComplete,
      onSave: {
        model.savePhotoResponse(presetId, draft)
        dismiss()
      },
      onDelete: isNew
        ? nil
        : {
          model.deletePhotoResponse(presetId, draft.id)
          dismiss()
        }
    ) {
      // A photo comes back with a bird or with nothing. "Which of these two?" is an
      // exchange, and an exchange needs a spoken answer to settle it — which is the
      // ambient lane's, not a single capture's.
      DemoResultEditor(
        result: $draft.result,
        kinds: photoResultKinds,
        birdCatalog: birdCatalog
      )

      DemoEditorCard(title: "Caption", subtitle: "what appears on screen") {
        NotesField(
          text: draft.caption,
          onTextChange: { draft.caption = $0 },
          placeholder: "Northern Cardinal",
          minLines: 1
        )
      }

      DemoEditorCard(
        title: "Spoken line",
        subtitle: "said only when glasses are connected — the phone stays silent"
      ) {
        NotesField(
          text: draft.spokenLine ?? "",
          onTextChange: { draft.spokenLine = $0.isEmpty ? nil : $0 },
          placeholder: "Northern Cardinal, 92 percent.",
          minLines: 1
        )
      }

      DemoMillisField(
        title: "Response delay",
        millis: $draft.delayMillis,
        range: 0...8_000,
        // The glasses' audio route has needed about two seconds to settle before they can
        // speak — see the routing note in the design doc.
        footnote: draft.spokenLine != nil && draft.delayMillis < 2_000
          ? "Under 2s the spoken line may arrive late: the glasses' audio route takes about that long to settle."
          : nil
      )
    }
  }
}

// MARK: - Ambient input

/// The editor for one ambient-input row: the gap since the row before it, and the bird it
/// lands.
struct DemoAmbientEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model: DemoDirectorViewModel
  @State private var draft: DemoAmbientCall
  private let isNew: Bool
  private let precedingMillis: Int

  let presetId: String
  let birdCatalog: any BirdCatalogRepository

  init(
    presetId: String,
    callId: String?,
    store: DemoSettingsStore,
    birdCatalog: any BirdCatalogRepository
  ) {
    self.presetId = presetId
    self.birdCatalog = birdCatalog
    let viewModel = DemoDirectorViewModel(store: store)
    _model = State(initialValue: viewModel)
    let calls = viewModel.uiState.preset(presetId)?.ambientCalls ?? []
    let existing = callId.flatMap { id in calls.first { $0.id == id } }
    isNew = existing == nil
    let row =
      existing
      ?? DemoAmbientCall(
        id: DemoDirectorViewModel.newId(),
        afterMillis: 8_000,
        result: .species(speciesId: "", confidence: 0.87)
      )
    _draft = State(initialValue: row)
    // Where this row lands on the session clock, given the rows before it — the same
    // running total the preset page prints, so the editor and the card agree.
    precedingMillis = calls.prefix { $0.id != row.id }.reduce(0) { $0 + $1.afterMillis }
  }

  var body: some View {
    DemoEditorScaffold(
      title: isNew ? "New call" : "Ambient call",
      canSave: draft.result.isComplete,
      onSave: {
        var saved = draft
        // A row that names no bird says nothing out loud, so a line left behind by a
        // change of kind would be words that never play.
        if kindOf(saved.result) != .species { saved.spokenLine = nil }
        model.saveAmbientCall(presetId, saved)
        dismiss()
      },
      onDelete: isNew
        ? nil
        : {
          model.deleteAmbientCall(presetId, draft.id)
          dismiss()
        }
    ) {
      DemoMillisField(
        title: "Gap from the row before",
        millis: $draft.afterMillis,
        range: 0...60_000,
        footnote: "Lands at \(sessionStamp(Double(precedingMillis + draft.afterMillis) / 1000.0)) into the session. "
          + "The first row's gap is measured from the microphone opening."
      )

      DemoResultEditor(result: $draft.result, birdCatalog: birdCatalog)

      if case let .species(speciesId, confidence) = draft.result {
        DemoSpokenLineField(
          speciesId: speciesId,
          confidence: confidence,
          line: $draft.spokenLine,
          birdCatalog: birdCatalog
        )
      }
    }
  }
}

// MARK: - Shared editor pieces

/// What this row will say out loud — the composed sentence, and the field that replaces it.
///
/// **Empty is the sentence, not nothing.** An ambient row composes its line from the bird and the
/// confidence (``heardAloud(commonName:confidence:)``), and that composed line is what stands in
/// the field until somebody types over it — so the words are the placeholder rather than a rule
/// described in prose, and they re-read as the slider moves. That is where the two openings become
/// one visible thing: drag past ``sureAloudConfidence`` and *I think I heard* becomes *I just
/// heard*.
///
/// **What is typed is said verbatim**, and the footnote keeps the composed line in view beside it,
/// because the reason to write one is usually that this row wants different words from the row
/// above it — which is a comparison.
///
/// A bird the catalog cannot resolve composes nothing — the name is the catalog's to give, and a
/// sentence with a slug in the middle of it would be a preview of something that never happens.
/// The field still takes a line, because words somebody typed do not need a name resolving.
private struct DemoSpokenLineField: View {
  @Environment(\.theme) private var theme
  let speciesId: String
  let confidence: Double
  @Binding var line: String?
  let birdCatalog: any BirdCatalogRepository

  @State private var commonName: String?

  var body: some View {
    DemoEditorCard(
      title: "Spoken line",
      subtitle: "said only when there are glasses to say it into — the phone stays silent"
    ) {
      NotesField(
        text: line ?? "",
        onTextChange: { line = $0.isEmpty ? nil : $0 },
        placeholder: composed ?? "Choose a bird to hear the line.",
        minLines: 1
      )
      Text(footnote)
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: speciesId) {
      guard !speciesId.isEmpty else {
        commonName = nil
        return
      }
      commonName = (try? await birdCatalog.findById(speciesId))?.species.commonName
    }
  }

  /// The sentence this row makes for itself, or nil while there is no name to make it from.
  private var composed: String? {
    commonName.map { heardAloud(commonName: $0, confidence: Float(confidence)) }
  }

  private var footnote: String {
    guard line != nil else {
      return "Left empty, the line is composed from the bird and the confidence."
    }
    guard let composed else { return "Said as written." }
    return "Said instead of “\(composed)”"
  }
}

/// The kind picker, and whichever fields that kind needs.
private struct DemoResultEditor: View {
  @Environment(\.theme) private var theme
  @Binding var result: DemoResult
  var kinds: [DemoResultKind] = DemoResultKind.allCases
  let birdCatalog: any BirdCatalogRepository

  var body: some View {
    DemoEditorCard(title: "Result", subtitle: "what the app answers") {
      FlowingChips(kinds: kinds, current: kindOf(result)) { picked in
        result = resultOf(picked, result)
      }
    }

    switch result {
    case let .species(speciesId, confidence):
      DemoSpeciesField(
        title: "Bird",
        subtitle: "resolved against the catalog when it plays",
        speciesId: Binding(
          get: { speciesId.isEmpty ? nil : speciesId },
          set: { result = .species(speciesId: $0 ?? "", confidence: confidence) }
        ),
        allowClear: false,
        birdCatalog: birdCatalog
      )
      DemoConfidenceField(
        confidence: Binding(
          get: { confidence },
          set: { result = .species(speciesId: speciesId, confidence: $0) }
        )
      )

    case let .ambiguous(candidateIds):
      DemoSpeciesField(
        title: "First candidate",
        subtitle: "\"Green Jay or Blue Jay?\" — settled by an STT answer",
        speciesId: Binding(
          get: { candidateIds.count > 0 ? candidateIds[0] : nil },
          set: { result = .ambiguous(candidateIds: replacing(candidateIds, at: 0, with: $0)) }
        ),
        allowClear: false,
        birdCatalog: birdCatalog
      )
      DemoSpeciesField(
        title: "Second candidate",
        subtitle: "the one the watcher rules out",
        speciesId: Binding(
          get: { candidateIds.count > 1 ? candidateIds[1] : nil },
          set: { result = .ambiguous(candidateIds: replacing(candidateIds, at: 1, with: $0)) }
        ),
        allowClear: false,
        birdCatalog: birdCatalog
      )

    case .noIdentification:
      EmptyView()
    }
  }

  private func replacing(_ ids: [String], at index: Int, with value: String?) -> [String] {
    var ids = ids
    while ids.count < 2 { ids.append("") }
    ids[index] = value ?? ""
    return ids
  }
}

/// The result kinds as tappable chips, wrapped across two rows so the long labels fit.
private struct FlowingChips: View {
  @Environment(\.theme) private var theme
  let kinds: [DemoResultKind]
  let current: DemoResultKind
  let onPick: (DemoResultKind) -> Void

  var body: some View {
    FlowLayout(spacing: theme.space.snug) {
      ForEach(kinds, id: \.self) { kind in
        Button {
          onPick(kind)
        } label: {
          Chip(text: kind.label, tone: kind == current ? .answer : .neutral)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A species, picked from the catalog rather than typed.
///
/// Typing a slug is how a preset ends up naming a bird the catalog cannot resolve — which
/// plays as a silent no-op mid-demo. The picker only offers birds that exist.
private struct DemoSpeciesField: View {
  @Environment(\.theme) private var theme
  let title: String
  let subtitle: String
  @Binding var speciesId: String?
  let allowClear: Bool
  let birdCatalog: any BirdCatalogRepository

  @State private var resolved: SpeciesWithMedia?
  @State private var isPicking = false

  var body: some View {
    DemoEditorCard(title: title, subtitle: subtitle) {
      HStack(spacing: theme.space.related) {
        Text(label)
          .font(theme.type.body)
          .foregroundStyle(labelColor)
          .frame(maxWidth: .infinity, alignment: .leading)

        if allowClear, speciesId != nil {
          Button {
            speciesId = nil
          } label: {
            Image(glyph: theme.glyphs.close)
              .foregroundStyle(theme.colors.textSecondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear bird")
        }
        Image(glyph: theme.glyphs.disclosure)
          .foregroundStyle(theme.colors.textSecondary)
      }
      // The whole row opens the picker — the chevron included, and the empty space
      // beside the name. The clear button keeps its own smaller target inside it.
      .contentShape(Rectangle())
      .onTapGesture { isPicking = true }
    }
    .task(id: speciesId) {
      guard let speciesId else {
        resolved = nil
        return
      }
      resolved = try? await birdCatalog.findById(speciesId)
    }
    .sheet(isPresented: $isPicking) {
      DemoSpeciesPickerSheet(birdCatalog: birdCatalog) { picked in
        speciesId = picked
        isPicking = false
      }
    }
  }

  private var label: String {
    if let resolved { return resolved.species.commonName }
    if let speciesId { return "\(speciesId) — not in the catalog" }
    return "Choose a bird"
  }

  private var labelColor: Color {
    if speciesId != nil && resolved == nil { return .red }
    return speciesId == nil ? theme.colors.textSecondary : theme.colors.textPrimary
  }
}

/// The catalog, searchable, in a sheet — the one way a species id gets into a preset.
private struct DemoSpeciesPickerSheet: View {
  @Environment(\.theme) private var theme
  let birdCatalog: any BirdCatalogRepository
  let onPick: (String) -> Void

  @State private var query = ""
  @State private var birds: [SpeciesWithMedia] = []

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(matches) { bird in
            Button {
              onPick(bird.species.id)
            } label: {
              SpeciesRow(bird: bird)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, theme.space.gutter)
      }
      .safeAreaInset(edge: .top) {
        SearchField(text: query, onTextChange: { query = $0 })
          .padding(.horizontal, theme.space.gutter)
          .padding(.bottom, theme.space.snug)
          .background(theme.colors.paper)
      }
      .background(theme.colors.paper)
      .navigationTitle("Choose a bird")
      .navigationBarTitleDisplayMode(.inline)
    }
    .task {
      birds = ((try? await birdCatalog.browseGroups()) ?? []).flatMap(\.species)
    }
  }

  private var matches: [SpeciesWithMedia] {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return birds }
    return birds.filter { $0.species.commonName.localizedCaseInsensitiveContains(query) }
  }
}

/// A confidence, as the percentage the card will show.
private struct DemoConfidenceField: View {
  @Environment(\.theme) private var theme
  @Binding var confidence: Double

  var body: some View {
    DemoEditorCard(title: "Confidence", subtitle: "the number the card shows") {
      Text("\(Int((confidence * 100).rounded()))%")
        .font(theme.type.title)
        .foregroundStyle(theme.colors.textPrimary)
      Slider(
        value: Binding(
          get: { confidence },
          set: { confidence = ($0 * 100).rounded() / 100 }
        ),
        in: 0...1
      )
    }
  }
}

/// A duration in whole tenths of a second, stored as the ms the wire format carries.
private struct DemoMillisField: View {
  @Environment(\.theme) private var theme
  let title: String
  @Binding var millis: Int
  let range: ClosedRange<Int>
  var subtitle: String?
  var footnote: String?

  var body: some View {
    DemoEditorCard(title: title, subtitle: subtitle) {
      Text(secondsLabel(millis))
        .font(theme.type.title)
        .foregroundStyle(theme.colors.textPrimary)
      Slider(
        value: Binding(
          get: { Double(millis) },
          set: { millis = Int(($0 / 100).rounded()) * 100 }
        ),
        in: Double(range.lowerBound)...Double(range.upperBound)
      )
      if let footnote {
        Text(footnote)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
      }
    }
  }
}

private struct DemoEditorCard<Content: View>: View {
  @Environment(\.theme) private var theme
  let title: String
  let subtitle: String?
  @ViewBuilder let content: Content

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: theme.space.related) {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          PlateLabel(text: title, color: theme.colors.gilt)
          if let subtitle {
            Text(subtitle)
              .font(theme.type.label)
              .foregroundStyle(theme.colors.textSecondary)
          }
        }
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.space.cardInset)
    }
  }
}

/// The frame every row editor shares: a bar with Save, the cards, and Delete where the row
/// can be removed.
private struct DemoEditorScaffold<Content: View>: View {
  @Environment(\.theme) private var theme
  let title: String
  let canSave: Bool
  let onSave: () -> Void
  let onDelete: (() -> Void)?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.separate) {
        content

        if let onDelete {
          ActionButton(title: "Delete row", tone: .destructive, action: onDelete)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: onSave).disabled(!canSave)
      }
    }
  }
}
