/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  ExploreViewModel.swift
//  birdspotter
//

import Foundation

/// What the Explore screen renders.
///
/// `empty` is not an error state and not a placeholder — it is what an empty catalog
/// honestly looks like, which is possible only if the seed failed to stage. The screen
/// shows its title area regardless; only the card below it has anything to be missing.
nonisolated enum ExploreUiState: Equatable {
  case loading

  /// `guide` is the rest of the field guide, in checklist order and already sectioned —
  /// `birdOfTheDay` is not in it, because it is on screen directly above and printing it
  /// twice reads as a bug. A group never empties out from that removal: the smallest one
  /// the seed ships holds two species.
  case ready(birdOfTheDay: SpeciesWithMedia, guide: [SpeciesGroup])

  /// What a non-empty query matched, in browse order.
  ///
  /// A state of its own rather than a filter applied to `ready`, because a query replaces
  /// the whole page below the title: the featured card is not a search result, and leaving
  /// it above the matches would make the field look like it had missed something. Empty
  /// `results` is the honest no-matches case, not a placeholder.
  case searching(results: [SpeciesWithMedia])

  case empty
}

/// Explore's state holder.
///
/// `today` is injected so a test can pin the date without touching the clock — the same
/// seam `LocalJournalRepository` opens with its `now` parameter.
@MainActor
@Observable
final class ExploreViewModel {

  private(set) var uiState: ExploreUiState = .loading

  /// What is in the search field. Writable only through ``search(_:)``, so it can never
  /// disagree with the state that was computed from it.
  private(set) var query: String = ""

  private let birdCatalog: any BirdCatalogRepository
  private let today: @Sendable () -> Date

  /// The whole guide, today's featured bird included.
  ///
  /// Kept alongside `uiState` rather than read back out of it, because
  /// ``ExploreUiState/ready``'s `guide` has the featured bird taken *out* — searching that
  /// copy would make today's bird the one bird in the catalog you cannot look up.
  private var groups: [SpeciesGroup] = []
  private var birdOfTheDay: SpeciesWithMedia?
  private var isLoaded = false

  init(
    birdCatalog: any BirdCatalogRepository,
    today: @escaping @Sendable () -> Date = Date.init
  ) {
    self.birdCatalog = birdCatalog
    self.today = today
  }

  /// Driven by `.task` on the view, so the load starts when the screen appears and is
  /// cancelled with it.
  func load() async {
    do {
      let bird = try await birdCatalog.birdOfTheDay(epochDay: Self.epochDay(for: today()))
      birdOfTheDay = bird
      groups = bird == nil ? [] : try await birdCatalog.browseGroups()
    } catch is CancellationError {
      // The screen went away mid-query. Leaving the state alone means coming back
      // shows the placeholder again rather than a stale empty card.
      return
    } catch {
      birdOfTheDay = nil
      groups = []
    }
    isLoaded = true
    refresh()
  }

  /// Runs a query against the guide, or clears it when `query` is blank.
  ///
  /// Synchronous on purpose. `load()` already holds all 93 species in memory, so this is
  /// a few hundred string comparisons — a keystroke has no reason to wait on a database
  /// round trip, and a `LIKE` query would be one more surface to mirror and test in two
  /// languages for no gain. See ``speciesMatching(_:in:)``.
  func search(_ query: String) {
    self.query = query
    refresh()
  }

  /// Recomputes what the screen shows from the query and whatever `load()` fetched.
  ///
  /// Called from both, so a query typed while the first read is still in flight is
  /// honoured the moment that read lands rather than quietly dropped.
  private func refresh() {
    // Still loading: the field is on screen and typeable, but there is nothing to
    // search yet. The query is held and applied when `load()` finishes.
    guard isLoaded else { return }
    uiState = Self.state(query: query, birdOfTheDay: birdOfTheDay, groups: groups)
  }

  /// What the screen shows, given a query and what the catalog returned.
  ///
  /// Pure and static so the whole policy — a blank query browses, a real one searches,
  /// and the search covers today's bird as well — is one function a test can call
  /// directly, instead of behaviour only reachable by driving a ViewModel through an
  /// async load. The same reason ``withoutSpecies(_:from:)`` and ``epochDay(for:calendar:)``
  /// are up here.
  nonisolated static func state(
    query: String,
    birdOfTheDay: SpeciesWithMedia?,
    groups: [SpeciesGroup]
  ) -> ExploreUiState {
    guard let bird = birdOfTheDay else { return .empty }

    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .ready(
        birdOfTheDay: bird,
        guide: withoutSpecies(bird.species.id, from: groups)
      )
    }
    return .searching(results: speciesMatching(trimmed, in: groups))
  }

  /// Every species whose common name, binomial, family or section contains `query`.
  ///
  /// Reads `groups` whole, today's featured bird included — see the note on ``groups``.
  /// Matches come back in browse order for free, since that is the order `groups` is
  /// already in and flattening preserves it. Nothing is ranked: 93 rows do not need it,
  /// and a ranking is one more thing that would have to score identically in two
  /// languages.
  ///
  /// Family and section are searched as well as the two names so that "warbler" finds a
  /// section and "corvidae" a family, without either being its own feature.
  ///
  /// `lowercased()` and a plain `contains`, deliberately, rather than
  /// `localizedCaseInsensitiveContains`: that folds case by the *user's* locale, so the same
  /// word would match different rows on two phones set to different regions (`I` → `ı` in
  /// Turkish). A locale-independent fold is what makes them agree — the concern
  /// ``birdOfTheDayIndex(epochDay:count:)`` documents at greater length. The shipped
  /// catalog is ASCII throughout, so nothing here folds diacritics; a seed that
  /// introduces one needs that added deliberately.
  nonisolated static func speciesMatching(
    _ query: String,
    in groups: [SpeciesGroup]
  ) -> [SpeciesWithMedia] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return [] }

    return groups.flatMap(\.species).filter { bird in
      [
        bird.species.commonName,
        bird.species.scientificName,
        bird.species.familyName,
        bird.species.groupName,
      ].contains { $0.lowercased().contains(needle) }
    }
  }

  /// The guide without one species, and without any section it just emptied.
  ///
  /// The empty-section guard cannot fire against today's seed — every group ships at
  /// least two birds — but it costs one predicate and it is the difference between a
  /// later thin group and a header floating over nothing.
  nonisolated static func withoutSpecies(
    _ speciesId: String,
    from groups: [SpeciesGroup]
  ) -> [SpeciesGroup] {
    groups.compactMap { group in
      let kept = group.species.filter { $0.species.id != speciesId }
      guard !kept.isEmpty else { return nil }
      return SpeciesGroup(name: group.name, species: kept)
    }
  }

  /// Days since 1970-01-01 for the *civil* date in the user's timezone.
  ///
  /// The obvious version, dividing `startOfDay(for:).timeIntervalSince1970` by 86 400,
  /// is wrong east of Greenwich: local midnight in Tokyo is 15:00 the *previous* day in
  /// UTC, so it reports yesterday's bird for the first nine hours of every day. Reading
  /// the calendar date locally and re-anchoring it at UTC midnight sidesteps that
  /// entirely — the arithmetic never sees a timezone offset.
  /// `nonisolated` because it is arithmetic on its arguments and touches nothing on the
  /// model — hopping to the main actor to divide two numbers would be theatre.
  nonisolated static func epochDay(for date: Date, calendar: Calendar = .current) -> Int64 {
    let civil = calendar.dateComponents([.year, .month, .day], from: date)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard let midnight = utc.date(from: civil) else { return 0 }
    return Int64((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
  }
}
