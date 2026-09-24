/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingWithChildren.swift
//  birdspotter
//

import Foundation

/// An outing and everything that landed on it — what the Journal renders.
///
/// `media` is empty for an outing that captured nothing, or whose only transfer failed —
/// a wizard entry is always this. `sightings` is empty for an outing that confirmed
/// nothing — the Merlin "0 birds, saved anyway" case, which is a first-class journal
/// entry, not a failure.
nonisolated struct OutingWithChildren: Identifiable, Equatable, Sendable {
  var outing: Outing
  var media: [OutingMedia]
  var events: [OutingEvent]
  var sightings: [Sighting]

  var id: String { outing.id }

  var photos: [OutingMedia] { media.filter { $0.type == .photo } }

  var audio: [OutingMedia] { media.filter { $0.type == .audio } }

  // MARK: - Following the evidence links
  //
  // A moment is stored once, on the row that recorded it, and everything downstream
  // reads through. These properties perform that read in one place.
  // Lookups are `first(where:)` rather than dictionaries: an outing's children are two digits.

  /// The capture an event was produced from, or nil when it came from the clock alone.
  func media(for event: OutingEvent) -> OutingMedia? {
    guard let mediaId = event.mediaId else { return nil }
    return media.first { $0.id == mediaId }
  }

  /// The detection a bird was confirmed from, or nil for a wizard entry.
  func sourceEvent(of sighting: Sighting) -> OutingEvent? {
    guard let sourceEventId = sighting.sourceEventId else { return nil }
    return events.first { $0.id == sourceEventId }
  }

  /// Where an event sits on the timeline — its own reading, or its photo's.
  func offset(of event: OutingEvent) -> Int64? {
    event.offsetMs ?? media(for: event)?.offsetMs
  }

  /// Where a confirmed bird sits on the timeline. Nil for an outing with no clock.
  func offset(of sighting: Sighting) -> Int64? {
    sourceEvent(of: sighting).flatMap { offset(of: $0) }
  }

  /// Where the camera was aimed for an event — empty unless a photo is behind it.
  func moment(of event: OutingEvent) -> MomentContext {
    guard let photo = media(for: event) else { return MomentContext() }
    return MomentContext(gazeContext: photo.gazeContext, bearingDeg: photo.bearingDeg)
  }

  /// Where the camera was aimed for a confirmed bird. Empty for anything heard.
  func moment(of sighting: Sighting) -> MomentContext {
    sourceEvent(of: sighting).map { moment(of: $0) } ?? MomentContext()
  }

  /// How confident the detector was **in this bird** — nil unless the watcher confirmed
  /// the species the detection actually proposed.
  ///
  /// A watcher can look at the photo behind an *American Crow, 0.91* and name a Fish Crow.
  /// That 0.91 scored the label they rejected, so returning it here would put a number
  /// against a bird nothing ever scored. This is why the column is not on ``Sighting``: a
  /// copy taken at confirmation time cannot tell the two cases apart afterwards.
  func confidence(of sighting: Sighting) -> Double? {
    guard let event = sourceEvent(of: sighting),
      event.speciesId == sighting.speciesId
    else { return nil }
    return event.confidence
  }

  init(
    outing: Outing,
    media: [OutingMedia] = [],
    events: [OutingEvent] = [],
    sightings: [Sighting] = []
  ) {
    self.outing = outing
    self.media = media
    self.events = events
    self.sightings = sightings
  }
}
