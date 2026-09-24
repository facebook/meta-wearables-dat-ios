/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  ExploreViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// Explore's search and browse policy, against `PreviewCatalog.guide` rather than the
/// shipped database.
///
/// The fixture is deliberate: `BirdCatalogRepositoryTests` already covers the real
/// `catalog.db`, and what is under test here is the rule — which query matches which bird,
/// and what the screen shows for it — not whether the seed staged. Six species in two
/// sections is enough to pin every rule and small enough that a failure names the bird.
///
/// Everything below calls a static function directly. `ExploreViewModel.state` is pure so
/// that the whole policy is reachable without driving a ViewModel through an async load, and
/// without a test harness of any kind.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("ExploreViewModel")
struct ExploreViewModelTests {

  private let guide = PreviewCatalog.guide

  private func bird(_ speciesId: String) throws -> SpeciesWithMedia {
    try #require(guide.flatMap(\.species).first { $0.species.id == speciesId })
  }

  private func ids(_ species: [SpeciesWithMedia]) -> [String] {
    species.map(\.species.id)
  }

  // MARK: - Matching

  @Test func speciesMatching_matchesCommonNameRegardlessOfCase() throws {
    let matches = ExploreViewModel.speciesMatching("BLUE jAy", in: guide)

    #expect(ids(matches) == ["blue-jay"])
  }

  @Test func speciesMatching_matchesPartOfAName() throws {
    // "thrush" is inside "Wood Thrush" but is also the section — the point is only that
    // a fragment works, so this asserts the fragment of a *name* that no section shares.
    let matches = ExploreViewModel.speciesMatching("rave", in: guide)

    #expect(ids(matches) == ["common-raven"])
  }

  @Test func speciesMatching_matchesScientificName() throws {
    let matches = ExploreViewModel.speciesMatching("corvus", in: guide)

    #expect(ids(matches) == ["american-crow", "common-raven"])
  }

  @Test func speciesMatching_matchesFamilyName() throws {
    let matches = ExploreViewModel.speciesMatching("turdidae", in: guide)

    #expect(ids(matches) == ["american-robin", "eastern-bluebird", "wood-thrush"])
  }

  @Test func speciesMatching_matchesGroupName() throws {
    let matches = ExploreViewModel.speciesMatching("jays", in: guide)

    #expect(ids(matches) == ["american-crow", "blue-jay", "common-raven"])
  }

  @Test func speciesMatching_keepsBrowseOrder() throws {
    let matches = ExploreViewModel.speciesMatching("a", in: guide)
    let orders = matches.map(\.species.browseOrder)

    #expect(matches.count > 1)
    #expect(orders == orders.sorted())
  }

  @Test func speciesMatching_ignoresSurroundingWhitespace() throws {
    let matches = ExploreViewModel.speciesMatching("   blue jay \n", in: guide)

    #expect(ids(matches) == ["blue-jay"])
  }

  @Test func speciesMatching_withNoMatch_isEmpty() throws {
    #expect(ExploreViewModel.speciesMatching("pelican", in: guide).isEmpty)
  }

  @Test func speciesMatching_withBlankQuery_isEmpty() throws {
    // The blank case belongs to `state`, which browses instead of searching. Matching
    // returns nothing rather than everything, so a caller that skips that check shows
    // an empty result set instead of silently re-listing the whole guide.
    #expect(ExploreViewModel.speciesMatching("   ", in: guide).isEmpty)
  }

  // MARK: - State

  @Test func state_withBlankQuery_browsesTheGuideWithoutTheFeaturedBird() throws {
    let featured = try bird("blue-jay")

    let state = ExploreViewModel.state(query: "", birdOfTheDay: featured, groups: guide)

    guard case .ready(let birdOfTheDay, let sections) = state else {
      Issue.record("expected .ready, got \(state)")
      return
    }
    #expect(birdOfTheDay.species.id == "blue-jay")
    #expect(!ids(sections.flatMap(\.species)).contains("blue-jay"))
    #expect(sections.flatMap(\.species).count == 5)
  }

  @Test func state_withAQuery_findsTheFeaturedBird() throws {
    // The regression this suite exists for. `ready`'s guide has the featured bird
    // removed, so a search over *that* list makes today's bird the one bird nobody can
    // look up — on precisely the day it is being demoed.
    let featured = try bird("blue-jay")

    let state = ExploreViewModel.state(query: "blue jay", birdOfTheDay: featured, groups: guide)

    guard case .searching(let results) = state else {
      Issue.record("expected .searching, got \(state)")
      return
    }
    #expect(ids(results) == ["blue-jay"])
  }

  @Test func state_withAQueryNothingMatches_isSearchingWithNoResults() throws {
    let state = ExploreViewModel.state(
      query: "pelican",
      birdOfTheDay: try bird("blue-jay"),
      groups: guide
    )

    // Not `.empty`: the catalog is fine, the query just missed. The screen says so.
    #expect(state == .searching(results: []))
  }

  @Test func state_withWhitespaceOnlyQuery_browses() throws {
    let state = ExploreViewModel.state(
      query: "  \n ",
      birdOfTheDay: try bird("blue-jay"),
      groups: guide
    )

    guard case .ready = state else {
      Issue.record("expected .ready, got \(state)")
      return
    }
  }

  @Test func state_withNoBirdOfTheDay_isEmpty() throws {
    #expect(ExploreViewModel.state(query: "", birdOfTheDay: nil, groups: []) == .empty)
    // Still empty with a query: nothing staged means nothing to search.
    #expect(ExploreViewModel.state(query: "jay", birdOfTheDay: nil, groups: []) == .empty)
  }

  // MARK: - Guide pruning

  @Test func withoutSpecies_dropsASectionItEmpties() throws {
    let single = [SpeciesGroup(name: "Jays & Crows", species: [try bird("blue-jay")])]

    let pruned = ExploreViewModel.withoutSpecies("blue-jay", from: single)

    // A header floating over nothing is worse than a missing header.
    #expect(pruned.isEmpty)
  }
}
