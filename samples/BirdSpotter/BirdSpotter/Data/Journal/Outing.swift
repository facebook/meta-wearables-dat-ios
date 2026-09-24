/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  Outing.swift
//  birdspotter
//

import Foundation
import GRDB

/// What shape the outing took. `live` is the recording flow — a timeline with media and
/// events pinned to it. `manual` is the identify wizard — no capture, no clock, one
/// confirmed bird, written in one breath.
nonisolated enum OutingKind: String, Codable, Sendable, DatabaseValueConvertible {
  case live = "LIVE"
  case manual = "MANUAL"
}

/// What a timeline event row carries. See the per-type column contract in the design doc.
nonisolated enum OutingEventType: String, Codable, Sendable, DatabaseValueConvertible {
  case detection = "DETECTION"
  case qa = "QA"
  case wizardAnswer = "WIZARD_ANSWER"
}

/// Which wizard question a `wizardAnswer` event answers.
nonisolated enum WizardTrait: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
  case size = "SIZE"
  case colors = "COLORS"
  case behavior = "BEHAVIOR"
}

/// What a captured file is. Derived visuals (waveform, spectrogram) are never stored.
nonisolated enum OutingMediaType: String, Codable, Sendable, DatabaseValueConvertible {
  case photo = "PHOTO"
  case audio = "AUDIO"
}

/// Which device performed a capture. Also decides whose compass fed that row's `bearingDeg`.
nonisolated enum CaptureSource: String, Codable, Sendable, DatabaseValueConvertible {
  case glasses = "GLASSES"
  case phone = "PHONE"
}

/// Where the observer was looking at a moment — the stratum, not the angle.
///
/// The same five strata the live session's chip reads, and deliberately the same type: what a
/// watcher was shown while aiming is what gets stored beside what they caught. These were three
/// (`CANOPY`/`LEVEL`/`GROUND`) while the stored value and the on-screen one were separate ideas,
/// which cost the two most useful readings a birder has — *overhead*, where a flyover or a raptor
/// is, and *understory*, which is not the ground.
///
/// Ordered low to high, so a case's place in ``allCases`` is the stratum's height and comparisons
/// read the way the words do. See ``gazeBand(_:)`` for the thresholds.
nonisolated enum GazeContext: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
  case ground = "GROUND"
  case understory = "UNDERSTORY"
  case horizon = "HORIZON"
  case canopy = "CANOPY"
  case overhead = "OVERHEAD"
}

/// The phone's fix at the start of an outing — one per outing, per open question #16;
/// per-moment location is deliberately not tracked.
///
/// **Required, not optional.** Identify is gated on location being granted, and a screen that
/// cannot get a fix refuses to save rather than writing an outing that claims to be nowhere.
/// The nullability used to live here and be checked nowhere; now the type carries the rule.
///
/// Grouped into one value rather than two loose parameters so the call reads the same on both
/// platforms, and so a latitude can never be passed without its longitude.
nonisolated struct CaptureLocation: Codable, Equatable, Sendable {
  var latitude: Double
  var longitude: Double
}

/// Where a camera was aimed for one *photo* — never the outing, which spans many headings,
/// and never an event or a confirmation, which reach it through the photo they name.
/// Grouped for the same Swift-defaults reason as ``CaptureLocation``.
///
/// A photo is the only row that *is* a moment of aiming, which is why this rides on
/// ``PendingMedia`` alone.
nonisolated struct MomentContext: Codable, Equatable, Sendable {
  var gazeContext: GazeContext?
  /// True north, 0–360, from the same device as the capture's `source`.
  var bearingDeg: Double?

  init(gazeContext: GazeContext? = nil, bearingDeg: Double? = nil) {
    self.gazeContext = gazeContext
    self.bearingDeg = bearingDeg
  }
}

/// One journal entry — the root every child row carries the id of.
///
/// Written **at save**, never before: an outing assembles in memory as an ``OutingDraft``
/// while it is happening and reaches this table only when the user keeps it. A row here is
/// therefore a finished outing by construction — the Journal is a query over these, newest
/// first, with nothing to filter out.
///
/// Timestamps are epoch milliseconds UTC; formatting is the UI's job.
nonisolated struct Outing: Codable, Identifiable, Equatable, Sendable,
  FetchableRecord, PersistableRecord
{
  static let databaseTableName = "Outing"

  var id: String
  var kind: OutingKind
  /// Capture time. May predate `createdAt` when a transfer lags; the Journal sorts on this.
  var startedAt: Int64
  /// Stamped at stop. Nil for `manual`, which has no clock.
  var durationMs: Int64?
  /// The phone's fix, taken once at the start. Not optional: Identify is gated on location,
  /// and a flow that cannot get a fix declines to save rather than logging a bird nowhere.
  var latitude: Double
  var longitude: Double
  var notes: String?
  var createdAt: Int64
  var updatedAt: Int64
}

/// A file that actually landed in the app's media directory, pinned to the outing's
/// timeline by `offsetMs`. A saved outing may legitimately have zero of these — a walk that
/// heard nothing still keeps. Audio arrives as *segments* — the source can change or vanish
/// under a session that never stopped — which is why one outing holds many audio rows.
nonisolated struct OutingMedia: Codable, Identifiable, Equatable, Sendable,
  FetchableRecord, PersistableRecord
{
  static let databaseTableName = "OutingMedia"

  var id: String
  var outingId: String
  var type: OutingMediaType
  var source: CaptureSource
  /// ms from the outing's `startedAt`. Nil where there is no clock — `manual` children.
  var offsetMs: Int64?
  /// Relative to the media root — never absolute. See ``MediaFileStore``.
  var filePath: String
  var width: Int?
  var height: Int?
  var durationMs: Int64?
  /// The moment's pitch and heading — photos only; an audio segment has no single moment.
  var gazeContext: GazeContext?
  var bearingDeg: Double?
  var createdAt: Int64
}

/// A non-file timeline pin. One deliberately wide table rather than three narrow ones,
/// because its one real read is the whole timeline ordered by `offsetMs`; columns are
/// per-`type`, nil elsewhere:
///
/// - `detection` — `speciesId`, `confidence`, and one of `mediaId` / `offsetMs`
/// - `qa` — `question`, `answer`; one row per exchange
/// - `wizardAnswer` — `trait`, `value`; three rows per wizard outing
nonisolated struct OutingEvent: Codable, Identifiable, Equatable, Sendable,
  FetchableRecord, PersistableRecord
{
  static let databaseTableName = "OutingEvent"

  var id: String
  var outingId: String
  /// The capture this event was produced from — a photo, for a detection made by looking
  /// at one. Nil for everything else, including a *sound* detection: the classifier's
  /// window is a range on the clock that can straddle a handover, so there is no single
  /// file it came from.
  ///
  /// Set, this row's moment lives on that photo and `offsetMs` stays nil.
  var mediaId: String?
  var type: OutingEventType
  /// ms from the outing's `startedAt`. Nil where there is no clock (`manual` children)
  /// and nil again where `mediaId` owns the moment — the shutter is the honest position
  /// for a detection, and inference lands a few hundred ms after it.
  var offsetMs: Int64?
  /// Cross-file reference into `catalog.db`, not a FK. `detection` only.
  var speciesId: String?
  /// 0–1, and welded to `speciesId` — the label this number actually scored.
  var confidence: Double?
  var question: String?
  var answer: String?
  var trait: WizardTrait?
  /// `wizardAnswer` payload, in the catalog enums' own SCREAMING_SNAKE spellings:
  /// `size` is the sparrow-to-goose digit ("4"), `colors` up to three comma-joined
  /// tokens ("BLACK,RED"), `behavior` one token.
  var value: String?
  var createdAt: Int64
}

/// A confirmed bird within an outing — the life-list unit. Confirmation is the act of
/// naming a species, so `speciesId` is non-nil here; an outing with nothing confirmed
/// simply has no rows.
///
/// **Who was confirmed, and what evidence backs it — nothing else.** When the bird was seen,
/// how confident the detector was and where the camera pointed all belong to the rows that
/// recorded them, and are read through `sourceEventId` rather than copied here. See
/// ``OutingWithChildren/confidence(of:)`` for the one that can otherwise go wrong.
///
/// `speciesId` points at `Species.id` in `catalog.db` and deliberately carries no foreign
/// key — SQLite cannot enforce one across files. Treat an unresolvable id as an
/// unidentified sighting, never an error.
nonisolated struct Sighting: Codable, Identifiable, Equatable, Sendable,
  FetchableRecord, PersistableRecord
{
  static let databaseTableName = "Sighting"

  var id: String
  var outingId: String
  /// The `detection` this confirmation accepted. Nil for a wizard entry, which reached
  /// its bird by answering questions and has no detection to name.
  var sourceEventId: String?
  var speciesId: String
  var createdAt: Int64
}

/// An outing while it is still happening — the in-memory shape the screens build up and hand
/// to ``JournalRepository/saveOuting(_:)`` in one piece.
///
/// **This is what a draft is now.** There is no half-written outing in the database and no
/// status column saying so: an outing that was never saved is a value that was never passed,
/// and it goes away with the screen that held it. The wizard keeps one in its ui state across
/// three questions; a live session keeps one for the length of the walk. Timestamps and file
/// paths are the repository's to assign, and so is the outing's own id — but each child mints
/// its id on construction, which is what lets a detection point at the photo it came from
/// while both are still values in memory.
nonisolated struct OutingDraft: Sendable {
  var kind: OutingKind
  /// Capture time — when the outing began, not when it was saved.
  var startedAt: Int64
  /// The stop-clock reading for a `live` outing. Nil for `manual`, which has no clock.
  var durationMs: Int64?
  /// No default — an outing without a fix is one the caller should not have built.
  var location: CaptureLocation
  var notes: String?
  var media: [PendingMedia]
  var events: [PendingEvent]
  var sightings: [PendingSighting]

  /// The session's finished strip, as ``SonogramBuffer/encoded()`` wrote it — nil for a wizard
  /// entry, which never heard anything, and nil for a live one whose recording is empty.
  ///
  /// **Not a ``PendingMedia``, deliberately.** The media table holds what was *captured*, and
  /// this was derived from it; giving it a row would mean a row that can point at a missing
  /// file and a second thing to keep in step with the audio. It rides here instead and lands as
  /// a sidecar in the outing's own group, which the existing delete sweep already carries away.
  var sonogram: Data?

  init(
    kind: OutingKind,
    startedAt: Int64,
    durationMs: Int64? = nil,
    location: CaptureLocation,
    notes: String? = nil,
    media: [PendingMedia] = [],
    events: [PendingEvent] = [],
    sightings: [PendingSighting] = [],
    sonogram: Data? = nil
  ) {
    self.kind = kind
    self.startedAt = startedAt
    self.durationMs = durationMs
    self.location = location
    self.notes = notes
    self.media = media
    self.events = events
    self.sightings = sightings
    self.sonogram = sonogram
  }
}

/// Bytes captured during an outing, waiting for the outing to be saved.
///
/// Deliberately **not** `Equatable`, where every other value here is: it carries the raw
/// capture, and comparing two of those byte for byte is never what a caller means. Nothing
/// compares these.
nonisolated struct PendingMedia: Sendable {
  var type: OutingMediaType
  var source: CaptureSource
  var bytes: Data
  /// Always explicit: a capture knows its own format, and a defaulted "jpg" would mislabel HEIF.
  var fileExtension: String
  var offsetMs: Int64?
  var width: Int?
  var height: Int?
  var durationMs: Int64?
  /// Photos only — an audio segment spans many moments and has no single one.
  var moment: MomentContext
  /// Minted here, written through by the repository, and what ``PendingEvent/seen(speciesId:confidence:inPhoto:)``
  /// points at.
  var id: String

  init(
    type: OutingMediaType,
    source: CaptureSource,
    bytes: Data,
    fileExtension: String,
    offsetMs: Int64? = nil,
    width: Int? = nil,
    height: Int? = nil,
    durationMs: Int64? = nil,
    moment: MomentContext = MomentContext(),
    id: String = newDraftId()
  ) {
    self.type = type
    self.source = source
    self.bytes = bytes
    self.fileExtension = fileExtension
    self.offsetMs = offsetMs
    self.width = width
    self.height = height
    self.durationMs = durationMs
    self.moment = moment
    self.id = id
  }
}

/// A timeline pin waiting for its outing. Built through the four factories rather than the
/// initializer, so a caller cannot assemble a `detection` carrying a wizard trait — the
/// per-type column contract is enforced where the row is made, not by convention.
///
/// A detection is **seen or heard, never both**, which is why there are two of it:
/// ``seen(speciesId:confidence:inPhoto:)`` takes the photo and leaves `offsetMs` nil,
/// ``heard(speciesId:confidence:offsetMs:)`` takes the clock reading and leaves `mediaId`
/// nil. Neither can be assembled into the other's shape.
nonisolated struct PendingEvent: Sendable {
  var type: OutingEventType
  var mediaId: String?
  var offsetMs: Int64?
  var speciesId: String?
  var confidence: Double?
  var question: String?
  var answer: String?
  var trait: WizardTrait?
  var value: String?
  /// Minted here, written through by the repository, and what ``PendingSighting`` confirms.
  var id: String

  private init(
    type: OutingEventType,
    mediaId: String? = nil,
    offsetMs: Int64? = nil,
    speciesId: String? = nil,
    confidence: Double? = nil,
    question: String? = nil,
    answer: String? = nil,
    trait: WizardTrait? = nil,
    value: String? = nil,
    id: String = newDraftId()
  ) {
    self.type = type
    self.mediaId = mediaId
    self.offsetMs = offsetMs
    self.speciesId = speciesId
    self.confidence = confidence
    self.question = question
    self.answer = answer
    self.trait = trait
    self.value = value
    self.id = id
  }

  /// A candidate found by looking at a photo. The photo carries the moment — when the
  /// shutter went, and where the camera was aimed — so this row carries neither.
  static func seen(
    speciesId: String,
    confidence: Double,
    inPhoto: PendingMedia
  ) -> PendingEvent {
    PendingEvent(
      type: .detection,
      mediaId: inPhoto.id,
      speciesId: speciesId,
      confidence: confidence
    )
  }

  /// A candidate found by listening. `offsetMs` is the only anchor it has: the
  /// classifier's window is a range on the clock and can straddle a handover, so no
  /// single audio segment is the one it came from.
  static func heard(
    speciesId: String,
    confidence: Double,
    offsetMs: Int64?
  ) -> PendingEvent {
    PendingEvent(
      type: .detection,
      offsetMs: offsetMs,
      speciesId: speciesId,
      confidence: confidence
    )
  }

  /// One Q&A exchange during the outing. Multi-turn is multiple events.
  static func exchange(question: String, answer: String, offsetMs: Int64?) -> PendingEvent {
    PendingEvent(
      type: .qa,
      offsetMs: offsetMs,
      question: question,
      answer: answer
    )
  }

  /// One wizard answer, as provenance for the ID. `value` uses the catalog enums' own
  /// SCREAMING_SNAKE spellings — see ``OutingEvent/value``.
  static func wizardAnswer(trait: WizardTrait, value: String) -> PendingEvent {
    PendingEvent(type: .wizardAnswer, trait: trait, value: value)
  }
}

/// A bird the user confirmed during an outing — the life-list unit, waiting to be saved with
/// it. Confirmation names a species, so `speciesId` is required; an outing with nothing
/// confirmed simply carries none of these, and still saves.
///
/// `confirming` is the detection the watcher accepted, and nil where they reached the bird
/// another way — the wizard has no detection to name. Note that confirming a detection does
/// not mean agreeing with it: a watcher looking at the same photo may name a different bird,
/// and `speciesId` is theirs either way.
///
/// No longer `Equatable`, now that it holds a ``PendingEvent``: comparing a captured event by
/// value is never what a caller means, and nothing compares these anyway.
nonisolated struct PendingSighting: Sendable {
  var speciesId: String
  var confirming: PendingEvent?
  var id: String

  init(
    speciesId: String,
    confirming: PendingEvent? = nil,
    id: String = newDraftId()
  ) {
    self.speciesId = speciesId
    self.confirming = confirming
    self.id = id
  }
}

/// The id a draft child is born with. Row ids and draft ids are one space on purpose: a
/// second one would need a fixing-up pass after the insert, and the links exist precisely so
/// that a screen can wire evidence together before anything is a row.
nonisolated func newDraftId() -> String {
  UUID().uuidString.lowercased()
}
