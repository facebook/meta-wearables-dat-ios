/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesDisplayScreen.swift
//  birdspotter
//

import SwiftUI

/// Display Screen — any bird's card put on the glasses' panel by hand, and held there.
///
/// Pushed from the glasses settings screen. The session opens with the screen and the guide
/// sits under a search field; tapping a row sends that bird's card up, where it stays until
/// another row replaces it, **Clear screen** takes it down, or the screen is left. See
/// ``GlassesDisplayViewModel`` for why leaving is a clear.
struct GlassesDisplayScreen: View {
  @State private var model: GlassesDisplayViewModel
  private let birdCatalog: any BirdCatalogRepository

  init(
    glassesSession: any GlassesSessionRepository,
    glassesDisplay: any GlassesDisplayRepository,
    birdCatalog: any BirdCatalogRepository,
    settings: DisplaySettingsStore = DisplaySettingsStore()
  ) {
    self.birdCatalog = birdCatalog
    _model = State(
      initialValue: GlassesDisplayViewModel(
        glassesSession: glassesSession,
        glassesDisplay: glassesDisplay,
        birdCatalog: birdCatalog,
        settings: settings
      )
    )
  }

  var body: some View {
    GlassesDisplayContent(
      uiState: model.uiState,
      birdCatalog: birdCatalog,
      onQueryChange: { model.search($0) },
      onShow: { model.show($0) },
      onClearScreen: { model.clearScreen() },
      onPickCustomBird: { model.pickCustomBird($0) },
      onCustomMessageChange: { model.editCustomMessage($0) },
      onShowCustom: { model.showCustom() },
      onRetry: { model.start() }
    )
    .task {
      model.start()
      await model.load()
    }
    // The run is the screen's, not the navigation stack's: walking away hangs up — and
    // takes the card down with it — the same lease every other glasses session in the
    // app is held on.
    .onDisappear { model.stop() }
  }
}

/// The drawing, taking a reading rather than a repository for everything it shows — the
/// catalog rides along only so the custom card's picker sheet can offer the guide.
private struct GlassesDisplayContent: View {
  @Environment(\.theme) private var theme

  let uiState: GlassesDisplayUiState
  let birdCatalog: any BirdCatalogRepository
  let onQueryChange: (String) -> Void
  let onShow: (SpeciesWithMedia) -> Void
  let onClearScreen: () -> Void
  let onPickCustomBird: (SpeciesWithMedia) -> Void
  let onCustomMessageChange: (String) -> Void
  let onShowCustom: () -> Void
  let onRetry: () -> Void

  var body: some View {
    ScrollView {
      // A lazy stack rather than a plain one: the guide's rows decode a thumbnail
      // each, and only the ones about to be seen should pay for it. Per-child padding
      // and no `spacing:`, deliberately — the rhythm down this page is not uniform,
      // and setting both would add the two together.
      LazyVStack(alignment: .leading, spacing: 0) {
        sessionSection

        onTheGlassesSection
          .padding(.top, theme.space.section)

        CustomCardSection(
          customBird: uiState.customBird,
          customMessage: uiState.customMessage,
          birdCatalog: birdCatalog,
          onPickBird: onPickCustomBird,
          onMessageChange: onCustomMessageChange,
          onShowCustom: onShowCustom
        )
        .padding(.top, theme.space.section)

        SearchField(text: uiState.query, onTextChange: onQueryChange)
          .padding(.top, theme.space.section)
          .padding(.bottom, theme.space.related)

        if uiState.birds.isEmpty && !trimmedQuery.isEmpty {
          Text("Nothing in the guide matches “\(trimmedQuery)”.")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.space.related)
        }

        ForEach(uiState.birds) { bird in
          Button {
            onShow(bird)
          } label: {
            SpeciesRow(bird: bird)
          }
          .buttonStyle(.plain)
          HairlineRule()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.separate)
      .padding(.bottom, theme.space.page)
    }
    .background(theme.colors.paper)
    .navigationTitle("Display Screen")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var trimmedQuery: String {
    uiState.query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Where the session stands, and whether these glasses can draw at all — the one
  /// reading that decides whether a tap below means anything.
  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Session", color: theme.colors.gilt)

      readingRow(label: "Glasses", value: sessionValue)
      readingRow(label: "Display", value: displayValue, support: displaySupport)

      if let failure = uiState.failure {
        // In the page's own ink rather than a red: the palette spends its one red
        // on controls that end something, and a line explaining why the session
        // ended is a statement, not a control.
        Text(failure)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
      }

      if !uiState.isRunning {
        ActionButton(title: "Reconnect", action: onRetry)
      }
    }
  }

  /// What the panel is carrying right now, and the way to take it down. The one
  /// destructive control on the screen — it ends what the wearer is looking at.
  private var onTheGlassesSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "On the glasses", color: theme.colors.gilt)

      Text(
        uiState.shownBird?.species.commonName
          ?? "Nothing yet — tap a bird below and its card goes up."
      )
      .font(theme.type.body)
      .foregroundStyle(theme.colors.textSecondary)

      if uiState.shownBird != nil {
        ActionButton(title: "Clear screen", tone: .destructive, action: onClearScreen)
      }
    }
  }

  /// What the session is doing, in the words the pill on the realtime screen uses — one
  /// vocabulary for the link across the app, so a reading here is comparable with a
  /// reading there.
  private var sessionValue: String {
    switch uiState.sessionState {
    case .starting: "Connecting"
    case .started: "Connected"
    case .paused: "Paused"
    case .stopping: "Stopping"
    case .stopped: "Stopped"
    case nil: uiState.isRunning ? "Connecting" : "Not started"
    }
  }

  private var displayValue: String {
    switch uiState.hasDisplay {
    case .some(true): "Ready"
    case .some(false): "None on this pair"
    case .none: "—"
    }
  }

  /// Only the reading that changes what a tap does explains itself: a pair with no panel
  /// takes every card quietly and shows none of them, which is otherwise
  /// indistinguishable from it working.
  private var displaySupport: String? {
    switch uiState.hasDisplay {
    case .some(false): "These glasses have no panel, so a card sent here lands nowhere"
    case .some(true), .none: nil
    }
  }

  private func readingRow(label: String, value: String, support: String? = nil) -> some View {
    HStack(spacing: theme.space.related) {
      VStack(alignment: .leading) {
        Text(label)
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
        if let support {
          Text(support)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      Spacer()
      Text(value)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }
}

/// The custom card: a chosen bird's gallery with the presenter's own line under the
/// photographs, in place of the catalog's description.
///
/// The bird is picked from a sheet rather than the list below, because the list's tap
/// already means *send this now* — a setup control and a trigger wearing the same gesture
/// would put a card up mid-sentence. The button appears only once there is a bird and a
/// line to send; see ``GlassesDisplayViewModel/customCardReady(bird:message:)``.
private struct CustomCardSection: View {
  @Environment(\.theme) private var theme

  let customBird: SpeciesWithMedia?
  let customMessage: String
  let birdCatalog: any BirdCatalogRepository
  let onPickBird: (SpeciesWithMedia) -> Void
  let onMessageChange: (String) -> Void
  let onShowCustom: () -> Void

  @State private var isPicking = false

  var body: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Custom card", color: theme.colors.gilt)

      Text(
        "The bird's card with your own line under the photos, in place of the "
          + "guide's description. Remembered until you change it."
      )
      .font(theme.type.label)
      .foregroundStyle(theme.colors.textSecondary)

      HStack(spacing: theme.space.related) {
        Text(customBird?.species.commonName ?? "Choose a bird")
          .font(theme.type.body)
          .foregroundStyle(
            customBird == nil ? theme.colors.textSecondary : theme.colors.textPrimary
          )
          .frame(maxWidth: .infinity, alignment: .leading)

        Image(glyph: theme.glyphs.disclosure)
          .foregroundStyle(theme.colors.textSecondary)
      }
      // The whole row opens the picker — the chevron included, and the empty space
      // beside the name.
      .contentShape(Rectangle())
      .onTapGesture { isPicking = true }

      NotesField(
        text: customMessage,
        onTextChange: onMessageChange,
        placeholder: "The line to show under the photos"
      )

      if GlassesDisplayViewModel.customCardReady(bird: customBird, message: customMessage) {
        ActionButton(title: "Show custom card", action: onShowCustom)
      }
    }
    .sheet(isPresented: $isPicking) {
      CustomBirdPickerSheet(birdCatalog: birdCatalog) { bird in
        onPickBird(bird)
        isPicking = false
      }
    }
  }
}

/// The catalog, searchable, in a sheet — the way the custom card's bird is chosen. Matching
/// goes through ``GlassesDisplayViewModel/birdsFor(_:in:)``, so this field and the one on
/// the screen under it find the same birds by the same letters.
private struct CustomBirdPickerSheet: View {
  @Environment(\.theme) private var theme
  let birdCatalog: any BirdCatalogRepository
  let onPick: (SpeciesWithMedia) -> Void

  @State private var query = ""
  @State private var groups: [SpeciesGroup] = []

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(matches) { bird in
            Button {
              onPick(bird)
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
      groups = (try? await birdCatalog.browseGroups()) ?? []
    }
  }

  private var matches: [SpeciesWithMedia] {
    GlassesDisplayViewModel.birdsFor(query, in: groups)
  }
}

/// Mid-rehearsal: connected, a card up, the custom card set, and the guide ready for the
/// next one.
#Preview("Connected") {
  NavigationStack {
    GlassesDisplayContent(
      uiState: GlassesDisplayUiState(
        isRunning: true,
        sessionState: .started,
        hasDisplay: true,
        birds: GlassesDisplayViewModel.birdsFor("", in: PreviewCatalog.guide),
        shownBird: PreviewCatalog.blueJay,
        customBird: PreviewCatalog.blueJay,
        customMessage: "Our loudest regular — listen for the pump-handle call."
      ),
      birdCatalog: PreviewBirdCatalog(),
      onQueryChange: { _ in },
      onShow: { _ in },
      onClearScreen: {},
      onPickCustomBird: { _ in },
      onCustomMessageChange: { _ in },
      onShowCustom: {},
      onRetry: {}
    )
  }
  .birdSpotterTheme()
}

/// The reading that matters: a pair with nothing to draw on, saying so before a tap.
#Preview("No display") {
  NavigationStack {
    GlassesDisplayContent(
      uiState: GlassesDisplayUiState(
        isRunning: true,
        sessionState: .started,
        hasDisplay: false,
        birds: GlassesDisplayViewModel.birdsFor("", in: PreviewCatalog.guide)
      ),
      birdCatalog: PreviewBirdCatalog(),
      onQueryChange: { _ in },
      onShow: { _ in },
      onClearScreen: {},
      onPickCustomBird: { _ in },
      onCustomMessageChange: { _ in },
      onShowCustom: {},
      onRetry: {}
    )
  }
  .birdSpotterTheme()
}
