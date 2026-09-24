/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PresetDemoDirector.swift
//  birdspotter
//

import Foundation

/// The ``DemoDirector`` the app ships: it reads the armed preset out of
/// ``DemoSettingsStore`` and plays it.
///
/// Which preset is armed is read at iteration time, so re-arming between takes needs no
/// restart — the next session simply plays the new script. Within a session nothing
/// re-reads it: a preset changing under a live run is not a case worth designing for,
/// because the operator recovering from anything is "close the session, start a new one".
///
/// Species ids resolve against the catalog at play time, because a
/// ``SessionFinding/bird(speciesId:commonName:confidence:)`` carries a common name and the
/// preset deliberately does not — the catalog is the one source of bird names. A row whose id
/// the catalog cannot resolve is dropped rather than surfaced half-named; the import path is
/// where unknown ids get *refused* (see the QR stretch goal).
nonisolated struct PresetDemoDirector: DemoDirector {

  private let store: DemoSettingsStore
  private let catalog: any BirdCatalogRepository

  init(store: DemoSettingsStore, catalog: any BirdCatalogRepository) {
    self.store = store
    self.catalog = catalog
  }

  var armed: DemoPreset? { store.armedPreset() }

  /// The ambient section, on the clock: each call waits its gap, then lands as a bird
  /// finding. Cold, like every ``SessionDetector`` — iterating starts the clock,
  /// cancelling abandons it, and a second iteration is a fresh session from the top.
  ///
  /// With nothing armed it finishes without emitting: the session goes on listening,
  /// deliberately silent.
  func findingStream() -> AsyncThrowingStream<SessionFinding, Error> {
    let store = store
    let catalog = catalog
    return AsyncThrowingStream { continuation in
      let task = Task {
        defer { continuation.finish() }
        guard let preset = store.armedPreset() else { return }
        for call in preset.ambientCalls {
          try await Task.sleep(for: .milliseconds(call.afterMillis))
          let found = await Self.finding(
            for: call.result,
            saying: call.spokenLine,
            in: catalog
          )
          if let found {
            continuation.yield(found)
          }
        }
        // Finishing with nothing more scripted to say is the honest end of a
        // script — the session above goes on listening; nothing loops.
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func response(toPhotoAt index: Int) -> DemoPhotoResponse? {
    guard let preset = armed else { return nil }
    guard preset.photoResponses.indices.contains(index) else { return .pastTheEnd }
    return preset.photoResponses[index]
  }

  /// The question a spoken sentence is asking, or nil for a clean miss.
  ///
  /// **Matched word by word, in order, rather than as a run of characters.** A prompt is a
  /// phrase somebody typed into the editor and a transcript is a sentence somebody actually
  /// said, and the two are never going to be the same string: "green with a yellow belly"
  /// against *"Green **bird** with a yellow belly"* misses on containment for the sake of one
  /// word nobody thought to author. That is not a hypothetical — it is the first question ever
  /// asked of a real pair of glasses, and it went unanswered.
  ///
  /// So a prompt matches when **all of its words appear in the transcript, in the order it
  /// wrote them**, with anything at all allowed in between. The filler the wearer puts in —
  /// *bird*, *sort of*, *kind of a* — no longer costs the operator a prompt variant each.
  ///
  /// **Order is what keeps it from being a bag of words.** Without it, "belly yellow green"
  /// would answer a question about a green bird with a yellow belly, and so would any sentence
  /// unlucky enough to contain the same four words scattered through it. With it, the phrase
  /// has to have been *said*, in the shape it was authored.
  ///
  /// The looseness is deliberate and it is not free: a run listens for its whole length, so a
  /// longer sentence has more chances to contain a short prompt's words in order. **Short
  /// prompts are the risk, not long ones** — a two-word prompt will eventually match something
  /// said to the room. Author phrases, not keywords.
  func answer(to transcript: String) -> DemoQuestion? {
    let heard = Self.words(in: Self.normalized(transcript))
    guard !heard.isEmpty else { return nil }
    guard let preset = armed else { return nil }
    return preset.questions.first { question in
      question.prompts.contains { prompt in
        Self.said(heard, inOrder: Self.words(in: Self.normalized(prompt)))
      }
    }
  }

  /// What an ambient result puts on the timeline.
  ///
  /// `species` is a bird with a confidence, whatever that confidence is — what a low
  /// number is worth is the screen's judgement, not this one's. `noIdentification` is,
  /// correctly, nothing landing. `ambiguous` lands as the question it is — "Green Jay or
  /// Blue Jay?" — for a spoken answer to settle; a candidate the catalog cannot name
  /// drops the whole row, the same silence an unresolvable species keeps.
  ///
  /// `line` is the row's own wording where it authored one, and it travels with the bird
  /// rather than being said here: this type scripts *what* is identified, and where a line
  /// comes out is the session's rule to keep.
  private static func finding(
    for result: DemoResult,
    saying line: String?,
    in catalog: any BirdCatalogRepository
  ) async -> SessionFinding? {
    switch result {
    case let .species(speciesId, confidence):
      return await bird(speciesId, confidence: confidence, saying: line, in: catalog)
    case let .ambiguous(candidateIds):
      return await question(candidateIds, in: catalog)
    case .noIdentification:
      return nil
    }
  }

  private static func bird(
    _ speciesId: String,
    confidence: Double,
    saying line: String?,
    in catalog: any BirdCatalogRepository
  ) async -> SessionFinding? {
    guard let found = try? await catalog.findById(speciesId) else { return nil }
    return .bird(
      speciesId: speciesId,
      commonName: found.species.commonName,
      confidence: Float(confidence),
      spokenLine: line
    )
  }

  private static func question(_ candidateIds: [String], in catalog: any BirdCatalogRepository) async -> SessionFinding? {
    guard !candidateIds.isEmpty else { return nil }
    var names: [String] = []
    for id in candidateIds {
      guard let found = try? await catalog.findById(id) else { return nil }
      names.append(found.species.commonName)
    }
    return .answer(text: names.joined(separator: " or ") + "?")
  }

  /// The words as ears hear them: lowercased, punctuation dropped, whitespace
  /// collapsed — so "It's green, with a yellow belly!" reads as the prompt
  /// "it's green with a yellow belly" does.
  ///
  /// **The apostrophe is what this is really for.** A recogniser writes *it's*, an operator
  /// types *its*, and neither is wrong; dropping the punctuation makes them the same word
  /// rather than making somebody choose. Everything past that is ``said(_:inOrder:)``'s to
  /// forgive.
  static func normalized(_ text: String) -> String {
    let kept = text.lowercased().filter { character in
      character == " " || (character.isASCII && (character.isLetter || character.isNumber))
    }
    return kept.split(separator: " ").joined(separator: " ")
  }

  /// A normalised line as the words it is made of.
  private static func words(in line: String) -> [String] {
    line.isEmpty ? [] : line.split(separator: " ").map(String.init)
  }

  /// Whether `heard` said all of `prompt`'s words, in `prompt`'s order — see
  /// ``answer(to:)``.
  ///
  /// One pass, keeping a place in the prompt: every word of the sentence either advances it or
  /// is filler. An empty prompt matches nothing rather than everything — an operator who left
  /// the field blank authored no way to ask, not a way to ask with silence.
  private static func said(_ heard: [String], inOrder prompt: [String]) -> Bool {
    guard !prompt.isEmpty else { return false }
    var next = 0
    for word in heard {
      if word == prompt[next] { next += 1 }
      if next == prompt.count { return true }
    }
    return false
  }
}
