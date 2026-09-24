/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalViewModel.swift
//  birdspotter
//

import Foundation

/// What the Journal screen renders.
///
/// `empty` is an honest state, not an error: a fresh install has logged nothing, so the
/// Journal is empty until the first identify completes. It is distinct from `searching` with
/// no results — one means "you have no entries", the other "none match what you typed".
nonisolated enum JournalUiState: Equatable {
  case loading

  case empty

  /// The Journal itself: every outing, newest first, under a heading per month. `lifeList`
  /// is the count of distinct confirmed species — the header's stat — carried in the state
  /// so the header never disagrees with the list under it.
  case ready(lifeList: Int, months: [JournalMonth])

  /// What a non-empty query matched, flat and newest first — no month headings, for the
  /// same reason Explore's search results have no section headings: a query pulls a handful
  /// of entries out of many months, and heading each would put more headings on screen than
  /// results. Empty `results` is the honest no-matches case.
  case searching(lifeList: Int, results: [JournalEntry])
}

/// The Journal's state holder.
///
/// Where ``ExploreViewModel`` reads a catalog that cannot change and so loads once, the
/// Journal is **live** — an outing saves while the screen is up — so this
/// consumes ``JournalRepository/journalStream()`` and ``JournalRepository/lifeListCountStream()``
/// and rebuilds on every emission. Each confirmed sighting's `speciesId` is resolved
/// against the catalog (which *is* fixed, so the lookups are memoised) to pair the outing
/// with its birds.
///
/// `calendar` is injected so a test can pin the timezone the month buckets fall in — the same
/// seam ``ExploreViewModel`` opens with `today`.
@MainActor
@Observable
final class JournalViewModel {

  private(set) var uiState: JournalUiState = .loading

  /// What is in the search field. Writable only through ``search(_:)``, so it can never
  /// disagree with the state computed from it.
  private(set) var query: String = ""

  private let journal: any JournalRepository
  private let birdCatalog: any BirdCatalogRepository
  private let calendar: Calendar

  /// The resolved Journal, kept alongside `uiState` so a keystroke can recompute against it
  /// without re-reading the database — the same reason ``ExploreViewModel`` holds `groups`.
  private var entries: [JournalEntry] = []
  private var lifeList = 0
  /// Set once the first journal emission lands. Until then the field is on screen and
  /// typeable, but there is nothing to search and the screen shows `loading`.
  private var hasLoaded = false

  /// `speciesId` → resolved bird. The catalog cannot change while the app runs, so a
  /// species is looked up once however many sightings reference it. A stored value of nil
  /// is a real answer — an id the guide doesn't have — and is not looked up again.
  private var speciesCache: [String: SpeciesWithMedia?] = [:]

  init(
    journal: any JournalRepository,
    birdCatalog: any BirdCatalogRepository,
    calendar: Calendar = .current
  ) {
    self.journal = journal
    self.birdCatalog = birdCatalog
    self.calendar = calendar
  }

  /// Observes both streams for the life of the view.
  ///
  /// Driven by `.task` on the screen, so it starts when the Journal appears and is
  /// cancelled with it. The two run
  /// concurrently: a new sighting and a changed life-list count can arrive independently,
  /// and each updates its own slice before recomputing.
  func observe() async {
    async let journal: Void = observeJournal()
    async let lifeList: Void = observeLifeList()
    _ = await (journal, lifeList)
  }

  private func observeJournal() async {
    do {
      for try await snapshot in journal.journalStream() {
        entries = await resolveEntries(snapshot)
        hasLoaded = true
        refresh()
      }
    } catch is CancellationError {
      // The screen went away mid-read. Leaving the state alone means coming back shows
      // what was there rather than a flash of the placeholder.
      return
    } catch {
      // A broken journal file is not something the user can act on; show it as empty
      // rather than an error, matching how Explore treats a catalog that won't open.
      entries = []
      hasLoaded = true
      refresh()
    }
  }

  private func observeLifeList() async {
    do {
      for try await count in journal.lifeListCountStream() {
        lifeList = count
        refresh()
      }
    } catch {
      // The count is a decoration on the header; if its stream fails, leave the last
      // good number rather than zeroing a stat the list below may still contradict.
    }
  }

  /// Runs a query against the loaded Journal, or clears it when `query` is blank.
  ///
  /// Synchronous, like Explore's: the entries are already in memory, so filtering them is a
  /// few string comparisons a keystroke has no reason to wait on.
  func search(_ query: String) {
    self.query = query
    refresh()
  }

  private func refresh() {
    guard hasLoaded else { return }
    uiState = Self.state(query: query, entries: entries, lifeList: lifeList, calendar: calendar)
  }

  // MARK: - Resolution

  /// Pairs each outing with its confirmed birds — story order, resolved through the
  /// memoised catalog.
  private func resolveEntries(_ snapshot: [OutingWithChildren]) async -> [JournalEntry] {
    var resolved: [JournalEntry] = []
    resolved.reserveCapacity(snapshot.count)
    for withChildren in snapshot {
      var birds: [ConfirmedBird] = []
      for sighting in JournalEntry.storyOrder(withChildren) {
        birds.append(ConfirmedBird(sighting: sighting, species: await resolveSpecies(sighting.speciesId)))
      }
      resolved.append(JournalEntry(withChildren: withChildren, birds: birds))
    }
    return resolved
  }

  private func resolveSpecies(_ speciesId: String) async -> SpeciesWithMedia? {
    // A present key — even one whose value is nil — is a settled answer.
    if let cached = speciesCache[speciesId] { return cached }
    let resolved = (try? await birdCatalog.findById(speciesId)) ?? nil
    speciesCache[speciesId] = resolved
    return resolved
  }

  // MARK: - Pure policy

  /// What the screen shows, given the query and what the streams loaded.
  ///
  /// Pure and static so the whole policy — no rows browses to empty, a blank query groups by
  /// month, a real one searches flat — is one function a test calls directly, the same shape
  /// as ``ExploreViewModel/state(query:birdOfTheDay:groups:)``.
  nonisolated static func state(
    query: String,
    entries: [JournalEntry],
    lifeList: Int,
    calendar: Calendar = .current
  ) -> JournalUiState {
    guard !entries.isEmpty else { return .empty }

    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .ready(lifeList: lifeList, months: groupByMonth(entries, calendar: calendar))
    }
    return .searching(lifeList: lifeList, results: entriesMatching(trimmed, in: entries))
  }

  /// Every entry any of whose birds (common, scientific or family name), place or notes
  /// contain `query`. A birdless outing has no names to match, but its place and notes
  /// still count.
  ///
  /// `lowercased()` and a plain `contains`, deliberately, rather than
  /// `localizedCaseInsensitiveContains`: the locale-independent fold is what makes two
  /// phones side by side return the same rows for the same word — the same reason, spelled
  /// out at length, that ``ExploreViewModel/speciesMatching(_:in:)`` folds this way.
  nonisolated static func entriesMatching(
    _ query: String,
    in entries: [JournalEntry]
  ) -> [JournalEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return [] }

    return entries.filter { entry in
      searchableStrings(for: entry).contains { $0.lowercased().contains(needle) }
    }
  }

  private nonisolated static func searchableStrings(for entry: JournalEntry) -> [String] {
    var fields: [String] = []
    for bird in entry.birds {
      if let species = bird.species?.species {
        fields.append(species.commonName)
        fields.append(species.scientificName)
        fields.append(species.familyName)
      }
    }
    if let notes = entry.outing.notes { fields.append(notes) }
    return fields
  }

  /// Buckets entries by the civil month of their `startedAt`, newest month first, entries
  /// within each newest first.
  ///
  /// Relies on the stream arriving sorted `startedAt` descending: first-seen key order is
  /// then already newest-first, so no month or entry needs re-sorting. `calendar` decides
  /// which day a midnight-adjacent outing falls in — pinned in tests, `.current` in the app.
  nonisolated static func groupByMonth(
    _ entries: [JournalEntry],
    calendar: Calendar = .current
  ) -> [JournalMonth] {
    var order: [String] = []
    var buckets: [String: [JournalEntry]] = [:]
    var titles: [String: String] = [:]

    for entry in entries {
      let startedAt = entry.outing.startedAt
      let key = JournalFormatting.monthKey(startedAt, calendar: calendar)
      if buckets[key] == nil {
        order.append(key)
        titles[key] = JournalFormatting.monthTitle(startedAt, calendar: calendar)
      }
      buckets[key, default: []].append(entry)
    }

    return order.map { key in
      JournalMonth(key: key, title: titles[key] ?? key, entries: buckets[key] ?? [])
    }
  }

  /// The plate over a query's matches — "12 ENTRIES", "1 ENTRY", "NO MATCHES". Entries,
  /// not sightings: a journal row is an outing, and an outing with nothing confirmed is
  /// still a row.
  nonisolated static func resultsLabel(count: Int) -> String {
    switch count {
    case 0: "No Matches"
    case 1: "1 Entry"
    default: "\(count) Entries"
    }
  }
}
