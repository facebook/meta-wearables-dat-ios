/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalDatabase.swift
//  birdspotter
//

import Foundation
import GRDB

/// Schema version for `journal.db`.
///
/// **Kept in lockstep with the exported schema** — the same number, the same equivalent DDL,
/// in the same order. `catalog.db` has no migrations by design and is not managed here;
/// it is replaced wholesale on a seed bump.
nonisolated let journalDatabaseVersion = 5

/// `journal.db` — created empty on first launch, migrated in place forever after,
/// survives every app update. The only user-written store in the app.
///
/// Never add a "wipe and recreate on schema mismatch" escape hatch: this file is the
/// user's Journal, and dropping it to dodge a migration throws their life list away.
/// (The *catalog* is the disposable one, and it lives in a separate file precisely so
/// that stays true.)
nonisolated final class JournalDatabase: Sendable {

  static let fileName = "journal.db"

  let writer: any DatabaseWriter

  private init(writer: any DatabaseWriter) throws {
    self.writer = writer
    try Self.migrator.migrate(writer)
  }

  func journalStore() -> JournalStore {
    JournalStore(writer: writer)
  }

  /// Opens (creating on first call) the on-disk journal.
  ///
  /// `DatabasePool` rather than `DatabaseQueue` because it runs the file in WAL mode,
  /// which is what lets capture-thread writes proceed without blocking Journal reads. (The
  /// "one clean checkpointed file" rule constrains the shipped *catalog*, not this one.)
  static func open(at url: URL? = nil) throws -> JournalDatabase {
    let fileURL = try url ?? defaultURL()
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    return try JournalDatabase(writer: DatabasePool(path: fileURL.path, configuration: configuration()))
  }

  /// Ephemeral journal for tests. Same schema, same migrations, no file.
  static func openInMemory() throws -> JournalDatabase {
    try JournalDatabase(writer: DatabaseQueue(configuration: configuration()))
  }

  /// Application Support, not Documents — captures are Journal content the app owns,
  /// not files the user browses.
  static func defaultURL() throws -> URL {
    try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent(fileName)
  }

  private static func configuration() -> Configuration {
    var config = Configuration()
    // Enforced within a file. The one cross-file reference, `Sighting.speciesId`,
    // is deliberately not a foreign key.
    config.foreignKeysEnabled = true
    return config
  }

  /// Migrations, oldest first. Every step added here needs its matching numbered step in the
  /// exported schema.
  ///
  /// The DDL is transcribed from that exported schema rather than expressed through GRDB's
  /// table builder, so the two can be diffed literally and any drift shows up as a text
  /// difference instead of a runtime surprise.
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1") { db in
      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `Sighting` (
              `id` TEXT NOT NULL,
              `speciesId` TEXT,
              `method` TEXT NOT NULL,
              `source` TEXT NOT NULL,
              `status` TEXT NOT NULL,
              `confidence` REAL,
              `gazeContext` TEXT,
              `bearingDeg` REAL,
              `latitude` REAL,
              `longitude` REAL,
              `placeName` TEXT,
              `notes` TEXT,
              `spottedAt` INTEGER NOT NULL,
              `createdAt` INTEGER NOT NULL,
              `updatedAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`)
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_spottedAt`
          ON `Sighting` (`spottedAt` DESC)
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_speciesId`
          ON `Sighting` (`speciesId`)
          """)

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `SightingMedia` (
              `id` TEXT NOT NULL,
              `sightingId` TEXT NOT NULL,
              `type` TEXT NOT NULL,
              `filePath` TEXT NOT NULL,
              `width` INTEGER,
              `height` INTEGER,
              `durationMs` INTEGER,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`sightingId`) REFERENCES `Sighting`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_SightingMedia_sightingId`
          ON `SightingMedia` (`sightingId`)
          """)
    }

    // v1 → v2: the outing reshape.
    //
    // Drop-and-recreate rather than a data-carrying migration, deliberately: no build
    // has left this machine pair, so the v1 one-row-per-flow schema has no installed
    // base to carry — only dev-device files. The "migrated in place forever" covenant
    // starts at the first external build; from then on it is additive migrations only.
    migrator.registerMigration("v2") { db in
      try db.execute(sql: "DROP TABLE IF EXISTS `SightingMedia`")
      try db.execute(sql: "DROP TABLE IF EXISTS `Sighting`")

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `Outing` (
              `id` TEXT NOT NULL,
              `kind` TEXT NOT NULL,
              `status` TEXT NOT NULL,
              `startedAt` INTEGER NOT NULL,
              `durationMs` INTEGER,
              `latitude` REAL,
              `longitude` REAL,
              `placeName` TEXT,
              `notes` TEXT,
              `createdAt` INTEGER NOT NULL,
              `updatedAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`)
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Outing_startedAt`
          ON `Outing` (`startedAt` DESC)
          """)

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `OutingMedia` (
              `id` TEXT NOT NULL,
              `outingId` TEXT NOT NULL,
              `type` TEXT NOT NULL,
              `source` TEXT NOT NULL,
              `offsetMs` INTEGER,
              `filePath` TEXT NOT NULL,
              `width` INTEGER,
              `height` INTEGER,
              `durationMs` INTEGER,
              `gazeContext` TEXT,
              `bearingDeg` REAL,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`outingId`) REFERENCES `Outing`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_OutingMedia_outingId`
          ON `OutingMedia` (`outingId`)
          """)

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `OutingEvent` (
              `id` TEXT NOT NULL,
              `outingId` TEXT NOT NULL,
              `type` TEXT NOT NULL,
              `offsetMs` INTEGER,
              `speciesId` TEXT,
              `confidence` REAL,
              `question` TEXT,
              `answer` TEXT,
              `trait` TEXT,
              `value` TEXT,
              `gazeContext` TEXT,
              `bearingDeg` REAL,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`outingId`) REFERENCES `Outing`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_OutingEvent_outingId`
          ON `OutingEvent` (`outingId`)
          """)

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `Sighting` (
              `id` TEXT NOT NULL,
              `outingId` TEXT NOT NULL,
              `speciesId` TEXT NOT NULL,
              `confidence` REAL,
              `offsetMs` INTEGER,
              `gazeContext` TEXT,
              `bearingDeg` REAL,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`outingId`) REFERENCES `Outing`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE
          )
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_outingId`
          ON `Sighting` (`outingId`)
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_speciesId`
          ON `Sighting` (`speciesId`)
          """)
    }

    // v2 → v3: `Outing.status` is gone.
    //
    // An outing is now written only at Save, so every row in this table is a finished
    // one and the column had no second value left to hold. SQLite before 3.35 cannot
    // `DROP COLUMN`, and the iOS floor here is below that, so this is the standard
    // twelve-step rewrite: build the new table, carry the rows worth carrying, swap.
    //
    // Any `DRAFT` row is dropped rather than promoted. Under the old model a draft was
    // an outing the user never kept — a crash, or a rehearsal — and inventing a Save
    // they never performed would put entries in their Journal that they did not make.
    migrator.registerMigration("v3") { db in
      // Children go by hand, not by cascade: a migration runs with `foreign_keys`
      // off so a table can be rewritten, which is exactly when `ON DELETE CASCADE`
      // stops firing. (GRDB defers the check to the end of the step, as Room does.)
      for table in ["OutingMedia", "OutingEvent", "Sighting"] {
        try db.execute(
          sql: """
            DELETE FROM `\(table)` WHERE `outingId` IN
            (SELECT `id` FROM `Outing` WHERE `status` = 'DRAFT')
            """)
      }
      try db.execute(sql: "DELETE FROM `Outing` WHERE `status` = 'DRAFT'")
      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `Outing_new` (
              `id` TEXT NOT NULL,
              `kind` TEXT NOT NULL,
              `startedAt` INTEGER NOT NULL,
              `durationMs` INTEGER,
              `latitude` REAL,
              `longitude` REAL,
              `placeName` TEXT,
              `notes` TEXT,
              `createdAt` INTEGER NOT NULL,
              `updatedAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`)
          )
          """)
      try db.execute(
        sql: """
          INSERT INTO `Outing_new` (`id`, `kind`, `startedAt`, `durationMs`, `latitude`,
              `longitude`, `placeName`, `notes`, `createdAt`, `updatedAt`)
          SELECT `id`, `kind`, `startedAt`, `durationMs`, `latitude`, `longitude`,
              `placeName`, `notes`, `createdAt`, `updatedAt` FROM `Outing`
          """)
      try db.execute(sql: "DROP TABLE `Outing`")
      try db.execute(sql: "ALTER TABLE `Outing_new` RENAME TO `Outing`")
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Outing_startedAt`
          ON `Outing` (`startedAt` DESC)
          """)
    }

    // v3 → v4: `GazeContext` widens from three strata to five.
    //
    // `GROUND` and `CANOPY` keep their spellings and their meanings. `LEVEL` becomes
    // `HORIZON` — the same stratum under the name the live session's chip has always
    // used for it — so stored rows are rewritten rather than left holding a token the
    // enum no longer has a case for.
    //
    // No column changes: gaze is TEXT, and widening an enum only adds spellings that
    // were never written before. `UNDERSTORY` and `OVERHEAD` therefore appear on new
    // rows only, which is honest — a moment recorded under the old three had no way to
    // mean either one, and inferring one now would be inventing precision.
    migrator.registerMigration("v4") { db in
      for table in ["OutingMedia", "OutingEvent", "Sighting"] {
        try db.execute(
          sql: """
            UPDATE `\(table)` SET `gazeContext` = 'HORIZON' WHERE `gazeContext` = 'LEVEL'
            """)
      }
    }

    // v4 → v5: the evidence links.
    //
    // `OutingEvent` gains `mediaId` — the photo a detection was made by looking at —
    // and loses gaze and bearing, which are facts about an aimed camera and belong to
    // that photo. `Sighting` gains `sourceEventId` and loses `confidence`, `offsetMs`,
    // gaze and bearing for the same reason: it now says who was confirmed and what
    // backs it, and reads the rest through the link.
    //
    // Both tables are rewritten rather than altered — SQLite before 3.35 has no
    // `DROP COLUMN` and the iOS floor is below that. `OutingEvent` goes first, so that
    // `Sighting`'s new foreign key has a table to point at.
    //
    // **Existing rows get null links.** Which photo a detection came from is new
    // information; picking the nearest by `offsetMs` would be manufacturing a
    // provenance the app never observed. The values dropped along the way are the ones
    // this change exists to stop writing — an unattributed `Sighting.confidence` most
    // of all — and in practice the dev journals hold none, since the only path that
    // saves a sighting today is the wizard, which has no detection to copy from.
    migrator.registerMigration("v5") { db in
      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `OutingEvent_new` (
              `id` TEXT NOT NULL,
              `outingId` TEXT NOT NULL,
              `mediaId` TEXT,
              `type` TEXT NOT NULL,
              `offsetMs` INTEGER,
              `speciesId` TEXT,
              `confidence` REAL,
              `question` TEXT,
              `answer` TEXT,
              `trait` TEXT,
              `value` TEXT,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`outingId`) REFERENCES `Outing`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE,
              FOREIGN KEY(`mediaId`) REFERENCES `OutingMedia`(`id`)
                  ON UPDATE NO ACTION ON DELETE SET NULL
          )
          """)
      try db.execute(
        sql: """
          INSERT INTO `OutingEvent_new` (`id`, `outingId`, `type`, `offsetMs`,
              `speciesId`, `confidence`, `question`, `answer`, `trait`, `value`, `createdAt`)
          SELECT `id`, `outingId`, `type`, `offsetMs`, `speciesId`, `confidence`,
              `question`, `answer`, `trait`, `value`, `createdAt` FROM `OutingEvent`
          """)
      try db.execute(sql: "DROP TABLE `OutingEvent`")
      try db.execute(sql: "ALTER TABLE `OutingEvent_new` RENAME TO `OutingEvent`")
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_OutingEvent_outingId`
          ON `OutingEvent` (`outingId`)
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_OutingEvent_mediaId`
          ON `OutingEvent` (`mediaId`)
          """)

      try db.execute(
        sql: """
          CREATE TABLE IF NOT EXISTS `Sighting_new` (
              `id` TEXT NOT NULL,
              `outingId` TEXT NOT NULL,
              `sourceEventId` TEXT,
              `speciesId` TEXT NOT NULL,
              `createdAt` INTEGER NOT NULL,
              PRIMARY KEY(`id`),
              FOREIGN KEY(`outingId`) REFERENCES `Outing`(`id`)
                  ON UPDATE NO ACTION ON DELETE CASCADE,
              FOREIGN KEY(`sourceEventId`) REFERENCES `OutingEvent`(`id`)
                  ON UPDATE NO ACTION ON DELETE SET NULL
          )
          """)
      try db.execute(
        sql: """
          INSERT INTO `Sighting_new` (`id`, `outingId`, `speciesId`, `createdAt`)
          SELECT `id`, `outingId`, `speciesId`, `createdAt` FROM `Sighting`
          """)
      try db.execute(sql: "DROP TABLE `Sighting`")
      try db.execute(sql: "ALTER TABLE `Sighting_new` RENAME TO `Sighting`")
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_outingId`
          ON `Sighting` (`outingId`)
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_speciesId`
          ON `Sighting` (`speciesId`)
          """)
      try db.execute(
        sql: """
          CREATE INDEX IF NOT EXISTS `index_Sighting_sourceEventId`
          ON `Sighting` (`sourceEventId`)
          """)
    }

    return migrator
  }
}
