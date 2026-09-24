/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalRepositoryTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The journal storage stack end to end: `journal.db`, the media directory, and the
/// ordering the repository imposes between them — against the outing model.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("JournalRepository")
struct JournalRepositoryTests {

  private let database: JournalDatabase
  private let mediaRoot: URL
  private let mediaFileStore: MediaFileStore
  private let repository: any JournalRepository
  /// Pinned so `createdAt`/`updatedAt` assertions are exact rather than approximate.
  private let clock: MutableClock
  private let idCounter: Counter

  init() throws {
    database = try JournalDatabase.openInMemory()
    mediaRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("birdspotter-media-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
    mediaFileStore = MediaFileStore(rootURL: mediaRoot)

    let clock = MutableClock(1_000)
    let idCounter = Counter()
    self.clock = clock
    self.idCounter = idCounter
    repository = LocalJournalRepository(
      store: database.journalStore(),
      mediaFileStore: mediaFileStore,
      now: { clock.value },
      newId: { "id-\(idCounter.next())" }
    )
  }

  @Test func saveOuting_putsItStraightIntoTheJournal() async throws {
    let id = try await repository.saveOuting(OutingDraft(kind: .live, startedAt: 500, location: somewhere))

    #expect(try await journal().map(\.outing.id) == [id])
  }

  @Test func saveOuting_withNothingConfirmed_savesAnyway() async throws {
    // The Merlin case: a walk that heard no bird is still an outing worth keeping.
    let id = try await repository.saveOuting(
      OutingDraft(kind: .live, startedAt: 500, durationMs: 840_000, location: somewhere)
    )

    #expect(try await journal().map(\.outing.id) == [id])
    #expect(try await repository.findById(id)?.sightings.isEmpty == true)
    #expect(try await lifeListCount() == 0)
  }

  @Test func saveOuting_persistsConfirmedSightings() async throws {
    let heard = PendingEvent.heard(
      speciesId: "american-robin",
      confidence: 0.87,
      offsetMs: 12_000
    )
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        events: [heard],
        sightings: [PendingSighting(speciesId: "american-robin", confirming: heard)]
      )
    )

    let saved = try #require(try await repository.findById(id))
    let confirmed = try #require(saved.sightings.first)
    #expect(confirmed.speciesId == "american-robin")
    // The moment and the score are read down the link, not off the row.
    #expect(confirmed.sourceEventId == heard.id)
    #expect(saved.offset(of: confirmed) == 12_000)
    #expect(abs((saved.confidence(of: confirmed) ?? 0) - 0.87) < 1e-9)
  }

  @Test func saveOuting_withoutADetection_leavesTheSightingUnbacked() async throws {
    // The wizard's shape: a bird named by answering questions, with nothing to cite.
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .manual,
        startedAt: 500,
        location: somewhere,
        sightings: [PendingSighting(speciesId: "northern-cardinal")]
      )
    )

    let saved = try #require(try await repository.findById(id))
    let confirmed = try #require(saved.sightings.first)
    #expect(confirmed.sourceEventId == nil)
    #expect(saved.offset(of: confirmed) == nil)
    #expect(saved.confidence(of: confirmed) == nil)
  }

  @Test func saveOuting_confidenceIsNullWhenTheWatcherNamedAnotherBird() async throws {
    // The detector proposed a crow; the watcher looked at the photo and said Fish Crow.
    // 0.91 scored the label they rejected, so it is not this bird's confidence.
    let photo = PendingMedia(
      type: .photo,
      source: .glasses,
      bytes: Data([0x1]),
      fileExtension: "heic",
      offsetMs: 8_000
    )
    let proposed = PendingEvent.seen(
      speciesId: "american-crow",
      confidence: 0.91,
      inPhoto: photo
    )
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [photo],
        events: [proposed],
        sightings: [PendingSighting(speciesId: "fish-crow", confirming: proposed)]
      )
    )

    let saved = try #require(try await repository.findById(id))
    let confirmed = try #require(saved.sightings.first)
    #expect(saved.confidence(of: confirmed) == nil)
    // The link still holds, so the moment behind the confirmation is still readable.
    #expect(saved.offset(of: confirmed) == 8_000)
  }

  @Test func saveOuting_normalizesBearingToTrueNorthRange() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .photo,
            source: .phone,
            bytes: Data([0x1]),
            fileExtension: "jpg",
            offsetMs: 4_000,
            moment: MomentContext(bearingDeg: -90)
          )
        ]
      )
    )

    let bearing = try #require(try await repository.findById(id)?.media.first?.bearingDeg)
    #expect(abs(bearing - 270) < 1e-9)
  }

  @Test func saveOuting_writesPhotoFileThenRow() async throws {
    let bytes = Data([0x1, 0x2, 0x3, 0x4])

    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .photo,
            source: .glasses,
            bytes: bytes,
            fileExtension: "heic",
            offsetMs: 42_000,
            width: 4032,
            height: 3024,
            moment: MomentContext(gazeContext: .canopy)
          )
        ]
      )
    )

    let media = try #require(try await repository.findById(id)?.media.first)
    #expect(media.filePath == "\(id)/\(media.id).heic")
    #expect(await mediaFileStore.exists(media.filePath))
    #expect(try Data(contentsOf: mediaFileStore.resolve(media.filePath)) == bytes)
    #expect(media.offsetMs == 42_000)
    #expect(media.source == .glasses)
    #expect(media.gazeContext == .canopy)
  }

  @Test func saveOuting_recordsAudioDurationAndNoDimensions() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .audio,
            source: .glasses,
            bytes: Data([0x9]),
            fileExtension: "wav",
            offsetMs: 5_000,
            durationMs: 10_000
          )
        ]
      )
    )

    let media = try #require(try await repository.findById(id)?.media.first)
    #expect(media.type == .audio)
    #expect(media.durationMs == 10_000)
    #expect(media.width == nil)
    #expect(media.height == nil)
  }

  @Test func saveOuting_keepsAudioSegmentsAsSeparateRows() async throws {
    // Two microphones across one unbroken session — the handover is the two rows.
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .audio,
            source: .glasses,
            bytes: Data([0x1]),
            fileExtension: "wav",
            offsetMs: 0,
            durationMs: 30_000
          ),
          PendingMedia(
            type: .audio,
            source: .phone,
            bytes: Data([0x2]),
            fileExtension: "wav",
            offsetMs: 30_000,
            durationMs: 15_000
          ),
        ]
      )
    )

    let segments = try #require(try await repository.findById(id)?.media)
      .sorted { ($0.offsetMs ?? 0) < ($1.offsetMs ?? 0) }
    #expect(segments.map(\.source) == [.glasses, .phone])
    // Distinct files, so one row can never hold two microphones.
    #expect(Set(segments.map(\.filePath)).count == 2)
  }

  @Test func saveOuting_whenMediaWriteFails_leavesNothingBehind() async throws {
    // A root that is a file, not a directory: every write under it fails.
    let blocked = mediaRoot.appendingPathComponent("blocked")
    try Data([0x0]).write(to: blocked)
    let failing = LocalJournalRepository(
      store: database.journalStore(),
      mediaFileStore: MediaFileStore(rootURL: blocked),
      now: { [clock] in clock.value },
      newId: { [idCounter] in "id-\(idCounter.next())" }
    )

    await #expect(throws: JournalError.self) {
      _ = try await failing.saveOuting(
        OutingDraft(
          kind: .live,
          startedAt: 500,
          location: somewhere,
          media: [
            PendingMedia(
              type: .photo,
              source: .phone,
              bytes: Data([0x1]),
              fileExtension: "jpg"
            )
          ]
        )
      )
    }

    // No row, and nothing half-written: the Journal is exactly as it was.
    #expect(try await journal().isEmpty)
  }

  @Test func saveOuting_persistsWizardAnswers() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .manual,
        startedAt: 500,
        location: somewhere,
        events: [
          PendingEvent.wizardAnswer(trait: .size, value: "4"),
          PendingEvent.wizardAnswer(trait: .colors, value: "BLACK,RED"),
          PendingEvent.wizardAnswer(trait: .behavior, value: "AT_FEEDER"),
        ]
      )
    )

    let events = try #require(try await repository.findById(id)?.events)
    let answers =
      events
      .filter { $0.type == .wizardAnswer }
      .sorted { traitIndex($0.trait) < traitIndex($1.trait) }
    #expect(answers.map(\.trait) == [.size, .colors, .behavior])
    #expect(answers.map(\.value) == ["4", "BLACK,RED", "AT_FEEDER"])
    // A wizard answer has no clock to pin to.
    #expect(answers.allSatisfy { $0.offsetMs == nil })
  }

  @Test func saveOuting_persistsAHeardDetectionAgainstTheClock() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        events: [
          PendingEvent.heard(
            speciesId: "american-robin",
            confidence: 0.87,
            offsetMs: 21_000
          )
        ]
      )
    )

    let saved = try #require(try await repository.findById(id))
    let event = try #require(saved.events.first)
    #expect(event.type == .detection)
    #expect(event.speciesId == "american-robin")
    #expect(abs((event.confidence ?? 0) - 0.87) < 1e-9)
    #expect(event.offsetMs == 21_000)
    // Nothing aimed a camera, so there is no photo to reach and no aim to report.
    #expect(event.mediaId == nil)
    #expect(saved.moment(of: event).gazeContext == nil)
    #expect(saved.moment(of: event).bearingDeg == nil)
  }

  @Test func saveOuting_pinsASeenDetectionToItsPhotoRatherThanTheClock() async throws {
    let photo = PendingMedia(
      type: .photo,
      source: .glasses,
      bytes: Data([0x1]),
      fileExtension: "heic",
      offsetMs: 21_000,
      moment: MomentContext(gazeContext: .canopy, bearingDeg: 292)
    )
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [photo],
        events: [
          PendingEvent.seen(
            speciesId: "american-robin",
            confidence: 0.87,
            inPhoto: photo
          )
        ]
      )
    )

    let saved = try #require(try await repository.findById(id))
    let event = try #require(saved.events.first)
    #expect(event.mediaId == photo.id)
    // The photo owns the moment; the event stores no copy of any of it.
    #expect(event.offsetMs == nil)
    #expect(saved.offset(of: event) == 21_000)
    #expect(saved.moment(of: event).gazeContext == .canopy)
    #expect(abs((saved.moment(of: event).bearingDeg ?? 0) - 292) < 1e-9)
  }

  @Test func saveOuting_persistsExchangeQuestionAndAnswer() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        events: [
          PendingEvent.exchange(
            question: "It's green with a yellow belly",
            answer: "That's likely a Green Jay",
            offsetMs: 65_000
          )
        ]
      )
    )

    let event = try #require(try await repository.findById(id)?.events.first)
    #expect(event.type == .qa)
    #expect(event.question == "It's green with a yellow belly")
    #expect(event.answer == "That's likely a Green Jay")
  }

  @Test func saveOuting_stampsTheDurationItWasGiven() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(kind: .live, startedAt: 500, durationMs: 90_000, location: somewhere)
    )

    #expect(try await repository.findById(id)?.outing.durationMs == 90_000)
  }

  @Test func saveOuting_leavesManualDurationNull() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .manual,
        startedAt: 500,
        location: somewhere,
        events: [PendingEvent.wizardAnswer(trait: .size, value: "2")],
        sightings: [PendingSighting(speciesId: "northern-cardinal")]
      )
    )

    #expect(try await repository.findById(id)?.outing.durationMs == nil)
  }

  @Test func saveOuting_stampsTimestampsWithoutTouchingStartedAt() async throws {
    clock.value = 2_000

    let id = try await repository.saveOuting(OutingDraft(kind: .live, startedAt: 500, location: somewhere))

    let saved = try #require(try await repository.findById(id)?.outing)
    // startedAt is capture time and may predate createdAt when a transfer lags.
    #expect(saved.startedAt == 500)
    #expect(saved.createdAt == 2_000)
    #expect(saved.updatedAt == 2_000)
  }

  @Test func updateNotes_bumpsUpdatedAtButNotStartedAt() async throws {
    let id = try await repository.saveOuting(OutingDraft(kind: .live, startedAt: 500, location: somewhere))

    clock.value = 2_000
    try await repository.updateNotes(outingId: id, notes: "Loud dawn chorus by the creek")

    let updated = try #require(try await repository.findById(id)?.outing)
    #expect(updated.notes == "Loud dawn chorus by the creek")
    #expect(updated.startedAt == 500)
    #expect(updated.createdAt == 1_000)
    #expect(updated.updatedAt == 2_000)
  }

  @Test func updateNotes_whenOutingUnknown_throwsNotFound() async throws {
    await #expect(throws: JournalError.notFound(outingId: "no-such-outing")) {
      try await repository.updateNotes(outingId: "no-such-outing", notes: "anything")
    }
  }

  @Test func delete_removesFilesAndRow() async throws {
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .photo,
            source: .glasses,
            bytes: Data([0x1]),
            fileExtension: "jpg",
            offsetMs: 1_000,
            width: 100,
            height: 100
          ),
          PendingMedia(
            type: .audio,
            source: .glasses,
            bytes: Data([0x2]),
            fileExtension: "wav",
            offsetMs: 0,
            durationMs: 3_000
          ),
        ],
        sightings: [
          PendingSighting(speciesId: "blue-jay")
        ]
      )
    )
    let paths = try #require(try await repository.findById(id)?.media.map(\.filePath))
    #expect(try await repository.findById(id) != nil)

    try await repository.delete(outingId: id)

    #expect(try await repository.findById(id) == nil)
    for path in paths { #expect(!(await mediaFileStore.exists(path))) }
    #expect(!FileManager.default.fileExists(atPath: mediaRoot.appendingPathComponent(id).path))
    #expect(try await journal().isEmpty)
    #expect(try await lifeListCount() == 0)
  }

  @Test func deleteAll_emptiesTheJournalAndItsMediaDirectory() async throws {
    // Settings' one destructive control: the whole Journal, not an entry of it.
    let withPhoto = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        location: somewhere,
        media: [
          PendingMedia(
            type: .photo,
            source: .glasses,
            bytes: Data([0x1]),
            fileExtension: "jpg",
            offsetMs: 1_000,
            width: 100,
            height: 100
          )
        ],
        sightings: [
          PendingSighting(speciesId: "blue-jay")
        ]
      )
    )
    try await savedOuting(startedAt: 900, speciesId: "northern-cardinal")
    let paths = try #require(try await repository.findById(withPhoto)?.media.map(\.filePath))

    try await repository.deleteAll()

    #expect(try await journal().isEmpty)
    #expect(try await lifeListCount() == 0)
    for path in paths { #expect(!(await mediaFileStore.exists(path))) }
    // Not one group swept but the whole directory — bytes from a capture that never
    // became a row have no id to look them up by, and this is what collects them.
    #expect(try FileManager.default.contentsOfDirectory(atPath: mediaRoot.path).isEmpty)
  }

  @Test func deleteAll_onAnEmptyJournal_succeeds() async throws {
    // The second confirmed tap, and the first one on a fresh install.
    try await repository.deleteAll()

    #expect(try await journal().isEmpty)
  }

  @Test func journal_ordersByStartedAtNewestFirst() async throws {
    let older = try await savedOuting(startedAt: 100)
    let newer = try await savedOuting(startedAt: 900)

    #expect(try await journal().map(\.outing.id) == [newer, older])
  }

  @Test func lifeListCount_countsDistinctSpecies_ignoringBirdless() async throws {
    try await savedOuting(startedAt: 100, speciesId: "northern-cardinal")
    try await savedOuting(startedAt: 200, speciesId: "northern-cardinal")
    try await savedOuting(startedAt: 300, speciesId: "blue-jay")
    // A birdless outing saves, but confirms nothing toward the life list.
    try await savedOuting(startedAt: 400)

    #expect(try await lifeListCount() == 2)
  }

  /// The other tests run against an in-memory database. This one uses the real file, so
  /// the on-disk path — WAL, and a migration replayed against an already-migrated
  /// file — is covered rather than assumed.
  @Test func open_onDisk_createsSchemaAndSurvivesReopen() async throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("birdspotter-journal-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let first = try JournalDatabase.open(at: fileURL)
    let id = try await LocalJournalRepository(
      store: first.journalStore(),
      mediaFileStore: mediaFileStore
    ).saveOuting(
      OutingDraft(
        kind: .manual,
        startedAt: 500,
        location: somewhere,
        events: [PendingEvent.wizardAnswer(trait: .size, value: "2")],
        sightings: [PendingSighting(speciesId: "northern-cardinal")]
      )
    )

    let second = try JournalDatabase.open(at: fileURL)
    let reading = LocalJournalRepository(store: second.journalStore(), mediaFileStore: mediaFileStore)
    let reopened = try #require(try await reading.findById(id))

    #expect(reopened.outing.kind == .manual)
    #expect(reopened.sightings.first?.speciesId == "northern-cardinal")
    #expect(reopened.events.first?.value == "2")
  }

  // MARK: - Helpers

  private func journal() async throws -> [OutingWithChildren] {
    try await firstValue(repository.journalStream())
  }

  private func lifeListCount() async throws -> Int {
    try await firstValue(repository.lifeListCountStream())
  }

  /// The current value of an observation — the first element the stream yields.
  private func firstValue<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> T {
    var iterator = stream.makeAsyncIterator()
    guard let value = try await iterator.next() else {
      throw TestFailure.streamFinishedWithoutValue
    }
    return value
  }

  private func traitIndex(_ trait: WizardTrait?) -> Int {
    guard let trait else { return .max }
    return WizardTrait.allCases.firstIndex(of: trait) ?? .max
  }

  @discardableResult
  private func savedOuting(startedAt: Int64, speciesId: String? = nil) async throws -> String {
    try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: startedAt,
        location: somewhere,
        sightings: speciesId.map { [PendingSighting(speciesId: $0)] } ?? []
      )
    )
  }
}

private enum TestFailure: Error {
  case streamFinishedWithoutValue
}

/// A clock the test moves by hand, so `updatedAt` assertions are exact.
private final class MutableClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Int64

  init(_ value: Int64) { storage = value }

  var value: Int64 {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}

/// Deterministic id source, so file paths in assertions are predictable.
private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

/// Any fix will do where a test is not about location — an outing just cannot be without one.
private let somewhere = CaptureLocation(latitude: 39.2098, longitude: -84.4699)
