/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CatalogDatabase.swift
//  birdspotter
//

import Foundation
import GRDB

/// Schema version for `catalog.db`.
///
/// Unrelated to the *seed* version. This number describes the shape of the tables and
/// changes when a column does; ``CatalogDatabase/expectedSeedVersion`` describes the
/// content inside them and changes whenever a bird does. There are no migrations either
/// way — the file is replaced wholesale, which is the entire reason the catalog lives
/// apart from ``JournalDatabase``.
nonisolated let catalogDatabaseVersion = 6

/// `catalog.db` — the shipped field guide. Copied out of the app bundle on first launch,
/// read-only forever after, and thrown away without ceremony whenever the bundled seed
/// is newer than the installed one.
///
/// The schema is not declared here at all. The exported schema the seed pipeline builds
/// against the bundled catalog is the authoritative DDL, and this side simply reads
/// whatever the pipeline produced — which is why there is no `DatabaseMigrator` in this
/// file and there never should be.
nonisolated final class CatalogDatabase: Sendable {

  static let fileName = "catalog.db"

  /// The bundle folder reference the seed pipeline stages into. See
  /// `SeedData/catalog.db`.
  static let bundleSubdirectory = "SeedData"

  /// The `AppMeta` row the replacement check turns on.
  static let seedVersionKey = "seed.version"

  /// The seed version this build of the app ships.
  ///
  /// Must equal `seed.version` in the bundled catalog; bump both
  /// together whenever catalog content changes, or installs will keep serving the
  /// stale copy they already have. `BirdCatalogRepositoryTests` fails loudly if they
  /// drift.
  static let expectedSeedVersion = 6

  let reader: any DatabaseReader

  private init(reader: any DatabaseReader) {
    self.reader = reader
  }

  func speciesStore() -> SpeciesStore {
    SpeciesStore(reader: reader)
  }

  /// Opens the catalog, replacing an installed copy that the bundle supersedes.
  ///
  /// The staleness check is written by hand rather than delegated to a framework: GRDB has
  /// no destructive-migration switch to lean on, so the logic has to exist here regardless,
  /// and one written rule beats a framework behaviour that only looks like one.
  static func open(at url: URL? = nil) throws -> CatalogDatabase {
    let fileURL = try url ?? defaultURL()
    try installIfNeeded(at: fileURL)

    // Read-only, because nothing in the app writes a species and the file is a copy
    // of a bundle resource either way. It also lets SQLite skip journalling entirely.
    var config = Configuration()
    config.readonly = true
    return CatalogDatabase(reader: try DatabaseQueue(path: fileURL.path, configuration: config))
  }

  /// Opens the bundled catalog in place, without copying. Tests only.
  ///
  /// Fine for reading precisely because the file is opened read-only — but not how the
  /// app runs, since the shipped copy has to be replaceable and a bundle resource is
  /// not. Keeping the difference to one method means the app path stays honest.
  static func openBundledForTesting() throws -> CatalogDatabase {
    guard let bundled = bundledURL() else {
      throw CatalogError.seedDataMissing
    }
    var config = Configuration()
    config.readonly = true
    return CatalogDatabase(reader: try DatabaseQueue(path: bundled.path, configuration: config))
  }

  /// Application Support, beside `journal.db` — the app's own storage, not the user's.
  static func defaultURL() throws -> URL {
    try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent(fileName)
  }

  static func bundledURL(in bundle: Bundle = .main) -> URL? {
    bundle.url(
      forResource: "catalog",
      withExtension: "db",
      subdirectory: bundleSubdirectory
    )
  }

  // MARK: - Installation

  /// Copies the bundled catalog into place when there isn't one, or when the one that
  /// is there has been superseded.
  private static func installIfNeeded(at fileURL: URL) throws {
    guard let bundled = bundledURL() else {
      throw CatalogError.seedDataMissing
    }

    if FileManager.default.fileExists(atPath: fileURL.path) {
      let installed = installedSeedVersion(at: fileURL)
      guard installed != expectedSeedVersion else { return }

      BirdLog.info(.catalog, "replacing catalog seed v\(installed.map(String.init) ?? "unreadable") with bundled v\(expectedSeedVersion)")
      try remove(at: fileURL)
    }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: bundled, to: fileURL)
  }

  /// The installed file's `seed.version`, or nil if it cannot be read.
  ///
  /// Anything unreadable is treated as stale rather than as an error: a catalog we
  /// can't interrogate is one we should replace, and there is nothing in it worth
  /// preserving. The user's journal is a different file and is never touched here.
  private static func installedSeedVersion(at fileURL: URL) -> Int? {
    do {
      var config = Configuration()
      config.readonly = true
      let queue = try DatabaseQueue(path: fileURL.path, configuration: config)
      return try queue.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT value FROM AppMeta WHERE key = ?",
          arguments: [seedVersionKey]
        )
      }
    } catch {
      BirdLog.warning(.catalog, "installed catalog is unreadable; treating as stale — \(error.localizedDescription)")
      return nil
    }
  }

  /// Drops the file and its sidecars. A leftover `-wal` would otherwise be replayed
  /// over the freshly copied catalog.
  private static func remove(at fileURL: URL) throws {
    for path in [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"]
    where FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(atPath: path)
    }
  }
}

/// Failures callers are expected to handle.
///
/// **Platform note:** this type exists because this side copies the seed file itself. Where
/// that copying belongs to a framework, the framework's own error is what callers see, and
/// inventing a matching `CatalogError` would be a type that exists only to make a table of
/// contents symmetrical.
nonisolated enum CatalogError: Error, Equatable {
  /// `SeedData/` never made it into the bundle.
  case seedDataMissing
}
