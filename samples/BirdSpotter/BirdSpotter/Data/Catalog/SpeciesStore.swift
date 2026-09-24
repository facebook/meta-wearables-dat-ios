/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeciesStore.swift
//  birdspotter
//

import Foundation
import GRDB

/// Every query against `catalog.db`. Reads only — nothing in the app writes here.
///
/// Note what is missing: there are no `AsyncThrowingStream` returns anywhere on this
/// store, where ``SightingStore`` is mostly streams. The catalog is immutable for the
/// life of the process, so an observed query would yield once and then never again — an
/// `async` read says that honestly. The `*Stream()` convention is for sources that
/// actually change.
///
/// Held as a `DatabaseReader` rather than a `DatabaseWriter` for the same reason: the
/// type makes "nothing writes to the catalog" a compile-time fact rather than a habit.
nonisolated struct SpeciesStore: Sendable {

  let reader: any DatabaseReader

  /// The full guide by name, for looking a bird up when you already know what it is.
  func allSpecies() async throws -> [Species] {
    try await reader.read { db in
      try Species.fetchAll(db, sql: "SELECT * FROM Species ORDER BY commonName ASC")
    }
  }

  /// The full guide with its media, in checklist sequence — what Explore browses.
  ///
  /// One statement for all 93 species rather than a page at a time. The rows are the
  /// cheap part; the photos are not, and a lazy list decodes only the thumbnails it
  /// actually shows. Paging the *query* would add state to every layer and save
  /// microseconds. If the catalog ever outgrows a single read, this method is the seam
  /// — nothing above it knows how the list arrives.
  func speciesInBrowseOrder() async throws -> [SpeciesWithMedia] {
    try await reader.read { db in
      try Self.fetchWithMedia(db, sql: "SELECT * FROM Species ORDER BY browseOrder ASC")
    }
  }

  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? {
    try await reader.read { db in
      try Self.fetchWithMedia(
        db,
        sql: "SELECT * FROM Species WHERE id = ?",
        arguments: [speciesId]
      ).first
    }
  }

  /// The identify wizard's one query. A candidate matches when:
  ///  - its `sizeClass` is within one stop of the picked size — nobody judges a bird
  ///    against a silhouette more precisely than that;
  ///  - it is tagged with the picked behavior;
  ///  - it wears **every** picked color. Each color the user names is on the bird, so
  ///    naming more narrows the list. The COUNT-equals trick is that rule in SQL: the
  ///    species' colors ∩ picked = picked.
  ///
  /// Results come back in `browseOrder` — checklist sequence, the order the rest of
  /// the guide reads in. We have no likelihood data to rank by, and pretending
  /// otherwise would be a fake confidence score.
  func identifyCandidates(
    sizeClass: Int,
    colors: Set<PlumageColor>,
    behavior: BirdBehavior
  ) async throws -> [SpeciesWithMedia] {
    // Sorted so the same picks always produce the same statement bindings.
    let colorValues = colors.map(\.rawValue).sorted()
    var bindings: [(any DatabaseValueConvertible)?] = [sizeClass, sizeClass, behavior.rawValue]
    bindings.append(contentsOf: colorValues.map { $0 as (any DatabaseValueConvertible)? })
    bindings.append(colorValues.count)
    return try await reader.read { db in
      try Self.fetchWithMedia(
        db,
        sql: """
          SELECT * FROM Species
          WHERE sizeClass BETWEEN ? - 1 AND ? + 1
            AND EXISTS (SELECT 1 FROM SpeciesBehavior
                        WHERE speciesId = Species.id AND behavior = ?)
            AND (SELECT COUNT(*) FROM SpeciesColor
                 WHERE speciesId = Species.id
                   AND color IN (\(databaseQuestionMarks(count: colorValues.count)))) = ?
          ORDER BY browseOrder ASC
          """,
        arguments: StatementArguments(bindings)
      )
    }
  }

  func speciesCount() async throws -> Int {
    try await reader.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM Species") ?? 0
    }
  }

  /// The species at `index` in slug order — the rotation ``BirdCatalogRepository/birdOfTheDay(epochDay:)``
  /// indexes into.
  ///
  /// Ordered by `id` rather than `commonName` deliberately: slugs are frozen by
  /// contract, so the rotation a given day produces stays put even if a common name is
  /// corrected.
  func speciesAt(_ index: Int) async throws -> SpeciesWithMedia? {
    try await reader.read { db in
      try Self.fetchWithMedia(
        db,
        sql: "SELECT * FROM Species ORDER BY id ASC LIMIT 1 OFFSET ?",
        arguments: [index]
      ).first
    }
  }

  /// `seed.version`, `seed.builtAt`. Nil for an unknown key.
  func metaValue(_ key: String) async throws -> String? {
    try await reader.read { db in
      try String.fetchOne(db, sql: "SELECT value FROM AppMeta WHERE key = ?", arguments: [key])
    }
  }

  // MARK: - Internals

  /// Species plus their media in two statements, then grouped in memory.
  ///
  /// Deliberately not a GRDB association, for the same reason ``SightingStore`` avoids
  /// one: the shape has to match Room's `@Relation` output exactly, and two plain
  /// statements make that correspondence obvious in a way `including(all:)` does not.
  private static func fetchWithMedia(
    _ db: Database,
    sql: String,
    arguments: StatementArguments = []
  ) throws -> [SpeciesWithMedia] {
    let species = try Species.fetchAll(db, sql: sql, arguments: arguments)
    guard !species.isEmpty else { return [] }

    let ids = species.map(\.id)
    let media = try SpeciesMedia.fetchAll(
      db,
      sql: """
        SELECT * FROM SpeciesMedia
        WHERE speciesId IN (\(databaseQuestionMarks(count: ids.count)))
        """,
      arguments: StatementArguments(ids)
    )
    let mediaBySpecies = Dictionary(grouping: media, by: \.speciesId)

    return species.map { one in
      SpeciesWithMedia(species: one, media: mediaBySpecies[one.id] ?? [])
    }
  }
}
