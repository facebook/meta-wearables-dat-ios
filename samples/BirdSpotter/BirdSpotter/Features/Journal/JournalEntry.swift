/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalEntry.swift
//  birdspotter
//

import Foundation

/// A confirmed bird paired with its catalog entry.
///
/// `species` is nil when the sighting's `speciesId` no longer resolves — legitimate, per
/// ``JournalRepository``, and rendered as unlabeled rather than as an error. Labeling walks
/// past an unresolvable bird the way it walks past an outing that confirmed nothing.
nonisolated struct ConfirmedBird: Identifiable, Equatable, Sendable {
  var sighting: Sighting
  /// The resolved catalog bird, or nil when the id no longer resolves.
  var species: SpeciesWithMedia?

  var id: String { sighting.id }
}

/// One line of the Journal: an outing joined with the birds it confirmed.
///
/// The store hands up an ``OutingWithChildren`` — the root row and everything that landed
/// on it — but not the birds, because `speciesId` points across into `catalog.db` and the
/// two files don't join in SQL. ``JournalViewModel`` resolves each confirmed sighting
/// against the catalog and pairs them here, so a row or the detail screen has everything
/// it draws in one value.
///
/// `birds` is in story order — earliest confirmed first — which is what makes
/// ``primaryBird`` "the outing's first trophy" rather than an arbitrary row. Empty is the
/// Merlin case: an outing saved with nothing confirmed.
nonisolated struct JournalEntry: Identifiable, Equatable, Sendable {
  var withChildren: OutingWithChildren
  /// Confirmed birds in story order, resolved against the catalog.
  var birds: [ConfirmedBird]

  var id: String { withChildren.outing.id }

  /// The stored root — `startedAt`, `kind`, the coordinates, `notes`, and the rest.
  var outing: Outing { withChildren.outing }

  /// The files the outing actually left behind. Empty for a `manual` entry.
  var photos: [OutingMedia] { withChildren.photos }
  var audio: [OutingMedia] { withChildren.audio }

  /// The bird that names this entry — the earliest confirmed one the catalog still
  /// resolves. Nil when nothing was confirmed (or nothing resolves), in which case the
  /// entry is named by its date.
  var primaryBird: ConfirmedBird? { birds.first { $0.species != nil } }

  /// How many confirmed birds ride behind ``primaryBird`` — the "+ n more" count.
  var extraBirdCount: Int {
    guard primaryBird != nil else { return 0 }
    return birds.count { $0.species != nil } - 1
  }

  /// The pin this entry drops on a map. Never nil: an outing knows where it happened or
  /// it was never saved. The title is the primary bird, or a plain word when nothing
  /// resolved — the entry is still a place the watcher stood.
  var location: SightingLocation {
    SightingLocation(
      coordinate: Coordinate(latitude: outing.latitude, longitude: outing.longitude),
      title: primaryBird?.species?.species.commonName ?? "Outing"
    )
  }

  /// Story order for confirmed birds: by moment on the timeline, then by write order
  /// for rows with no clock (`manual`, and ties). One definition, used by the list and
  /// the detail screen, so "the first bird" never disagrees between them.
  ///
  /// Takes the whole outing rather than its sightings because a moment is not a column
  /// on a ``Sighting`` any more — it is read down the evidence links, and only the
  /// outing's children have what that needs.
  static func storyOrder(_ withChildren: OutingWithChildren) -> [Sighting] {
    withChildren.sightings.sorted { lhs, rhs in
      let lhsOffset = withChildren.offset(of: lhs) ?? Int64.max
      let rhsOffset = withChildren.offset(of: rhs) ?? Int64.max
      if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
      return lhs.createdAt < rhs.createdAt
    }
  }
}

/// A month's worth of outings, under one heading in the Journal.
///
/// `key` is the stable, sortable bucket ("2026-07") that also serves as the section's
/// identity; `title` is what the heading prints ("July 2026"). The Journal lists months
/// newest first, and the entries within each newest first, which is the order
/// ``JournalViewModel/groupByMonth(_:calendar:)`` builds them in.
nonisolated struct JournalMonth: Identifiable, Equatable, Sendable {
  var key: String
  var title: String
  var entries: [JournalEntry]

  var id: String { key }
}
