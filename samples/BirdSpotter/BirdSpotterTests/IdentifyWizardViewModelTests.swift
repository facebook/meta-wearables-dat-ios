/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyWizardViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The wizard's save, which is the only path that writes a `manual` outing today.
///
/// The location cases are the point of this suite. ``Outing``'s coordinates are required, and the
/// Identify gate grants the *permission* rather than handing over a fix — so what the flow does
/// with no fix is a real branch, and it was briefly a silent no-op that looked exactly like a
/// broken button.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("IdentifyWizardViewModel")
@MainActor
struct IdentifyWizardViewModelTests {

  @Test func saveSighting_withAFix_writesTheOuting() async throws {
    let journal = RecordingJournal()
    let model = viewModel(journal, FakeWizardLocation(fixes: [Coordinate(latitude: 39.2098, longitude: -84.4699)]))
    await model.captureLocation()

    answerEverything(model)
    model.saveSighting("northern-cardinal")
    await settle(model)

    let draft = try #require(await journal.saved.first)
    #expect(abs(draft.location.latitude - 39.2098) < 1e-9)
    #expect(abs(draft.location.longitude - (-84.4699)) < 1e-9)
    #expect(model.uiState.savedSpeciesId == "northern-cardinal")
    #expect(model.uiState.saveError == nil)
  }

  @Test func saveSighting_withNoFixYet_asksAgainRatherThanGivingUp() async throws {
    // The screen's `captureLocation()` is still in flight when the user reaches Results —
    // the save asks for itself rather than failing on an empty ui state.
    let journal = RecordingJournal()
    let model = viewModel(journal, FakeWizardLocation(fixes: [Coordinate(latitude: 1, longitude: 2)]))

    answerEverything(model)
    model.saveSighting("northern-cardinal")
    await settle(model)

    let draft = try #require(await journal.saved.first)
    #expect(abs(draft.location.latitude - 1) < 1e-9)
  }

  @Test func saveSighting_withNoFixAtAll_savesNothingAndSaysSo() async throws {
    // The simulator with no location set, and the phone indoors at a venue. Nothing is
    // written — an outing cannot claim to be nowhere — but the failure has to reach the
    // screen, because a button that does nothing at all reads as a broken app.
    let journal = RecordingJournal()
    let model = viewModel(journal, FakeWizardLocation(fixes: [nil]))
    await model.captureLocation()

    answerEverything(model)
    model.saveSighting("northern-cardinal")
    await settle(model)

    #expect(await journal.saved.isEmpty)
    #expect(model.uiState.savedSpeciesId == nil)
    #expect(model.uiState.saveError == .noLocationFix)
    // And the button is live again, because asking once more is the whole remedy.
    #expect(model.uiState.savingSpeciesId == nil)
  }

  @Test func saveSighting_afterAFailedSave_clearsTheErrorOnTheNextTry() async throws {
    let journal = RecordingJournal()
    let model = viewModel(journal, FakeWizardLocation(fixes: [nil, Coordinate(latitude: 3, longitude: 4)]))

    answerEverything(model)
    model.saveSighting("northern-cardinal")
    await settle(model)
    #expect(model.uiState.saveError == .noLocationFix)

    model.saveSighting("northern-cardinal")
    await settle(model)

    #expect(model.uiState.saveError == nil)
    let draft = try #require(await journal.saved.first)
    #expect(abs(draft.location.latitude - 3) < 1e-9)
  }

  // MARK: - Helpers

  /// `saveSighting` is fire-and-forget, so wait for its `Task` to land rather than sleeping.
  private func settle(_ model: IdentifyWizardViewModel) async {
    while model.uiState.savingSpeciesId != nil {
      await Task.yield()
    }
  }

  private func answerEverything(_ model: IdentifyWizardViewModel) {
    model.chooseSizeClass(2)
    model.toggleColor(.red)
    model.chooseBehavior(.atFeeder)
  }

  private func viewModel(
    _ journal: any JournalRepository,
    _ location: any LocationProvider
  ) -> IdentifyWizardViewModel {
    IdentifyWizardViewModel(
      birdCatalog: EmptyCatalog(),
      journal: journal,
      locationProvider: location,
      today: { Date(timeIntervalSince1970: 1_784_203_200) },
      now: { 1_000 }
    )
  }
}

/// Keeps every draft it is handed, so a test can read what the wizard actually assembled.
private actor RecordingJournal: JournalRepository {
  private(set) var saved: [OutingDraft] = []

  nonisolated func journalStream() -> AsyncThrowingStream<[OutingWithChildren], Error> {
    AsyncThrowingStream { $0.finish() }
  }

  nonisolated func lifeListCountStream() -> AsyncThrowingStream<Int, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func findById(_ outingId: String) async throws -> OutingWithChildren? { nil }

  func saveOuting(_ draft: OutingDraft) async throws -> String {
    saved.append(draft)
    return "outing-\(saved.count)"
  }

  func updateNotes(outingId: String, notes: String?) async throws {}
  func delete(outingId: String) async throws {}
  func deleteAll() async throws {}
}

/// A phone that answers each ask in turn — `nil` then a fix is the retry the message invites.
private final class FakeWizardLocation: LocationProvider, @unchecked Sendable {
  private let fixes: [Coordinate?]
  private var index = 0

  init(fixes: [Coordinate?]) { self.fixes = fixes }

  func currentCoordinate() async -> Coordinate? {
    defer { index += 1 }
    return fixes[min(index, fixes.count - 1)]
  }
}

/// The wizard's catalog reads are not what this suite is about.
private struct EmptyCatalog: BirdCatalogRepository {
  func allSpecies() async throws -> [Species] { [] }
  func browseGroups() async throws -> [SpeciesGroup] { [] }
  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? { nil }
  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] { [] }
  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? { nil }
  func seedVersion() async throws -> Int? { nil }
}
