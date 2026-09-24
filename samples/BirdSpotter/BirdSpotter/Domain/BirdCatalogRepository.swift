/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdCatalogRepository.swift
//  birdspotter
//

import Foundation

/// What the identify wizard learned from its questions — everything the catalog can
/// actually filter on.
///
/// Deliberately *not* the whole questionnaire: the wizard also asks where and when, but
/// those stamp the resulting sighting rather than narrow the guide. The catalog has no
/// region or seasonality data, and filtering on data we don't have
/// would just be a bug wearing a feature's clothes.
nonisolated struct IdentifyQuery: Equatable, Sendable {
  /// 1-7 on the sparrow-to-goose scale; matched within one stop either way.
  var sizeClass: Int
  /// Every color here must be on the bird. 1-3 picks, per the wizard's color step.
  var colors: Set<PlumageColor>
  var behavior: BirdBehavior
}

/// The shipped field guide — 93 species, their photos, and one reference vocalization
/// each, read out of `catalog.db`.
///
/// Read-only by construction. Nothing in the app writes a species, which is what lets the
/// whole file be discarded and re-copied on a seed bump; ``JournalRepository`` is the
/// app's only writer, into a separate file.
///
/// Every method is a plain `async` read rather than a stream. The catalog cannot change
/// while the app is running, so an observed query would yield once and then sit there
/// pretending to be live — the `*Stream()` convention is for sources that actually move.
nonisolated protocol BirdCatalogRepository: Sendable {

  /// The full guide, alphabetical by common name.
  func allSpecies() async throws -> [Species]

  /// The full guide in checklist sequence, split into the sections a field guide prints
  /// — *Birds of Prey*, *Woodpeckers*, *Warblers* — each with its species' media.
  ///
  /// Both the order and the section names come out of the seed, not out of code here:
  /// see ``Species/browseOrder`` and ``Species/groupName``. Groups arrive in the order
  /// they are meant to be read, never empty, and never repeated.
  func browseGroups() async throws -> [SpeciesGroup]

  /// A species and its bundled media, or nil for an unknown id.
  ///
  /// Nil is the expected answer for a `Sighting.speciesId` that no longer resolves —
  /// that is an unidentified sighting, not an error.
  func findById(_ speciesId: String) async throws -> SpeciesWithMedia?

  /// The species matching an identify-wizard `query`, in checklist sequence.
  ///
  /// Checklist order rather than a ranking: we have no likelihood data, and a fake
  /// confidence sort would imply precision the guide doesn't have. Empty is an honest
  /// answer — the wizard shows it as "no matches" with a way back, never as an error.
  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia]

  /// The species featured on a given day, by `epochDay` — days since 1970-01-01 in
  /// whatever timezone the caller considers local.
  ///
  /// A day number rather than a `Date` so the two platforms compute the same answer
  /// from the same input and neither has to agree with the other about calendars or
  /// clocks. Deciding which day it is belongs to the caller; this only maps a day to a
  /// bird. Nil only when the catalog is empty.
  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia?

  /// `AppMeta.seed.version` from the installed catalog. Nil if absent.
  func seedVersion() async throws -> Int?
}

/// Which species ``BirdCatalogRepository/birdOfTheDay(epochDay:)`` lands on: a fixed
/// stride through `count` species in slug order.
///
/// **Mirrored verbatim**, down to the integer arithmetic, so a given day features the same
/// bird on every phone — worth more than it sounds, since a demo runs two of them side by
/// side.
///
/// Two properties are wanted at once, and one constant gets both:
///
/// - **Consecutive days look unrelated.** Stepping by 1 walks the guide in slug order, so
///   a week of demos would open on American Crow, American Goldfinch, American Kestrel.
///   Striding by roughly `count/φ` — the golden ratio, in integer arithmetic so no
///   floating-point rounding can differ across platforms — spreads each day far from the
///   last (for 93 species: 2, 58, 21, 77, 40, …).
/// - **Every bird appears before any repeats.** Because the stride is reduced until it is
///   coprime with `count`, the mapping is a bijection and the rotation is a full cycle.
///
/// A general-purpose hash would have satisfied the first and quietly lost the second.
/// Deriving the stride from `count` rather than fixing it also means adding species can
/// never degrade the walk: a literal constant only has to happen to be `1 mod count` — as
/// Knuth's 2654435761 is, for exactly 93 species — to collapse back into alphabetical order.
///
/// `epochDay` is floor-modded, so days before 1970 are meaningless but never negative.
nonisolated func birdOfTheDayIndex(epochDay: Int64, count: Int) -> Int {
  precondition(count > 0, "birdOfTheDayIndex needs a non-empty catalog")
  let modulus = Int64(count)
  // Swift's % truncates toward zero rather than flooring. Adding the modulus back is what
  // makes a negative day number land on the same index a floored remainder would.
  let day = ((epochDay % modulus) + modulus) % modulus
  return Int(day * Int64(rotationStride(count: count)) % modulus)
}

/// Largest stride at or below `count/φ` that shares no factor with `count`.
private nonisolated func rotationStride(count: Int) -> Int {
  // φ⁻¹ as a scaled integer: 0.6180339887, ten digits, no floating point involved.
  var stride = max(Int(Int64(count) * 6_180_339_887 / 10_000_000_000), 1)
  while greatestCommonDivisor(stride, count) != 1 {
    stride -= 1
  }
  return stride
}

private nonisolated func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
  b == 0 ? a : greatestCommonDivisor(b, a % b)
}
