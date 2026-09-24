/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdCatalogRepositoryTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The catalog stack end to end, against the **real shipped `catalog.db`** rather than a
/// fixture.
///
/// Every read below only succeeds if the bundled catalog and the app's expectations agree.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("BirdCatalogRepository")
struct BirdCatalogRepositoryTests {

  private let database: CatalogDatabase
  private let repository: any BirdCatalogRepository

  init() throws {
    database = try CatalogDatabase.openBundledForTesting()
    repository = LocalBirdCatalogRepository(store: database.speciesStore())
  }

  @Test func open_readsTheShippedCatalog() async throws {
    let species = try await repository.allSpecies()

    #expect(species.count == 93)
    #expect(species.contains { $0.id == "northern-cardinal" })
  }

  @Test func allSpecies_isAlphabeticalByCommonName() async throws {
    let names = try await repository.allSpecies().map(\.commonName)

    #expect(names == names.sorted())
  }

  @Test func browseGroups_coverTheWholeCatalogInSeedOrder() async throws {
    let groups = try await repository.browseGroups()
    let flattened = groups.flatMap(\.species)

    #expect(flattened.count == 93)
    #expect(Set(flattened.map(\.species.id)).count == 93)
    #expect(flattened.map(\.species.browseOrder) == flattened.map(\.species.browseOrder).sorted())
  }

  @Test func browseGroups_areContiguousAndNeverEmpty() async throws {
    let groups = try await repository.browseGroups()
    let names = groups.map(\.name)

    // Each group appears once. A name showing up twice means the seed let a group
    // fall in two places, which would print its header twice on Explore.
    #expect(Set(names).count == names.count)
    #expect(groups.allSatisfy { !$0.species.isEmpty })
    // Every species agrees with the group it was filed under.
    #expect(
      groups.allSatisfy { group in
        group.species.allSatisfy { $0.species.groupName == group.name }
      })
  }

  @Test func browseGroups_openTheGuideWithWaterfowl() async throws {
    let groups = try await repository.browseGroups()

    // Checklist sequence, not the alphabet: a field guide starts at the waterfowl and
    // ends at the cardinals, and `browseOrder` is what carries that.
    #expect(groups.first?.name == "Waterfowl & Game Birds")
    #expect(groups.first?.species.first?.species.commonName == "Canada Goose")
    #expect(groups.last?.name == "Cardinals & Grosbeaks")
  }

  @Test func browseGroups_carryTheThumbnailEachRowNeeds() async throws {
    let groups = try await repository.browseGroups()

    #expect(groups.flatMap(\.species).allSatisfy { $0.heroPhoto != nil })
  }

  @Test func findById_returnsSpeciesWithItsBundledMedia() async throws {
    let cardinal = try #require(try await repository.findById("northern-cardinal"))

    #expect(cardinal.species.scientificName == "Cardinalis cardinalis")
    // The external join keys survive the seed round-trip. Kept distinct from the
    // scientific name on purpose — see Species.wikidataId.
    #expect(cardinal.species.wikidataId == "Q726389")
    #expect(cardinal.species.ebirdSpeciesCode == "norcar")
    #expect(cardinal.photos.count == 3)
    #expect(cardinal.heroPhoto?.isPrimary == true)
    #expect(cardinal.referenceAudio != nil)
  }

  @Test func findById_returnsNilForUnknownSpecies() async throws {
    #expect(try await repository.findById("pterodactyl") == nil)
  }

  /// The identify wizard's demo query — a robin-to-crow bird, black, on a wire — finds
  /// the Common Grackle, and everything else it finds is inside the size window. Pinned
  /// to the seed the way the browse tests are: these answers are content, and content
  /// regressions should fail like code ones.
  @Test func identifyCandidates_findTheBlackbirdOnTheWire() async throws {
    let candidates = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 4, colors: [.black], behavior: .onFenceOrWire)
    )
    let ids = candidates.map(\.species.id)

    #expect(ids.contains("common-grackle"))
    #expect(candidates.allSatisfy { (3...5).contains($0.species.sizeClass) })
  }

  /// Size matches within one stop either way — a 4 finds 3s and 5s, never a 6.
  @Test func identifyCandidates_matchWithinOneSizeStop() async throws {
    let candidates = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 6, colors: [.brown], behavior: .soaringOrFlying)
    )

    #expect(!candidates.isEmpty)
    #expect(candidates.allSatisfy { (5...7).contains($0.species.sizeClass) })
    // The Bald Eagle is a 7 — inside a 6's window, outside a 4's.
    #expect(candidates.contains { $0.species.id == "bald-eagle" })
    let narrower = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 4, colors: [.brown], behavior: .soaringOrFlying)
    )
    #expect(!narrower.contains { $0.species.id == "bald-eagle" })
  }

  /// Every picked color must be on the bird, so adding a color can only narrow the
  /// list. Black-and-blue keeps the grackle (it wears both) and drops the Red-winged
  /// Blackbird (black, but never blue).
  @Test func identifyCandidates_requireEveryPickedColor() async throws {
    let black = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 4, colors: [.black], behavior: .onFenceOrWire)
    )
    let blackAndBlue = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 4, colors: [.black, .blue], behavior: .onFenceOrWire)
    )
    let blackIds = Set(black.map(\.species.id))
    let blackAndBlueIds = Set(blackAndBlue.map(\.species.id))

    #expect(blackAndBlueIds.isSubset(of: blackIds))
    #expect(blackIds.contains("red-winged-blackbird"))
    #expect(blackAndBlueIds.contains("common-grackle"))
    #expect(!blackAndBlueIds.contains("red-winged-blackbird"))
  }

  /// Behavior is a hard filter: the same bird appears where it lives, not elsewhere.
  @Test func identifyCandidates_filterByBehavior() async throws {
    let swimming = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 6, colors: [.green], behavior: .swimmingOrWading)
    )
    let atFeeder = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 6, colors: [.green], behavior: .atFeeder)
    )

    #expect(swimming.contains { $0.species.id == "mallard" })
    #expect(!atFeeder.contains { $0.species.id == "mallard" })
  }

  /// Results read in checklist sequence, like every other list in the guide.
  @Test func identifyCandidates_arriveInBrowseOrder() async throws {
    let candidates = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 1, colors: [.yellow], behavior: .inTreesOrBushes)
    )

    #expect(candidates.count >= 2)
    #expect(candidates.map(\.species.browseOrder) == candidates.map(\.species.browseOrder).sorted())
  }

  /// The results cards need plates; every candidate arrives with its media.
  @Test func identifyCandidates_carryTheMediaTheirCardsNeed() async throws {
    let candidates = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 2, colors: [.red], behavior: .atFeeder)
    )

    #expect(candidates.contains { $0.species.id == "northern-cardinal" })
    #expect(candidates.allSatisfy { $0.heroPhoto != nil })
  }

  /// An impossible ask — a goose-sized green feeder bird — is empty, not an error.
  @Test func identifyCandidates_emptyWhenNothingFits() async throws {
    let candidates = try await repository.identifyCandidates(
      IdentifyQuery(sizeClass: 7, colors: [.green], behavior: .atFeeder)
    )

    #expect(candidates.isEmpty)
  }

  /// Every species earns its card: three photos and one vocalization, no exceptions.
  @Test func everySpecies_shipsPhotosAndAudio() async throws {
    var thin: [String] = []
    for species in try await repository.allSpecies() {
      let full = try #require(try await repository.findById(species.id))
      if full.photos.count < 3 || full.referenceAudio == nil {
        thin.append(species.id)
      }
    }

    #expect(thin.isEmpty)
  }

  /// The clip earns a picture too: whatever a species can play, it can also show.
  @Test func everySpecies_shipsASonogramForItsClip() async throws {
    var missing: [String] = []
    for species in try await repository.allSpecies() {
      let full = try #require(try await repository.findById(species.id))
      if full.referenceAudio != nil && full.sonogram == nil {
        missing.append(species.id)
      }
    }

    #expect(missing.isEmpty)
  }

  /// A sonogram is an image of the clip, never a clip. Guards the partition directly:
  /// `audio` was once "everything that isn't a photo", which handed the player a PNG the
  /// moment the catalog started shipping sonograms.
  @Test func sonogram_isNeverServedAsAudio() async throws {
    let cardinal = try #require(try await repository.findById("northern-cardinal"))
    let sonogram = try #require(cardinal.sonogram)

    #expect(sonogram.type == .sonogram)
    #expect(sonogram.isPrimary == false)
    #expect(cardinal.audio.allSatisfy { $0.type != .sonogram })
    #expect(try #require(cardinal.referenceAudio).type != .sonogram)
  }

  /// The seed writes SCREAMING_SNAKE that GRDB maps back onto `ConservationStatus`; a
  /// raw IUCN label like "least concern" would fail to decode rather than arrive wrong.
  /// Nil is legitimate — six birds have no assessment on Wikidata.
  @Test func conservationStatus_decodesWhereTheSeedHasOne() async throws {
    let statuses = try await repository.allSpecies().compactMap(\.conservationStatus)

    #expect(!statuses.isEmpty)
    #expect(statuses.contains(.leastConcern))
  }

  /// Bundled files exist for every row that claims them.
  @Test func everyMediaRow_resolvesToABundledAsset() async throws {
    let assets = CatalogAssetStore(bundle: .main)
    var missing: [String] = []
    for species in try await repository.allSpecies() {
      let full = try #require(try await repository.findById(species.id))
      missing.append(contentsOf: full.media.filter { !assets.exists($0) }.map(\.assetKey))
    }

    #expect(missing.isEmpty)
  }

  @Test func birdOfTheDay_isStableForADayAndMovesTheNext() async throws {
    let today = try #require(try await repository.birdOfTheDay(epochDay: 20_656))
    let again = try #require(try await repository.birdOfTheDay(epochDay: 20_656))
    let tomorrow = try #require(try await repository.birdOfTheDay(epochDay: 20_657))

    #expect(today.species.id == again.species.id)
    #expect(today.species.id != tomorrow.species.id)
  }

  @Test func birdOfTheDay_carriesTheMediaItsCardNeeds() async throws {
    let bird = try #require(try await repository.birdOfTheDay(epochDay: 20_656))

    #expect(bird.heroPhoto != nil)
    #expect(bird.referenceAudio != nil)
    #expect(!bird.species.commonName.isEmpty)
  }

  /// The rotation visits every species before repeating any — for any catalog size.
  @Test func birdOfTheDay_coversTheWholeCatalogBeforeRepeating() async throws {
    let count = try await repository.allSpecies().count
    let seen = Set((0..<count).map { birdOfTheDayIndex(epochDay: 20_656 + Int64($0), count: count) })

    #expect(seen.count == count)

    // Sizes the catalog might plausibly grow to, including ones sharing a factor
    // with the stride. The property has to hold by construction, not by luck.
    for size in [1, 2, 3, 40, 93, 100, 150] {
      let cycle = Set((0..<size).map { birdOfTheDayIndex(epochDay: Int64($0), count: size) })
      #expect(cycle.count == size, "catalog of \(size)")
    }
  }

  /// Consecutive days land far apart, rather than marching down the slug order.
  @Test func birdOfTheDay_doesNotWalkTheCatalogInOrder() {
    let week = (0..<6).map { birdOfTheDayIndex(epochDay: 20_656 + Int64($0), count: 93) }

    #expect(week == [2, 58, 21, 77, 40, 3])
  }

  @Test func birdOfTheDayIndex_matchesThePinnedValues() {
    // Pinned values: these exact pairs are what keeps a given day landing on a given
    // bird. If they ever drift, the demo shows different birds on the two phones on stage.
    #expect(birdOfTheDayIndex(epochDay: 20_656, count: 93) == 2)
    #expect(birdOfTheDayIndex(epochDay: 20_657, count: 93) == 58)
    #expect(birdOfTheDayIndex(epochDay: 0, count: 93) == 0)
    #expect(birdOfTheDayIndex(epochDay: 1, count: 93) == 56)
  }

  /// The constant the replacement check compares against has to match what the pipeline
  /// actually stamped, or an install keeps serving a catalog the app thinks it replaced.
  @Test func seedVersion_matchesTheExpectedConstant() async throws {
    #expect(try await repository.seedVersion() == CatalogDatabase.expectedSeedVersion)
  }

  /// The day number the screen asks for is the *civil* date here, not a UTC one.
  ///
  /// Tokyo is the case that catches a naive implementation: local midnight is 15:00 the
  /// previous day in UTC, so dividing a timestamp by 86 400 reports yesterday's bird
  /// for the first nine hours of every day.
  @Test func epochDay_followsTheLocalCalendarNotUTC() throws {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

    // 2026-07-22 08:00 JST — comfortably inside the window a UTC-based reading
    // would still call the 21st.
    let morning = try #require(
      tokyo.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 8))
    )
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let expected = try #require(
      utc.date(from: DateComponents(year: 2026, month: 7, day: 22))
    )

    #expect(
      ExploreViewModel.epochDay(for: morning, calendar: tokyo)
        == Int64(expected.timeIntervalSince1970 / 86_400)
    )
  }
}
