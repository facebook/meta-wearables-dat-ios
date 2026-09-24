/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LocalJournalRepository.swift
//  birdspotter
//

import Foundation

/// The only implementation of ``JournalRepository``: `journal.db` for rows,
/// ``MediaFileStore`` for bytes, and the ordering between them.
///
/// `now` and `newId` are injected so tests can pin both. Everything else is the two data
/// sources — this type holds no state of its own.
///
/// `newId` mints the outing's id and nothing else: every child arrived carrying the id it was
/// born with, because a detection points at its photo while both are still in memory. A
/// sighting that names an event the draft doesn't hold therefore fails the foreign key on
/// insert, which is the right noise for a caller that wired the draft up wrong.
nonisolated struct LocalJournalRepository: JournalRepository {

  private let store: JournalStore
  private let mediaFileStore: MediaFileStore
  private let now: @Sendable () -> Int64
  private let newId: @Sendable () -> String

  init(
    store: JournalStore,
    mediaFileStore: MediaFileStore,
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    self.store = store
    self.mediaFileStore = mediaFileStore
    self.now = now
    self.newId = newId
  }

  // MARK: - Observation

  func journalStream() -> AsyncThrowingStream<[OutingWithChildren], Error> {
    store.journalStream()
  }

  func lifeListCountStream() -> AsyncThrowingStream<Int, Error> {
    store.lifeListCountStream()
  }

  func findById(_ outingId: String) async throws -> OutingWithChildren? {
    try await store.findById(outingId)
  }

  // MARK: - Save

  func saveOuting(_ draft: OutingDraft) async throws -> String {
    let outingId = newId()
    let timestamp = now()

    // Bytes down first, so no row can ever point at a file that isn't there. Written
    // under the outing's own group, which is what makes delete a single sweep later.
    var written: [OutingMedia] = []
    do {
      for pending in draft.media {
        // The draft minted this id when the capture happened, and anything that
        // points at this photo is already holding it — so it is written through
        // rather than replaced here.
        let filePath = try await mediaFileStore.write(
          pending.bytes,
          group: outingId,
          name: pending.id,
          fileExtension: pending.fileExtension
        )
        written.append(
          OutingMedia(
            id: pending.id,
            outingId: outingId,
            type: pending.type,
            source: pending.source,
            offsetMs: pending.offsetMs,
            filePath: filePath,
            width: pending.width,
            height: pending.height,
            durationMs: pending.durationMs,
            gazeContext: pending.moment.gazeContext,
            bearingDeg: pending.moment.bearingDeg.map(normalizeBearing),
            createdAt: timestamp
          )
        )
      }
    } catch {
      // Best-effort sweep of whatever landed before the failure: a save that did not
      // happen must not leave bytes behind that nothing will ever reference.
      try? await mediaFileStore.deleteGroup(outingId)
      throw JournalError.mediaWriteFailed(outingId: outingId)
    }

    // The strip, beside the audio it was measured from. `try?` and no row: it is derived,
    // and an outing that saved its recording but not its picture of it is a good outing —
    // the journal page recomputes, exactly as it did before this file existed. Failing the
    // save here would throw away a walk over a cache.
    if let sonogram = draft.sonogram {
      _ = try? await mediaFileStore.write(
        sonogram,
        group: outingId,
        name: MediaFileStore.sonogramName,
        fileExtension: MediaFileStore.sonogramExtension
      )
    }

    let outing = Outing(
      id: outingId,
      kind: draft.kind,
      startedAt: draft.startedAt,
      durationMs: draft.durationMs,
      latitude: draft.location.latitude,
      longitude: draft.location.longitude,
      notes: draft.notes,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    let events = draft.events.map { pending in
      OutingEvent(
        id: pending.id,
        outingId: outingId,
        mediaId: pending.mediaId,
        type: pending.type,
        offsetMs: pending.offsetMs,
        speciesId: pending.speciesId,
        confidence: pending.confidence,
        question: pending.question,
        answer: pending.answer,
        trait: pending.trait,
        value: pending.value,
        createdAt: timestamp
      )
    }
    let sightings = draft.sightings.map { pending in
      Sighting(
        id: pending.id,
        outingId: outingId,
        sourceEventId: pending.confirming?.id,
        speciesId: pending.speciesId,
        createdAt: timestamp
      )
    }

    do {
      try await store.insertOuting(outing, media: written, events: events, sightings: sightings)
    } catch {
      try? await mediaFileStore.deleteGroup(outingId)
      throw JournalError.mediaWriteFailed(outingId: outingId)
    }
    return outingId
  }

  // MARK: - Mutation

  func updateNotes(outingId: String, notes: String?) async throws {
    // Read, modify, write — with `Outing.updatedAt` bumped in code, never by a trigger.
    guard let current = try await store.findById(outingId)?.outing else {
      throw JournalError.notFound(outingId: outingId)
    }
    var updated = current
    updated.notes = notes
    updated.updatedAt = now()
    try await store.update(updated)
  }

  func delete(outingId: String) async throws {
    // Files first, then the row. Reversed, a crash between the two steps would strand
    // files on disk that nothing references and nothing will ever clean up.
    try await mediaFileStore.deleteGroup(outingId)
    try await store.deleteById(outingId)
  }

  func deleteAll() async throws {
    // Files first, then the rows — the same asymmetry, and one sweep of the media
    // directory rather than a group per outing, which also collects bytes from a
    // capture that never became a row.
    try await mediaFileStore.deleteAll()
    try await store.deleteAll()
  }
}

/// Folds a heading into 0–360. Bearings are stored true north and normalized at write, so
/// nothing downstream has to wonder whether -90 means 270.
private nonisolated func normalizeBearing(_ degrees: Double) -> Double {
  (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
}
