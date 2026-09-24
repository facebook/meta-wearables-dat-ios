/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalStore.swift
//  birdspotter
//

import Foundation
import GRDB

/// Every query against `journal.db`. Rows only — this layer never touches the
/// filesystem; pairing a row with its file is ``LocalJournalRepository``'s job.
nonisolated struct JournalStore: Sendable {

  let writer: any DatabaseWriter

  // MARK: - Observation

  /// The Journal: every outing, newest first.
  ///
  /// Unfiltered on purpose. An outing reaches this table only at Save, so there is no
  /// such thing as an unfinished row to exclude.
  func journalStream() -> AsyncThrowingStream<[OutingWithChildren], Error> {
    observe { db in
      try Self.fetchWithChildren(
        db,
        sql: "SELECT * FROM Outing ORDER BY startedAt DESC"
      )
    }
  }

  /// "12 species spotted" — derived on every read, never stored.
  func lifeListCountStream() -> AsyncThrowingStream<Int, Error> {
    observe { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT speciesId) FROM Sighting") ?? 0
    }
  }

  // MARK: - Reads

  func findById(_ id: String) async throws -> OutingWithChildren? {
    try await writer.read { db in
      try Self.fetchWithChildren(db, sql: "SELECT * FROM Outing WHERE id = ?", arguments: [id]).first
    }
  }

  // MARK: - Writes

  func insert(_ outing: Outing) async throws {
    try await writer.write { db in try outing.insert(db) }
  }

  func update(_ outing: Outing) async throws {
    try await writer.write { db in try outing.update(db) }
  }

  func insertMedia(_ media: [OutingMedia]) async throws {
    try await writer.write { db in for row in media { try row.insert(db) } }
  }

  func insertEvent(_ events: [OutingEvent]) async throws {
    try await writer.write { db in for row in events { try row.insert(db) } }
  }

  func insertSighting(_ sightings: [Sighting]) async throws {
    try await writer.write { db in for row in sightings { try row.insert(db) } }
  }

  /// A whole outing in one transaction — the only way an outing enters the Journal.
  ///
  /// Atomic because a half-written outing is exactly what dropping the status column
  /// removed the ability to describe: with no `DRAFT` to park it in, a partial insert
  /// would surface in the Journal as a real entry missing its birds. Either the entry
  /// exists complete or it was never here.
  ///
  /// One `write` block is one transaction — GRDB commits it whole or rolls it back on
  /// the first throw, which is what Room's `@Transaction` buys on the other side.
  func insertOuting(
    _ outing: Outing,
    media: [OutingMedia],
    events: [OutingEvent],
    sightings: [Sighting]
  ) async throws {
    try await writer.write { db in
      try outing.insert(db)
      for row in media { try row.insert(db) }
      for row in events { try row.insert(db) }
      for row in sightings { try row.insert(db) }
    }
  }

  /// Child rows go with it via `ON DELETE CASCADE`; the files do not.
  func deleteById(_ id: String) async throws {
    _ = try await writer.write { db in try Outing.deleteOne(db, key: id) }
  }

  /// Every outing at once. Children cascade with them; the files do not.
  func deleteAll() async throws {
    _ = try await writer.write { db in try Outing.deleteAll(db) }
  }

  // MARK: - Internals

  /// Outings plus their children in four statements, then grouped in memory.
  ///
  /// Deliberately not a GRDB association: the shape has to match Room's `@Relation`
  /// output exactly, and plain statements make that correspondence obvious in a way
  /// that hasMany/`including(all:)` decoding does not.
  private static func fetchWithChildren(
    _ db: Database,
    sql: String,
    arguments: StatementArguments = []
  ) throws -> [OutingWithChildren] {
    let outings = try Outing.fetchAll(db, sql: sql, arguments: arguments)
    guard !outings.isEmpty else { return [] }

    let ids = outings.map(\.id)
    let marks = databaseQuestionMarks(count: ids.count)
    let media = try OutingMedia.fetchAll(
      db,
      sql: "SELECT * FROM OutingMedia WHERE outingId IN (\(marks))",
      arguments: StatementArguments(ids)
    )
    let events = try OutingEvent.fetchAll(
      db,
      sql: "SELECT * FROM OutingEvent WHERE outingId IN (\(marks))",
      arguments: StatementArguments(ids)
    )
    let sightings = try Sighting.fetchAll(
      db,
      sql: "SELECT * FROM Sighting WHERE outingId IN (\(marks))",
      arguments: StatementArguments(ids)
    )
    let mediaByOuting = Dictionary(grouping: media, by: \.outingId)
    let eventsByOuting = Dictionary(grouping: events, by: \.outingId)
    let sightingsByOuting = Dictionary(grouping: sightings, by: \.outingId)

    return outings.map { outing in
      OutingWithChildren(
        outing: outing,
        media: mediaByOuting[outing.id] ?? [],
        events: eventsByOuting[outing.id] ?? [],
        sightings: sightingsByOuting[outing.id] ?? []
      )
    }
  }

  /// Bridges a GRDB `ValueObservation` to the `AsyncThrowingStream` the repository
  /// surface uses everywhere, so the domain layer never names a GRDB type.
  ///
  /// Observation starts when the stream is created and stops when iteration ends or
  /// the consuming task is cancelled.
  private func observe<T: Sendable>(
    _ fetch: @escaping @Sendable (Database) throws -> T
  ) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
      let observation = ValueObservation.tracking(fetch)
      let task = Task {
        do {
          for try await value in observation.values(in: writer) {
            continuation.yield(value)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
