/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirectorViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The Demo Director settings screens' policy: what plays is one dropdown-shaped decision,
/// presets are seeded then freely edited, rows upsert by id, and "Reset to starter" is
/// offered exactly while the shipped script is missing from the list.
///
/// Scenario names are fixed by the testing-parity rule.
@MainActor
@Suite("DemoDirectorViewModel")
struct DemoDirectorViewModelTests {

  // MARK: - Arming

  @Test func startsWithTheSeededPresetPlaying() {
    let model = model()

    #expect(model.uiState.presets.map(\.id) == ["shipped"])
    #expect(model.uiState.armedId == "shipped")
    #expect(model.uiState.armedName == "Full Flow")
  }

  @Test func arm_choosesWhatPlays() {
    let model = model()
    let copyId = model.duplicate("shipped")!

    model.arm(copyId)

    #expect(model.uiState.armedId == copyId)
  }

  @Test func arm_withNullIsTheNoneOption() {
    let model = model()

    model.arm(nil)

    #expect(model.uiState.armedId == nil)
    #expect(model.uiState.armedName == "None")
  }

  @Test func delete_ofThePlayingPresetFallsBackToNone() {
    let model = model()

    model.delete("shipped")

    #expect(model.uiState.armedId == nil)
    #expect(model.uiState.presets.isEmpty)
  }

  // MARK: - Reset to starter

  @Test func resetIsNotOfferedWhileTheShippedPresetIsUntouched() {
    let model = model()

    #expect(model.uiState.canResetToShipped == false)
  }

  @Test func resetIsOfferedOnceTheShippedPresetIsEdited() {
    let model = model()

    model.rename("shipped", to: "Mine now")

    #expect(model.uiState.canResetToShipped)
  }

  @Test func resetIsOfferedOnceTheShippedPresetIsDeleted() {
    let model = model()

    model.delete("shipped")

    #expect(model.uiState.canResetToShipped)
  }

  @Test func resetToShipped_putsItBackAndStopsBeingOffered() {
    let model = model()
    model.rename("shipped", to: "Mine now")

    model.resetToShipped()

    #expect(model.uiState.canResetToShipped == false)
    #expect(model.uiState.preset("shipped")?.name == "Full Flow")
  }

  // MARK: - Presets

  @Test func duplicate_makesAUniquelyIdentifiedCopy() {
    let model = model()

    let first = model.duplicate("shipped")!
    let second = model.duplicate("shipped")!

    #expect(first != "shipped")
    #expect(first != second)
    #expect(model.uiState.presets.count == 3)
  }

  @Test func duplicate_reIdentifiesItsRows() {
    let model = model()
    model.saveQuestion("shipped", Self.question)

    let copyId = model.duplicate("shipped")!

    // Rows are addressed by id; a shared one would make an edit to either land on both.
    let original = model.uiState.preset("shipped")!.questions[0]
    let copied = model.uiState.preset(copyId)!.questions[0]
    #expect(original.id != copied.id)
    #expect(original.answer == copied.answer)
  }

  @Test func newPreset_startsEmptyButPlayable() {
    let model = model()

    let id = model.newPreset()

    let created = model.uiState.preset(id)!
    #expect(created.name == "New preset")
    #expect(created.questions.isEmpty)
    #expect(created.photoResponses.isEmpty)
    #expect(created.ambientCalls.isEmpty)
  }

  @Test func rename_renamesAPreset() {
    let model = model()

    model.rename("shipped", to: "Booth — Tuesday")

    #expect(model.uiState.preset("shipped")?.name == "Booth — Tuesday")
  }

  // MARK: - Rows

  @Test func saveQuestion_addsThenAmendsById() {
    let model = model()

    model.saveQuestion("shipped", Self.question)
    #expect(model.uiState.preset("shipped")?.questions.count == 1)

    var amended = Self.question
    amended.answer = "Changed"
    model.saveQuestion("shipped", amended)

    let questions = model.uiState.preset("shipped")!.questions
    #expect(questions.count == 1)
    #expect(questions[0].answer == "Changed")
  }

  @Test func deleteQuestion_removesIt() {
    let model = model()
    model.saveQuestion("shipped", Self.question)

    model.deleteQuestion("shipped", Self.question.id)

    #expect(model.uiState.preset("shipped")!.questions.isEmpty)
  }

  @Test func savePhotoResponse_addsInOrder() {
    let model = model()

    model.savePhotoResponse("shipped", photo("a", "First"))
    model.savePhotoResponse("shipped", photo("b", "Second"))

    // Order is the semantic: the Nth capture gets the Nth row.
    #expect(model.uiState.preset("shipped")!.photoResponses.map(\.caption) == ["First", "Second"])
  }

  @Test func saveAmbientCall_addsThenAmendsById() {
    let model = model()

    model.saveAmbientCall("shipped", Self.call)
    var amended = Self.call
    amended.afterMillis = 12_000
    model.saveAmbientCall("shipped", amended)

    let calls = model.uiState.preset("shipped")!.ambientCalls
    #expect(calls.count == 1)
    #expect(calls[0].afterMillis == 12_000)
  }

  @Test func deleteAmbientCall_removesIt() {
    let model = model()
    model.saveAmbientCall("shipped", Self.call)

    model.deleteAmbientCall("shipped", Self.call.id)

    #expect(model.uiState.preset("shipped")!.ambientCalls.isEmpty)
  }

  @Test func ambientRunningTotals_accumulateGaps() {
    let totals = ambientRunningTotals([
      DemoAmbientCall(id: "a", afterMillis: 8_000, result: .noIdentification),
      DemoAmbientCall(id: "b", afterMillis: 15_000, result: .noIdentification),
      DemoAmbientCall(id: "c", afterMillis: 18_000, result: .noIdentification),
    ])

    #expect(totals == [8_000, 23_000, 41_000])
  }

  // MARK: - Result editing

  @Test func resultOf_keepsTheBirdWhenTheKindChanges() {
    let species = DemoResult.species(speciesId: "green-jay", confidence: 0.91)

    let ambiguous = resultOf(.ambiguous, species)
    let back = resultOf(.species, ambiguous)

    // Flipping the kind must not make the operator pick the bird again.
    #expect(ambiguous == .ambiguous(candidateIds: ["green-jay"]))
    #expect(back == .species(speciesId: "green-jay", confidence: 0.87))
  }

  @Test func resultOf_dropsTheBirdForAKindThatCarriesNone() {
    let result = resultOf(.noIdentification, .species(speciesId: "green-jay", confidence: 0.91))

    #expect(result == .noIdentification)
  }

  // MARK: - Fixtures

  private func model() -> DemoDirectorViewModel {
    let suiteName = "DemoDirectorViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return DemoDirectorViewModel(store: DemoSettingsStore(defaults: defaults, shipped: Self.shipped))
  }

  private func photo(_ id: String, _ caption: String) -> DemoPhotoResponse {
    DemoPhotoResponse(
      id: id,
      result: .noIdentification,
      caption: caption,
      spokenLine: nil,
      delayMillis: 10
    )
  }

  private static let shipped = DemoPreset(
    id: "shipped",
    name: "Full Flow",
    unmatchedQuestion: "Sorry — didn't catch that."
  )

  private static let question = DemoQuestion(
    id: "q1",
    prompts: ["green with a yellow belly"],
    answer: "That's likely a Green Jay.",
    speciesId: "green-jay",
    delayMillis: 1_500
  )

  private static let call = DemoAmbientCall(
    id: "c1",
    afterMillis: 8_000,
    result: .species(speciesId: "american-robin", confidence: 0.87)
  )
}
