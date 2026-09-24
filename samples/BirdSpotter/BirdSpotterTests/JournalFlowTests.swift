/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalFlowTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The Journal's end-to-end flows, through the real store: an outing reaches the Journal,
/// opens with everything the detail screen reads, and deleting it takes the rows and files
/// back out.
///
/// Repository-level rather than screen-driven on purpose. The live spine is the draft the
/// recording flow will hand over at Save — segments and detections pinned to a timeline; the
/// wizard spine is the exact draft `IdentifyWizardViewModel.saveSighting` builds today.
/// Driving those against a real ``LocalJournalRepository`` over `journal.db` and a temp media
/// directory tests the flow's spine without a simulator, where the screens' own logic is
/// covered by `JournalViewModelTests`.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("JournalFlow")
struct JournalFlowTests {

  private let database: JournalDatabase
  private let mediaRoot: URL
  private let mediaFileStore: MediaFileStore
  private let repository: any JournalRepository

  init() throws {
    database = try JournalDatabase.openInMemory()
    mediaRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("birdspotter-flow-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
    mediaFileStore = MediaFileStore(rootURL: mediaRoot)
    repository = LocalJournalRepository(
      store: database.journalStore(),
      mediaFileStore: mediaFileStore
    )
  }

  @Test func journalFlow_outingAppearsOpensAndDeletes() async throws {
    // The live spine: a walk's worth of capture, assembled in memory, saved in one call.
    let heard = PendingEvent.heard(
      speciesId: "american-robin",
      confidence: 0.87,
      offsetMs: 12_000
    )
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .live,
        startedAt: 500,
        durationMs: 30_000,
        location: somewhere,
        media: [
          PendingMedia(
            type: .audio,
            source: .glasses,
            bytes: Data([0x1, 0x2]),
            fileExtension: "wav",
            offsetMs: 0,
            durationMs: 5_000
          ),
          PendingMedia(
            type: .photo,
            source: .glasses,
            bytes: Data([0x3, 0x4, 0x5]),
            fileExtension: "jpg",
            offsetMs: 21_000,
            width: 120,
            height: 90
          ),
        ],
        events: [heard],
        sightings: [PendingSighting(speciesId: "american-robin", confirming: heard)]
      )
    )

    // Journal — the one outing, its species counted on the life list.
    #expect(try await journal().map(\.outing.id) == [id])
    #expect(try await firstValue(repository.lifeListCountStream()) == 1)

    // Detail — what the entry page loads: the root, the confirmed bird, both files, the pin.
    let opened = try #require(try await repository.findById(id))
    #expect(opened.outing.durationMs == 30_000)
    #expect(opened.sightings.first?.speciesId == "american-robin")
    #expect(opened.photos.count == 1)
    #expect(opened.audio.count == 1)
    #expect(opened.events.first?.type == .detection)

    // Delete — the rows leave the journal and the files leave the disk.
    let paths = opened.media.map(\.filePath)
    try await repository.delete(outingId: id)
    #expect(try await repository.findById(id) == nil)
    for path in paths { #expect(!(await mediaFileStore.exists(path))) }
    #expect(try await journal().isEmpty)
    #expect(try await firstValue(repository.lifeListCountStream()) == 0)
  }

  @Test func journalFlow_wizardEntryLandsInOneBreath() async throws {
    // The exact draft `IdentifyWizardViewModel.saveSighting` builds on "This is my bird".
    let id = try await repository.saveOuting(
      OutingDraft(
        kind: .manual,
        startedAt: 500,
        location: somewhere,
        events: [
          PendingEvent.wizardAnswer(trait: .size, value: "2"),
          PendingEvent.wizardAnswer(trait: .colors, value: "BLACK,RED"),
          PendingEvent.wizardAnswer(trait: .behavior, value: "IN_TREES_OR_BUSHES"),
        ],
        sightings: [PendingSighting(speciesId: "northern-cardinal")]
      )
    )

    let opened = try #require(try await repository.findById(id))
    #expect(opened.outing.kind == .manual)
    // No clock: a wizard entry has no duration and nothing pinned to a timeline.
    #expect(opened.outing.durationMs == nil)
    #expect(opened.media.isEmpty)
    #expect(opened.sightings.count == 1)
    #expect(opened.sightings.first?.speciesId == "northern-cardinal")
    // Nothing detected this bird — the watcher named it — so there is no evidence to cite.
    #expect(opened.sightings.first?.sourceEventId == nil)
    #expect(opened.confidence(of: try #require(opened.sightings.first)) == nil)

    let answers = opened.events
      .filter { $0.type == .wizardAnswer }
      .sorted { traitIndex($0.trait) < traitIndex($1.trait) }
    #expect(answers.map(\.value) == ["2", "BLACK,RED", "IN_TREES_OR_BUSHES"])

    #expect(try await firstValue(repository.lifeListCountStream()) == 1)
  }

  // MARK: - Helpers

  private func journal() async throws -> [OutingWithChildren] {
    try await firstValue(repository.journalStream())
  }

  /// The current value of an observation — the first element the stream yields.
  private func firstValue<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> T {
    var iterator = stream.makeAsyncIterator()
    guard let value = try await iterator.next() else {
      throw FlowTestFailure.streamFinishedWithoutValue
    }
    return value
  }

  private func traitIndex(_ trait: WizardTrait?) -> Int {
    guard let trait else { return .max }
    return WizardTrait.allCases.firstIndex(of: trait) ?? .max
  }
}

private enum FlowTestFailure: Error {
  case streamFinishedWithoutValue
}

/// Any fix will do where a test is not about location — an outing just cannot be without one.
private let somewhere = CaptureLocation(latitude: 39.2098, longitude: -84.4699)
