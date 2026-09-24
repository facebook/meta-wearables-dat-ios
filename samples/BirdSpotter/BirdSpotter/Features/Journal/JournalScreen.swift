/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalScreen.swift
//  birdspotter
//

import SwiftUI

/// Journal tab — the field notes: every outing saved, searchable, newest first, under a
/// heading per month.
///
/// Built to the same page recipe as `ExploreScreen` — a chrome-less page that opens with the
/// page, a search field that replaces everything below it, ruled rows on the paper — so the
/// two tabs read as one app. Split into a stateful `JournalScreen` that owns the view model
/// and a stateless ``JournalContentView`` that draws it, which is what lets the Previews below
/// render every state without a database.
///
/// No `NavigationStack` of its own: the tab's stack is owned by `ContentView`, which is what
/// lets a row push `Route.outingDetail` and the header push `Route.settings` without this
/// screen knowing how either is built.
struct JournalScreen: View {
  @State private var model: JournalViewModel

  /// Resolves captured photos for the rows. Held here, not on the view model, because it is
  /// a UI concern — the model deals in `JournalEntry`, not in files.
  private let mediaFileStore: MediaFileStore?

  init(
    journal: any JournalRepository,
    birdCatalog: any BirdCatalogRepository,
    mediaFileStore: MediaFileStore?
  ) {
    _model = State(initialValue: JournalViewModel(journal: journal, birdCatalog: birdCatalog))
    self.mediaFileStore = mediaFileStore
  }

  var body: some View {
    JournalContentView(
      uiState: model.uiState,
      query: model.query,
      mediaFileStore: mediaFileStore,
      onSearch: { model.search($0) }
    )
    // Starts both streams when the Journal appears and cancels them when it leaves.
    .task { await model.observe() }
  }
}

/// The Journal's layout, given already-computed state. Everything the screen draws lives here
/// so a Preview can hand it a `JournalUiState` directly.
private struct JournalContentView: View {
  @Environment(\.theme) private var theme

  let uiState: JournalUiState
  let query: String
  let mediaFileStore: MediaFileStore?
  let onSearch: (String) -> Void

  var body: some View {
    ScrollView {
      // Per-child padding with `spacing: 0`, deliberately: the rhythm down this page is
      // not uniform — a section gap above each month heading, none between the ruled rows
      // — and setting both would add the two together.
      LazyVStack(alignment: .leading, spacing: 0) {
        header

        SearchField(text: query, onTextChange: onSearch, placeholder: "Find a sighting")
          .padding(.top, theme.space.separate)

        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.page)
    }
    .background(theme.colors.paper)
    // The screen writes its own header, so the system bar would only repeat it.
    .toolbar(.hidden, for: .navigationBar)
  }

  /// Eyebrow, headline and the life-list stat, with Settings to the right — the page's own
  /// bar, since it draws no system one and Settings has to live somewhere.
  private var header: some View {
    HStack(alignment: .top, spacing: theme.space.separate) {
      VStack(alignment: .leading, spacing: theme.space.related) {
        PlateLabel(text: "The Journal", color: theme.colors.gilt)

        Text("Field notes.")
          .font(theme.type.display)
          .foregroundStyle(theme.colors.textPrimary)

        if let lifeList = lifeListStat {
          PlateLabel(text: lifeList, color: theme.colors.verdigris)
        }
      }

      Spacer(minLength: 0)

      NavigationLink(value: Route.settings) {
        Image(glyph: theme.glyphs.settings)
          .font(.system(size: 20))
          .foregroundStyle(theme.colors.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Settings")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch uiState {
    case .loading:
      JournalLoading()
        .padding(.top, theme.space.section)
    case .empty:
      JournalEmpty()
        .padding(.top, theme.space.section)
    case .ready(_, let months):
      monthSections(months)
    case .searching(_, let results):
      searchResults(results)
    }
  }

  /// The Journal proper: a month heading, then its entries as ruled rows — the same shape
  /// Explore's guide sections take, so the two lists rhyme.
  @ViewBuilder
  private func monthSections(_ months: [JournalMonth]) -> some View {
    ForEach(months) { month in
      PlateLabel(text: month.title, color: theme.colors.gilt)
        .padding(.top, theme.space.section)
        .padding(.bottom, theme.space.related)

      ForEach(month.entries) { entry in
        NavigationLink(value: Route.outingDetail(outingId: entry.id)) {
          JournalRow(entry: entry, mediaFileStore: mediaFileStore)
        }
        .buttonStyle(.plain)

        HairlineRule()
      }
    }
  }

  /// A query's matches: a count where a month heading would go, then the same ruled rows —
  /// flat, no month headings, matching Explore's search results.
  @ViewBuilder
  private func searchResults(_ results: [JournalEntry]) -> some View {
    PlateLabel(text: JournalViewModel.resultsLabel(count: results.count), color: theme.colors.gilt)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.related)

    if results.isEmpty {
      // Plain text on the paper rather than a card: it comes and goes between keystrokes,
      // and a card flashing in and out reads as a fault — the same call Explore makes.
      Text("Nothing in your journal matches “\(query)”.")
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
    } else {
      ForEach(results) { entry in
        NavigationLink(value: Route.outingDetail(outingId: entry.id)) {
          JournalRow(entry: entry, mediaFileStore: mediaFileStore)
        }
        .buttonStyle(.plain)

        HairlineRule()
      }
    }
  }

  /// The life-list stat — distinct confirmed species — or nil until there is one to show.
  private var lifeListStat: String? {
    let count: Int
    switch uiState {
    case .ready(let lifeList, _), .searching(let lifeList, _): count = lifeList
    case .loading, .empty: count = 0
    }
    guard count > 0 else { return nil }
    return count == 1 ? "1 species logged" : "\(count) species logged"
  }
}

// MARK: - States

/// Shown when nothing has been logged yet — a fresh install, honestly, not an error.
private struct JournalEmpty: View {
  @Environment(\.theme) private var theme

  var body: some View {
    CardSurface {
      VStack(spacing: theme.space.related) {
        PlateLabel(text: "The Journal Is Empty")

        Text("Every outing you save appears here, newest first — birds or no birds. Head to Identify to log your first.")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, theme.space.cardInset)
      .padding(.vertical, theme.space.page)
    }
  }
}

/// A few ruled ghost rows while the first read lands, so the page does not jump when it does.
private struct JournalLoading: View {
  private static let rowCount = 4

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<Self.rowCount, id: \.self) { _ in
        JournalRowPlaceholder()
        HairlineRule()
      }
    }
  }
}

private struct JournalRowPlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: theme.space.separate) {
      RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
        .fill(theme.colors.rule)
        .frame(
          width: SpeciesRowMetrics.thumbnailSize,
          height: SpeciesRowMetrics.thumbnailSize
        )

      VStack(alignment: .leading, spacing: theme.space.snug) {
        RoundedRectangle(cornerRadius: 2).fill(theme.colors.rule).frame(width: 150, height: 15)
        RoundedRectangle(cornerRadius: 2).fill(theme.colors.rule).frame(width: 96, height: 12)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, theme.space.related)
  }
}

// MARK: - Previews

#Preview("Journal") {
  NavigationStack {
    JournalContentView(
      uiState: .ready(lifeList: 12, months: PreviewCatalog.journalMonths),
      query: "",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
}

#Preview("Journal (dark)") {
  NavigationStack {
    JournalContentView(
      uiState: .ready(lifeList: 12, months: PreviewCatalog.journalMonths),
      query: "",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
  .environment(\.colorScheme, .dark)
}

#Preview("Searching") {
  NavigationStack {
    JournalContentView(
      uiState: .searching(lifeList: 12, results: PreviewCatalog.journalEntries),
      query: "jay",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
}

#Preview("No matches") {
  NavigationStack {
    JournalContentView(
      uiState: .searching(lifeList: 12, results: []),
      query: "pelican",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
}

#Preview("Empty") {
  NavigationStack {
    JournalContentView(
      uiState: .empty,
      query: "",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
}

#Preview("Loading") {
  NavigationStack {
    JournalContentView(
      uiState: .loading,
      query: "",
      mediaFileStore: nil,
      onSearch: { _ in }
    )
  }
  .birdSpotterTheme()
}
