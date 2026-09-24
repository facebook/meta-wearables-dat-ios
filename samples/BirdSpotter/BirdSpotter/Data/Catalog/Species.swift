/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  Species.swift
//  birdspotter
//

import Foundation
import GRDB

/// What a bundled asset is.
///
/// `song` and `call` are both audio and both play through the same control; the
/// distinction is a field-guide one (a song is territorial and musical, a call is short
/// and functional) and each species ships whichever it is actually known for.
///
/// `sonogram` is a spectrogram *of* that clip — the picture a field guide prints beside a
/// bird's voice. It is an image, so it never plays and is never ``SpeciesMedia/isPrimary``;
/// the seed pipeline renders it from the trimmed audio we ship, which is why it always
/// matches what the play button does.
nonisolated enum SpeciesMediaType: String, Codable, Sendable, DatabaseValueConvertible {
  case photo = "PHOTO"
  case song = "SONG"
  case call = "CALL"
  case sonogram = "SONOGRAM"
}

/// IUCN Red List category, as harvested from Wikidata P141.
///
/// Optional on ``Species`` rather than defaulting to ``notEvaluated``: a handful of birds
/// have no P141 at all, and "we have no data" is a different claim from "the IUCN assessed
/// this and declined to rank it". Only ``leastConcern``, ``nearThreatened`` and
/// ``vulnerable`` occur in the shipped guide today; the rest exist so a future species
/// cannot fall through to blank unnoticed.
nonisolated enum ConservationStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
  case leastConcern = "LEAST_CONCERN"
  case nearThreatened = "NEAR_THREATENED"
  case vulnerable = "VULNERABLE"
  case endangered = "ENDANGERED"
  case criticallyEndangered = "CRITICALLY_ENDANGERED"
  case extinctInTheWild = "EXTINCT_IN_THE_WILD"
  case extinct = "EXTINCT"
  case dataDeficient = "DATA_DEFICIENT"
  case notEvaluated = "NOT_EVALUATED"
}

/// One species in the shipped field guide.
///
/// Read-only at runtime: every row here comes from the bundled catalog
/// via the seed pipeline, and the whole file is replaced on a seed bump. Nothing the user
/// makes is ever written to this table — that is ``Sighting``'s job, in a separate file.
///
/// `id` is a stable slug (`northern-cardinal`) referenced by `Sighting.speciesId` across
/// the file boundary. **Once shipped, a species id is never renamed or removed** —
/// renaming one silently orphans every sighting logged against it.
nonisolated struct Species: Codable, Identifiable, Equatable, Sendable, FetchableRecord {
  static let databaseTableName = "Species"

  var id: String
  var commonName: String
  var scientificName: String
  /// Wikidata QID (`Q862896`) — the catalog's stable join key for the facts and media
  /// the seed pipeline harvests. Kept apart from ``scientificName`` on purpose: a QID
  /// survives a genus split, so it still points at Cooper's Hawk after the bird moved
  /// from `Accipiter` to `Astur`, where the display name stopped matching. Optional only
  /// so a half-authored species can exist mid-edit; the seed build gates on it being
  /// present and resolvable before ship.
  var wikidataId: String?
  /// eBird/Clements species code (`coohaw`) — the stable join key for occurrence data
  /// (eBird, and GBIF through it). Six characters the taxonomy-revision process is
  /// designed to hold fixed while scientific names churn, which is exactly why a join
  /// keys on this and not on ``scientificName``. Optional and gated like ``wikidataId``.
  var ebirdSpeciesCode: String?
  /// e.g. `Cardinalidae`.
  var familyName: String
  /// Position in the guide, in checklist sequence — what Explore's browse list sorts by.
  ///
  /// Curated in `species.csv` with gaps of 10, so slotting a bird in between two others
  /// is one row's edit rather than a renumber of everything after it. Alphabetical by
  /// `commonName` was the alternative and it reads like a phone book: five `American …`
  /// in a row, each from a different family.
  var browseOrder: Int
  /// The section header this species falls under, e.g. `Birds of Prey`.
  ///
  /// Stored on the row rather than derived from ``familyName`` in code, because the
  /// mapping is editorial — 34 families collapse to 22 groups — and re-deriving that
  /// judgement in app code is exactly the kind of drift the mirroring rule exists to
  /// prevent. Species sharing a group are contiguous in ``browseOrder``; the seed
  /// build enforces it.
  var groupName: String
  /// Apparent size on the identify wizard's 1-7 scale: 1 sparrow-sized or smaller,
  /// 3 robin-sized, 5 crow-sized, 7 goose-sized or larger; even numbers are the
  /// in-between stops. A number rather than a TEXT enum because the wizard matches a
  /// *window* (`BETWEEN picked-1 AND picked+1` — nobody judges size against a
  /// silhouette more precisely than that), and ranges need ordering.
  var sizeClass: Int
  /// IUCN Red List category, or nil where Wikidata has no assessment for the species.
  ///
  /// A field-guide fact rather than a filter — nothing queries it. Note that 83 of the
  /// 93 shipped birds are ``ConservationStatus/leastConcern``, so a card that prints this
  /// unconditionally is mostly printing the same phrase; the interesting reading is the
  /// four that are not.
  var conservationStatus: ConservationStatus?
  var aboutText: String
  var habitatText: String
}

/// A main plumage color the identify wizard can ask about — the nine swatches on its
/// color step. Broad on purpose: a birder at a window says "black and orange", not
/// "rufous"; anything finer would need the user to know the answer the wizard exists
/// to find.
nonisolated enum PlumageColor: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
  case black = "BLACK"
  case gray = "GRAY"
  case white = "WHITE"
  case brown = "BROWN"
  case red = "RED"
  case orange = "ORANGE"
  case yellow = "YELLOW"
  case green = "GREEN"
  case blue = "BLUE"
}

/// What the bird was doing / where it was — the identify wizard's final step, one
/// answer per flow. The six cases are encounter contexts a non-birder can answer
/// confidently, not an ethogram.
nonisolated enum BirdBehavior: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
  case atFeeder = "AT_FEEDER"
  case swimmingOrWading = "SWIMMING_OR_WADING"
  case onGround = "ON_GROUND"
  case inTreesOrBushes = "IN_TREES_OR_BUSHES"
  case onFenceOrWire = "ON_FENCE_OR_WIRE"
  case soaringOrFlying = "SOARING_OR_FLYING"
}

/// One main color of one species — the identify wizard's color filter, seeded from
/// the bundled catalog.
///
/// A species carries 1-4 rows covering typical adults of both sexes (a cardinal is RED,
/// BLACK, *and* the female's BROWN), so describing either sex finds the bird. Tagging is
/// deliberately generous: a missing color silently excludes the species from results.
nonisolated struct SpeciesColor: Codable, Equatable, Sendable, FetchableRecord {
  static let databaseTableName = "SpeciesColor"

  var speciesId: String
  var color: PlumageColor
}

/// One encounter context a species is typically found in — the identify wizard's
/// behavior filter, seeded from the bundled catalog. Same
/// generosity rule as ``SpeciesColor``: tag every plausible context, because absence
/// excludes.
nonisolated struct SpeciesBehavior: Codable, Equatable, Sendable, FetchableRecord {
  static let databaseTableName = "SpeciesBehavior"

  var speciesId: String
  var behavior: BirdBehavior
}

/// Where the subject of a photograph sits, as fractions of the image's width and height
/// measured from the top-left corner — `FocalPoint(x: 0.5, y: 0.5)` is dead center.
///
/// A value, not a rectangle: the frames a photo lands in (4:3 plates, square thumbnails)
/// have shapes the catalog cannot know, so the catalog records the one thing that is true
/// of the *image* — where the bird is — and each frame crops toward it.
nonisolated struct FocalPoint: Equatable, Sendable {
  var x: Double
  var y: Double
}

/// A bundled photo or reference vocalization.
///
/// `assetKey` is a *logical* key (`northern-cardinal/photo-01`), never a stored path —
/// where the file actually lives is a bundling detail, and ``CatalogAssetStore`` is what
/// resolves it. Storing a path would bake one build's layout into the shipped database.
///
/// `credit` is displayed, not decorative: everything bundled is openly licensed on the
/// condition that the photographer or recordist is named.
nonisolated struct SpeciesMedia: Codable, Identifiable, Equatable, Sendable, FetchableRecord {
  static let databaseTableName = "SpeciesMedia"

  var id: String
  var speciesId: String
  var type: SpeciesMediaType
  /// Logical key, resolved per platform. No file extension — see ``CatalogAssetStore``.
  var assetKey: String
  /// Photographer / recordist. Nullable in the schema; in practice always present.
  var credit: String?
  /// The hero photo, and the call played by default. One of each per species.
  /// A ``SpeciesMediaType/sonogram`` is never primary — it illustrates the clip.
  var isPrimary: Bool
  /// Where the bird sits in the photograph — fractions of its width and height from the
  /// top-left, curated in the bundled catalog. Photos only, and
  /// nil where nobody has marked one; a nil crops from the center, exactly as every
  /// photo did before the column existed. Harvested photos put the bird anywhere, so a
  /// center crop routinely beheads it — this is the datum that lets a frame crop toward
  /// the subject instead.
  var focusX: Double?
  var focusY: Double?
  /// Audio only.
  var durationMs: Int64?
  /// The sex of the bird in the recording — audio only, and nil more often than not.
  ///
  /// Free text (`male`, `female`, `uncertain`, …) rather than an enum because that is
  /// what Xeno-canto stores, and a caption reads better honest than forced into cases
  /// the recordist never chose between.
  var sex: String?
  /// Life stage of the bird in the recording (`adult`, `juvenile`, …). Audio only.
  var stage: String?
  var sortOrder: Int

  /// The point a cropped rendering keeps in frame: the curated mark, or dead center.
  var focalPoint: FocalPoint {
    FocalPoint(x: focusX ?? 0.5, y: focusY ?? 0.5)
  }
}

/// Facts about the seed itself — `seed.version` and `seed.builtAt`, written by the
/// pipeline and only ever read by the app.
///
/// `seed.version` is what ``CatalogDatabase/open(at:)`` compares to decide whether the
/// shipped catalog supersedes the installed one.
nonisolated struct AppMeta: Codable, Identifiable, Equatable, Sendable, FetchableRecord {
  static let databaseTableName = "AppMeta"

  var key: String
  var value: String

  var id: String { key }
}
