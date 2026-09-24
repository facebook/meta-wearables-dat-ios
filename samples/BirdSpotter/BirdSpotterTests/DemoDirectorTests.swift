/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirectorTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The Demo Director's policy: the shipped starter decodes (the wire-format parity check —
/// every build decodes the *same file*), ambient calls land in order with
/// names resolved from the catalog, photos answer by index then fall back, spoken
/// questions match on normalized words, and none of it does anything with no preset armed.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("DemoDirector")
struct DemoDirectorTests {

  // MARK: - The shipped starter

  @Test func decodesTheShippedStarterPreset() throws {
    let preset = try DemoPreset.decode(shippedStarterJson())

    #expect(preset.id == "starter-full-flow")
    #expect(preset.name == "Full Flow")
    #expect(preset.version == 1)

    // One ambient row: the robin, eight seconds after the microphone opens.
    #expect(preset.ambientCalls.count == 1)
    #expect(preset.ambientCalls[0].afterMillis == 8_000)
    #expect(preset.ambientCalls[0].result == .species(speciesId: "american-robin", confidence: 0.87))

    // One photo row on purpose — the second capture runs off the end of the list.
    #expect(preset.photoResponses.count == 1)
    #expect(preset.photoResponses[0].result == .species(speciesId: "northern-cardinal", confidence: 0.92))

    // The one question links a real catalog bird, and carries no confidence.
    #expect(preset.questions.count == 1)
    #expect(preset.questions[0].speciesId == "green-jay")
  }

  @Test func decodingIgnoresFieldsItDoesNotKnow() throws {
    // A preset authored by a newer build must not take this one down on launch.
    let json = String(decoding: try shippedStarterJson(), as: UTF8.self)
      .replacingOccurrences(of: "\"version\": 1,", with: "\"version\": 1, \"futureKnob\": true,")

    let preset = try DemoPreset.decode(Data(json.utf8))

    #expect(preset.id == "starter-full-flow")
  }

  @Test func decodesAnAmbientRowsOwnSpokenLine() throws {
    // Optional on the wire, both ways round: the shipped row composes its own sentence,
    // and a row that carries one keeps the words as written.
    let written = String(decoding: try shippedStarterJson(), as: UTF8.self)
      .replacingOccurrences(
        of: "\"afterMillis\": 8000,",
        with: "\"afterMillis\": 8000, \"spokenLine\": \"Hear that? That's our robin.\","
      )

    let authored = try DemoPreset.decode(Data(written.utf8))
    let shipped = try DemoPreset.decode(shippedStarterJson())

    #expect(authored.ambientCalls[0].spokenLine == "Hear that? That's our robin.")
    #expect(shipped.ambientCalls[0].spokenLine == nil)
  }

  // MARK: - Ambient input: the clock lane

  @Test func ambientCalls_landInOrderWithResolvedNames() async throws {
    let director = director(
      preset: preset(ambientCalls: [
        call("robin", after: 5, result: .species(speciesId: "american-robin", confidence: 0.87)),
        call("jay", after: 5, result: .species(speciesId: "green-jay", confidence: 0.91)),
      ]))

    let findings = try await collect(director.findingStream())

    #expect(findings.count == 2)
    guard case let .bird(firstId, firstName, firstConfidence, _) = findings[0],
      case let .bird(secondId, secondName, _, _) = findings[1]
    else {
      Issue.record("Expected two bird findings, got \(findings)")
      return
    }
    #expect(firstId == "american-robin")
    #expect(firstName == "American Robin")
    #expect(firstConfidence == 0.87)
    #expect(secondId == "green-jay")
    #expect(secondName == "Green Jay")
  }

  @Test func ambientCalls_dropASpeciesTheCatalogCannotResolve() async throws {
    let director = director(
      preset: preset(ambientCalls: [
        call("ghost", after: 5, result: .species(speciesId: "no-such-bird", confidence: 0.9)),
        call("robin", after: 5, result: .species(speciesId: "american-robin", confidence: 0.87)),
      ]))

    let findings = try await collect(director.findingStream())

    // The unresolvable row lands nothing; the session is not taken down by it.
    #expect(findings.count == 1)
    guard case let .bird(speciesId, _, _, _) = findings[0] else {
      Issue.record("Expected a bird finding, got \(findings)")
      return
    }
    #expect(speciesId == "american-robin")
  }

  @Test func ambientCalls_landNothingForANoIdentificationRow() async throws {
    let director = director(
      preset: preset(ambientCalls: [
        call("quiet", after: 5, result: .noIdentification)
      ]))

    let findings = try await collect(director.findingStream())

    #expect(findings.isEmpty)
  }

  @Test func ambientCalls_carryTheLineTheRowAuthored() async throws {
    let director = director(
      preset: preset(ambientCalls: [
        call(
          "robin",
          after: 5,
          result: .species(speciesId: "american-robin", confidence: 0.87),
          saying: "Hear that? That's the robin that nests by the gate."
        )
      ]))

    let findings = try await collect(director.findingStream())

    guard case let .bird(_, _, _, spokenLine) = findings.first else {
      Issue.record("Expected a bird finding, got \(findings)")
      return
    }
    #expect(spokenLine == "Hear that? That's the robin that nests by the gate.")
  }

  @Test func ambientCalls_carryNoLineWhereTheRowAuthoredNone() async throws {
    // Nothing to say is not silence: it is the session composing the sentence itself.
    let director = director(
      preset: preset(ambientCalls: [
        call("robin", after: 5, result: .species(speciesId: "american-robin", confidence: 0.87))
      ]))

    let findings = try await collect(director.findingStream())

    guard case let .bird(_, _, _, spokenLine) = findings.first else {
      Issue.record("Expected a bird finding, got \(findings)")
      return
    }
    #expect(spokenLine == nil)
  }

  @Test func ambientCalls_landAnAmbiguousRowAsAQuestion() async throws {
    // "Green Jay or Blue Jay?" — the entire reason the speech path exists; an STT row
    // is what settles it.
    let director = director(
      preset: preset(ambientCalls: [
        call("which", after: 5, result: .ambiguous(candidateIds: ["green-jay", "american-robin"]))
      ]))

    let findings = try await collect(director.findingStream())

    #expect(findings.count == 1)
    guard case let .answer(text) = findings.first else {
      Issue.record("an ambiguous row should land as a question")
      return
    }
    #expect(text == "Green Jay or American Robin?")
  }

  @Test func ambientCalls_dropAnAmbiguousRowTheCatalogCannotFullyName() async throws {
    // Half a question — "Green Jay or …?" — is worse than silence, so one unresolvable
    // candidate drops the whole row.
    let director = director(
      preset: preset(ambientCalls: [
        call("which", after: 5, result: .ambiguous(candidateIds: ["green-jay", "no-such-bird"]))
      ]))

    let findings = try await collect(director.findingStream())

    #expect(findings.isEmpty)
  }

  @Test func findingStream_isSilentWithNoPresetArmed() async throws {
    let director = director(preset: nil)

    let findings = try await collect(director.findingStream())

    #expect(findings.isEmpty)
  }

  // MARK: - Photo: the index lane

  @Test func responseToPhotoAt_walksTheListThenLandsNoIdentification() {
    let row = photoResponse("row-1", result: .species(speciesId: "northern-cardinal", confidence: 0.92))
    let director = director(preset: preset(photoResponses: [row]))

    #expect(director.response(toPhotoAt: 0) == row)
    // Past the end is fixed, not authored: the same no-identification row forever.
    #expect(director.response(toPhotoAt: 1) == .pastTheEnd)
    #expect(director.response(toPhotoAt: 5) == .pastTheEnd)
    #expect(DemoPhotoResponse.pastTheEnd.result == .noIdentification)
    #expect(DemoPhotoResponse.pastTheEnd.spokenLine == nil)
  }

  @Test func responseToPhotoAt_isNothingWithNoPresetArmed() {
    let director = director(preset: nil)

    #expect(director.response(toPhotoAt: 0) == nil)
  }

  // MARK: - STT input: the words lane

  @Test func answerTo_matchesAPromptInsideASpokenSentence() {
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    let matched = director.answer(to: "Um, it's GREEN, with a yellow belly!")

    #expect(matched == Self.greenJayQuestion)
  }

  @Test func answerTo_matchesAcrossWordsTheWearerAddedInTheMiddle() {
    // **The question that went unanswered on real glasses.** The prompt is "green with a
    // yellow belly"; what was actually said was "Green bird with a yellow belly" — one word
    // nobody thought to author, and containment misses the lot.
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    let matched = director.answer(to: "Green bird with a yellow belly.")

    #expect(matched == Self.greenJayQuestion)
  }

  @Test func answerTo_matchesAPromptBuriedInALongerSentence() {
    // A wearer narrating rather than querying, which is how a question actually gets asked
    // out loud when nothing is framing it.
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    let matched = director.answer(
      to: "I think I just saw a green sort of bird with a yellow belly over there"
    )

    #expect(matched == Self.greenJayQuestion)
  }

  @Test func answerTo_isNothingWhenThePromptsWordsAreOutOfOrder() {
    // **The line between forgiving and meaningless.** Order is the whole of what stops this
    // being a bag of words: a sentence that happens to contain the same words scattered
    // through it did not ask the question.
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    #expect(director.answer(to: "the belly was yellow and it was green") == nil)
  }

  @Test func answerTo_isNothingWhenOnlySomeOfThePromptWasSaid() {
    // Every word has to be there. A prompt half-said is a sentence about something else.
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    #expect(director.answer(to: "it was green") == nil)
  }

  @Test func answerTo_isNothingWhenNoPromptMatches() {
    let director = director(preset: preset(questions: [Self.greenJayQuestion]))

    #expect(director.answer(to: "what does it eat") == nil)
  }

  @Test func answerTo_isNothingWithNoPresetArmed() {
    let director = director(preset: nil)

    #expect(director.answer(to: "it's green with a yellow belly") == nil)
  }

  // MARK: - The store: seeding, arming, resetting

  @Test func firstRunSeedsTheShippedPresetAndArmsIt() throws {
    let store = try freshStore()

    // The shipped file is a template: on first run it is copied in, and the copy is
    // what plays.
    #expect(store.presets() == [store.shipped])
    #expect(store.armedPreset()?.id == store.shipped?.id)
  }

  @Test func anEmptiedListIsNotReseeded() throws {
    let store = try freshStore()

    store.savePresets([])

    // Deleting every preset is allowed, and nothing refills behind the operator.
    #expect(store.presets().isEmpty)
    #expect(store.armedPreset() == nil)
  }

  @Test func disarmingPersistsAsExplicitlyNone() throws {
    let store = try freshStore()

    store.armPreset(id: nil)

    #expect(store.armedPreset() == nil)
  }

  @Test func savedPresetsSurviveARoundTripAndCanBeArmed() throws {
    let store = try freshStore()
    var booth = try DemoPreset.decode(shippedStarterJson())
    booth.id = "booth"
    booth.name = "Booth"

    store.savePresets(store.presets() + [booth])
    store.armPreset(id: "booth")

    #expect(store.armedPreset()?.id == "booth")
    #expect(store.armedPreset()?.name == "Booth")
  }

  @Test func armingAnUnknownIdArmsNothing() throws {
    let store = try freshStore()

    store.armPreset(id: "no-such-preset")

    #expect(store.armedPreset() == nil)
  }

  @Test func theShippedPresetIsPresentUntilItIsEdited() throws {
    let store = try freshStore()
    #expect(store.isShippedPresent)

    store.savePresets(
      store.presets().map {
        var p = $0
        p.name = "Edited"
        return p
      })

    // Value equality, not an id check: editing the copy is as much a departure from
    // the shipped script as deleting it, and both are worth being able to undo.
    #expect(store.isShippedPresent == false)
  }

  @Test func resetPutsTheShippedPresetBackAfterAnEdit() throws {
    let store = try freshStore()
    store.savePresets(
      store.presets().map {
        var p = $0
        p.name = "Edited"
        return p
      })

    store.resetToShipped()

    #expect(store.isShippedPresent)
    #expect(store.presets().count == 1)
  }

  @Test func resetPutsTheShippedPresetBackAfterADelete() throws {
    let store = try freshStore()
    // Deleting through the panel disarms first — see `DemoDirectorViewModel.delete`.
    store.armPreset(id: nil)
    store.savePresets([])

    store.resetToShipped()

    #expect(store.presets() == [store.shipped])
    // Restoring a script is not choosing to run it: arming is left alone.
    #expect(store.armedPreset() == nil)
  }

  // MARK: - Fixtures

  private func shippedStarterJson() throws -> Data {
    let sampleRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf: sampleRoot.appendingPathComponent("SeedData/presets/full-flow.json")
    )
  }

  private func freshStore(shipped: DemoPreset? = nil) throws -> DemoSettingsStore {
    let suiteName = "DemoDirectorTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let resolved = try shipped ?? DemoPreset.decode(shippedStarterJson())
    return DemoSettingsStore(defaults: defaults, shipped: resolved)
  }

  /// A director over a store holding exactly `preset`, armed — or holding nothing.
  private func director(preset: DemoPreset?) -> PresetDemoDirector {
    let suiteName = "DemoDirectorTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = DemoSettingsStore(defaults: defaults, shipped: preset)
    if preset == nil { store.armPreset(id: nil) }
    return PresetDemoDirector(store: store, catalog: FakeCatalog())
  }

  private func collect(_ stream: AsyncThrowingStream<SessionFinding, Error>) async throws -> [SessionFinding] {
    var findings: [SessionFinding] = []
    for try await finding in stream {
      findings.append(finding)
    }
    return findings
  }

  private func preset(
    questions: [DemoQuestion] = [],
    photoResponses: [DemoPhotoResponse] = [],
    ambientCalls: [DemoAmbientCall] = []
  ) -> DemoPreset {
    DemoPreset(
      id: "test-preset",
      name: "Test",
      questions: questions,
      photoResponses: photoResponses,
      ambientCalls: ambientCalls,
      unmatchedQuestion: "Sorry — didn't catch that."
    )
  }

  private func call(
    _ id: String,
    after millis: Int,
    result: DemoResult,
    saying spokenLine: String? = nil
  ) -> DemoAmbientCall {
    DemoAmbientCall(id: id, afterMillis: millis, result: result, spokenLine: spokenLine)
  }

  private func photoResponse(_ id: String, result: DemoResult) -> DemoPhotoResponse {
    DemoPhotoResponse(id: id, result: result, caption: "caption", spokenLine: nil, delayMillis: 10)
  }

  private static let greenJayQuestion = DemoQuestion(
    id: "green-yellow-belly",
    prompts: ["it's green with a yellow belly", "green bird yellow belly"],
    answer: "That's likely a Green Jay.",
    speciesId: "green-jay",
    delayMillis: 10
  )
}

/// Two birds and nothing else — what the Director resolves names against.
private struct FakeCatalog: BirdCatalogRepository {

  private let birds = [
    "american-robin": "American Robin",
    "green-jay": "Green Jay",
  ]

  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? {
    guard let commonName = birds[speciesId] else { return nil }
    return SpeciesWithMedia(
      species: Species(
        id: speciesId,
        commonName: commonName,
        scientificName: "Testus \(speciesId)",
        wikidataId: nil,
        ebirdSpeciesCode: nil,
        familyName: "Testidae",
        browseOrder: 10,
        groupName: "Test Birds",
        sizeClass: 3,
        conservationStatus: nil,
        aboutText: "",
        habitatText: ""
      ),
      media: []
    )
  }

  func allSpecies() async throws -> [Species] { [] }
  func browseGroups() async throws -> [SpeciesGroup] { [] }
  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] { [] }
  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? { nil }
  func seedVersion() async throws -> Int? { nil }
}
