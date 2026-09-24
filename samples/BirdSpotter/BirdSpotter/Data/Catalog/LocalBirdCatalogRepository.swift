/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LocalBirdCatalogRepository.swift
//  birdspotter
//

import Foundation

/// The only implementation of ``BirdCatalogRepository``: `catalog.db`, and nothing else.
///
/// Thinner than ``LocalJournalRepository`` by a wide margin, and that asymmetry is the
/// point — the Journal has to keep a database and a media directory consistent through
/// writes, where the catalog is a file somebody else built. Bundled bytes are
/// ``CatalogAssetStore``'s business and are resolved by the UI from the rows this
/// returns, so nothing here has to be told where assets live.
nonisolated struct LocalBirdCatalogRepository: BirdCatalogRepository {

  let store: SpeciesStore

  func allSpecies() async throws -> [Species] {
    try await store.allSpecies()
  }

  /// Chunks the guide into runs of equal `groupName`, in the order the rows arrive.
  ///
  /// A run, not a bucket. A dictionary-based grouping would gather a group that had
  /// somehow landed in two places back into one — hiding the very mistake
  /// `build_seed_db.py`'s contiguity check exists to catch, and quietly reordering the
  /// guide to do it. Walking the list keeps the seed's order the visible truth.
  func browseGroups() async throws -> [SpeciesGroup] {
    var runs: [[SpeciesWithMedia]] = []
    for bird in try await store.speciesInBrowseOrder() {
      if let current = runs.last, current[0].species.groupName == bird.species.groupName {
        runs[runs.count - 1].append(bird)
      } else {
        runs.append([bird])
      }
    }
    return runs.map { SpeciesGroup(name: $0[0].species.groupName, species: $0) }
  }

  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? {
    try await store.findById(speciesId)
  }

  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] {
    try await store.identifyCandidates(
      sizeClass: query.sizeClass,
      colors: query.colors,
      behavior: query.behavior
    )
  }

  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? {
    let count = try await store.speciesCount()
    guard count > 0 else { return nil }
    return try await store.speciesAt(birdOfTheDayIndex(epochDay: epochDay, count: count))
  }

  func seedVersion() async throws -> Int? {
    try await store.metaValue(CatalogDatabase.seedVersionKey).flatMap(Int.init)
  }
}
