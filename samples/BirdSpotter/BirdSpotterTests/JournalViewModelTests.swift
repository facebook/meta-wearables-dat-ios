/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The Journal's search, group and browse policy, against `PreviewCatalog.journalEntries`
/// rather than a live store.
///
/// Everything below calls a static function directly. `JournalViewModel.state` and its
/// helpers are pure so the whole policy is reachable without driving a ViewModel through its
/// streams, and without a test harness of any kind.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("JournalViewModel")
struct JournalViewModelTests {

  private let entries = PreviewCatalog.journalEntries

  /// UTC, so the fixture's midday-UTC timestamps fall in the same civil month wherever the
  /// test runs and the buckets are deterministic.
  private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()

  private func ids(_ entries: [JournalEntry]) -> [String] { entries.map(\.id) }

  // MARK: - Matching

  @Test func entriesMatching_matchesCommonNameRegardlessOfCase() {
    #expect(ids(JournalViewModel.entriesMatching("BLUE jAy", in: entries)) == ["preview-outing-2"])
  }

  @Test func entriesMatching_matchesEveryBirdTheOutingConfirmed() {
    // The cardinal names outing 1 and rides second on outing 2 — both must match.
    #expect(
      ids(JournalViewModel.entriesMatching("cardinalis", in: entries))
        == ["preview-outing-1", "preview-outing-2"]
    )
  }

  @Test func entriesMatching_matchesFamilyName() {
    #expect(ids(JournalViewModel.entriesMatching("corvidae", in: entries)) == ["preview-outing-2"])
  }

  @Test func entriesMatching_withABirdlessOuting_findsNothingToMatch() {
    // A walk that confirmed nothing and left no note has no words in it. It is a
    // first-class journal entry and an unsearchable one, now that place is gone —
    // its coordinates are a pin on a map, not a phrase anybody types.
    #expect(JournalViewModel.entriesMatching("outing", in: entries).isEmpty)
  }

  @Test func entriesMatching_matchesNotes() {
    #expect(ids(JournalViewModel.entriesMatching("maple", in: entries)) == ["preview-outing-1"])
  }

  @Test func entriesMatching_ignoresSurroundingWhitespace() {
    #expect(ids(JournalViewModel.entriesMatching("  blue jay \n", in: entries)) == ["preview-outing-2"])
  }

  @Test func entriesMatching_doesNotMatchScreenLabels() {
    // "No birds confirmed" is wording the screen prints, not something the outing
    // stores, so it is not searchable — a query for it finds nothing rather than every
    // birdless row.
    #expect(JournalViewModel.entriesMatching("confirmed", in: entries).isEmpty)
  }

  @Test func entriesMatching_keepsNewestFirstOrder() {
    // The cardinal is on both bird-bearing outings; the input order (newest first) holds.
    let matches = JournalViewModel.entriesMatching("cardinal", in: entries)
    #expect(ids(matches) == ["preview-outing-1", "preview-outing-2"])
  }

  @Test func entriesMatching_withNoMatch_isEmpty() {
    #expect(JournalViewModel.entriesMatching("pelican", in: entries).isEmpty)
  }

  @Test func entriesMatching_withBlankQuery_isEmpty() {
    #expect(JournalViewModel.entriesMatching("   ", in: entries).isEmpty)
  }

  // MARK: - State

  @Test func state_withNoEntries_isEmpty() {
    #expect(JournalViewModel.state(query: "", entries: [], lifeList: 0, calendar: utc) == .empty)
    // Still empty with a query: nothing logged means nothing to search.
    #expect(JournalViewModel.state(query: "jay", entries: [], lifeList: 5, calendar: utc) == .empty)
  }

  @Test func state_withBlankQuery_groupsByMonth() {
    let state = JournalViewModel.state(query: "", entries: entries, lifeList: 12, calendar: utc)

    guard case .ready(let lifeList, let months) = state else {
      Issue.record("expected .ready, got \(state)")
      return
    }
    #expect(lifeList == 12)
    #expect(months.map(\.key) == ["2026-07", "2026-06"])
    #expect(ids(months[0].entries) == ["preview-outing-1", "preview-outing-2"])
    #expect(ids(months[1].entries) == ["preview-outing-3"])
  }

  @Test func state_withAQuery_searchesFlat() {
    let state = JournalViewModel.state(query: "blue jay", entries: entries, lifeList: 12, calendar: utc)

    guard case .searching(let lifeList, let results) = state else {
      Issue.record("expected .searching, got \(state)")
      return
    }
    #expect(lifeList == 12)
    #expect(ids(results) == ["preview-outing-2"])
  }

  @Test func state_withAQueryNothingMatches_isSearchingWithNoResults() {
    let state = JournalViewModel.state(query: "pelican", entries: entries, lifeList: 12, calendar: utc)
    // Not `.empty`: the journal is fine, the query just missed. The screen says so.
    #expect(state == .searching(lifeList: 12, results: []))
  }

  @Test func state_withWhitespaceOnlyQuery_groups() {
    let state = JournalViewModel.state(query: "  \n ", entries: entries, lifeList: 12, calendar: utc)
    guard case .ready = state else {
      Issue.record("expected .ready, got \(state)")
      return
    }
  }

  // MARK: - Grouping

  @Test func groupByMonth_bucketsByCivilMonthNewestFirst() {
    let months = JournalViewModel.groupByMonth(entries, calendar: utc)

    #expect(months.map(\.key) == ["2026-07", "2026-06"])
    #expect(ids(months[0].entries) == ["preview-outing-1", "preview-outing-2"])
    #expect(ids(months[1].entries) == ["preview-outing-3"])
  }

  // MARK: - Results label

  @Test func resultsLabel_readsSingularAndPlural() {
    #expect(JournalViewModel.resultsLabel(count: 0) == "No Matches")
    #expect(JournalViewModel.resultsLabel(count: 1) == "1 Entry")
    #expect(JournalViewModel.resultsLabel(count: 12) == "12 Entries")
  }
}
