/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoPreset.swift
//  birdspotter
//

import Foundation

/// What any section of a demo preset lands — a tagged union on the wire, keyed by `kind`.
///
/// Three outcomes, because three is what a demo can show: the app named a bird, the app
/// could not choose between two, or the app declined to answer. *Low* confidence is not a
/// fourth — it is ``species(speciesId:confidence:)`` with the slider down, and the screen
/// decides what a number that low is worth. Transport failures are not here either: a photo
/// that never arrived is a Layer-1 problem and not something the Director scripts.
///
/// The wire format is fixed byte for byte (`{"kind": "species",...}`), which is what lets one
/// shipped JSON file feed every build. The `kind` tag is hand-written here in `init(from:)`.
nonisolated enum DemoResult: Codable, Sendable, Equatable {

  /// The card, the photo, the confidence — the ninety-percent case, and the
  /// low-confidence one too: the confidence is the whole of the difference.
  case species(speciesId: String, confidence: Double)

  /// Two candidates, unresolved — "Green Jay or Blue Jay?", settled by an STT answer.
  case ambiguous(candidateIds: [String])

  /// Nothing lands and the app stays calm — the no-false-positive scenario.
  case noIdentification

  private enum CodingKeys: String, CodingKey {
    case kind, speciesId, confidence, candidateIds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    switch kind {
    case "species":
      self = .species(
        speciesId: try container.decode(String.self, forKey: .speciesId),
        confidence: try container.decode(Double.self, forKey: .confidence)
      )
    case "ambiguous":
      self = .ambiguous(candidateIds: try container.decode([String].self, forKey: .candidateIds))
    case "noIdentification":
      self = .noIdentification
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unknown result kind '\(kind)'"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .species(speciesId, confidence):
      try container.encode("species", forKey: .kind)
      try container.encode(speciesId, forKey: .speciesId)
      try container.encode(confidence, forKey: .confidence)
    case let .ambiguous(candidateIds):
      try container.encode("ambiguous", forKey: .kind)
      try container.encode(candidateIds, forKey: .candidateIds)
    case .noIdentification:
      try container.encode("noIdentification", forKey: .kind)
    }
  }
}

/// STT input — a question the watcher asks out loud, and the answer to give back.
///
/// ``speciesId`` surfaces a real card with the bird's photo; it deliberately carries **no
/// confidence**, because the app did not guess — the watcher described the bird and the
/// app agreed. A number there would be inventing precision.
nonisolated struct DemoQuestion: Codable, Sendable, Equatable, Identifiable {
  var id: String
  /// Spoken wordings that should match this row — several, so nobody has to be word-perfect.
  var prompts: [String]
  /// The one line the app says or shows.
  var answer: String
  /// A catalog species to surface alongside the answer, or nil for a words-only reply.
  var speciesId: String?
  /// Time to compose, in ms.
  var delayMillis: Int
}

/// Photo — the Nth capture of a session gets the Nth of these; past the end of the list,
/// every capture gets ``DemoPhotoResponse/pastTheEnd``.
nonisolated struct DemoPhotoResponse: Codable, Sendable, Equatable, Identifiable {
  var id: String
  var result: DemoResult
  /// What appears on screen.
  var caption: String
  /// What the glasses say — only when glasses are connected; the phone stays silent.
  var spokenLine: String?
  /// The response-delay slider, in ms.
  var delayMillis: Int

  /// What every capture past the end of a preset's list gets, however many are taken.
  ///
  /// Fixed, not authored: running off the end of a script is the demo going somewhere
  /// the operator did not plan for, and the honest answer there is that the app did not
  /// identify anything. Letting it be configured invites a preset whose fourth photo
  /// confidently names a bird nobody pointed the camera at.
  ///
  /// It stays silent on the glasses for the same reason.
  static let pastTheEnd = DemoPhotoResponse(
    id: "photo-past-the-end",
    result: .noIdentification,
    caption: "Not enough to go on — try getting closer.",
    spokenLine: nil,
    delayMillis: 2_000
  )
}

/// Ambient input — a bird call landing on the clock.
///
/// ``afterMillis`` is a **gap from the previous row**, not an offset from the start — the
/// first row's gap is measured from the microphone opening. Gaps are what a person editing
/// a demo thinks in, and inserting a row does not renumber every row after it. That is the
/// same reasoning the hard-coded script this replaced was written with — authored now.
nonisolated struct DemoAmbientCall: Codable, Sendable, Equatable, Identifiable {
  var id: String
  var afterMillis: Int
  var result: DemoResult
  /// Words to say instead of the sentence this row would compose for itself, or nil to let
  /// it compose one — see ``heardAloud(commonName:confidence:)``.
  ///
  /// **Composed is the default because a list on a clock is not a place to write the same
  /// opening over and over.** But a row is sometimes the one beat of a demo that needs its
  /// own words — a call the script wants introduced rather than announced — and rewriting
  /// the sentence beats adding a bird to the catalog to get a different one. It reaches the
  /// wearer under the same rule as every other line: only where there are glasses to say it
  /// into.
  ///
  /// It belongs to a row that names a bird. A row that lands no identification says nothing
  /// out loud, and a line authored for one would be words that never play.
  var spokenLine: String?
}

/// A named, saved script for the Demo Director. One is armed at a time — or none, which is
/// legal and means the app never identifies anything.
///
/// Three lists, one per way an answer gets triggered: ``questions`` are matched on the
/// watcher's words, ``photoResponses`` are ordered by capture index, ``ambientCalls`` fire on
/// the clock. That the trigger is the *section* — not a per-row setting — is the design's whole
/// shape.
///
/// A preset never picks a platform: device source, environment, compass and gaze are all
/// deliberately absent. The same preset runs identically on phone-only, mock device and
/// real glasses.
nonisolated struct DemoPreset: Codable, Sendable, Equatable, Identifiable {

  /// Wire-format version. Stored presets outlive the code that wrote them.
  var version: Int
  var id: String
  var name: String
  var questions: [DemoQuestion]
  var photoResponses: [DemoPhotoResponse]
  var ambientCalls: [DemoAmbientCall]
  /// The line for a spoken question that matches nothing.
  var unmatchedQuestion: String

  init(
    version: Int = 1,
    id: String,
    name: String,
    questions: [DemoQuestion] = [],
    photoResponses: [DemoPhotoResponse] = [],
    ambientCalls: [DemoAmbientCall] = [],
    unmatchedQuestion: String
  ) {
    self.version = version
    self.id = id
    self.name = name
    self.questions = questions
    self.photoResponses = photoResponses
    self.ambientCalls = ambientCalls
    self.unmatchedQuestion = unmatchedQuestion
  }

  /// Hand-written for the tolerances the format promises: a missing `version` reads as 1,
  /// missing lists as empty, and unknown fields are
  /// ignored (which `JSONDecoder` does by default) — a preset authored by a newer
  /// build must not take this one down on launch.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    questions = try container.decodeIfPresent([DemoQuestion].self, forKey: .questions) ?? []
    photoResponses = try container.decodeIfPresent([DemoPhotoResponse].self, forKey: .photoResponses) ?? []
    ambientCalls = try container.decodeIfPresent([DemoAmbientCall].self, forKey: .ambientCalls) ?? []
    unmatchedQuestion = try container.decode(String.self, forKey: .unmatchedQuestion)
  }

  /// One preset off the wire — the shape `SeedData/presets/full-flow.json` ships in.
  static func decode(_ data: Data) throws -> DemoPreset {
    try JSONDecoder().decode(DemoPreset.self, from: data)
  }
}
