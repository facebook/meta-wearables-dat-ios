/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LocationProvider.swift
//  birdspotter
//

import Foundation

/// A WGS84 point — latitude and longitude in degrees.
///
/// It lives beside the protocol that produces it, the way ``IdentifyQuery`` sits with
/// ``BirdCatalogRepository``. The offline-map proposal projects the same `Coordinate` for its
/// region polygons, so the name is chosen to serve both when that lands.
nonisolated struct Coordinate: Equatable, Sendable {
  var latitude: Double
  var longitude: Double
}

/// The phone's GPS, as one honest question: *where are we, right now?*
///
/// One shot, not a stream — a sighting is stamped once, at the moment it is logged, so the
/// wizard asks for a single fix rather than subscribing to movement. The protocol is the
/// mirrored surface; the engine behind it — `CLLocationManager` — is location plumbing the
/// architecture note keeps idiomatic, the same call it makes for ``AudioClipPlayer``'s engine.
///
/// `nil` is the whole failure surface: authorization not granted, location services off, or no
/// fix before the attempt gives up. Gating the Identify tab on the permission narrows the first
/// of those and removes none of the others. An outing whose fix never arrived simply carries no
/// coordinates — ``Outing/latitude`` and ``Outing/longitude`` are nullable for exactly this
/// — so a caller treats `nil` as "no stamp", never as an error to handle.
@MainActor
protocol LocationProvider {
  /// The current position, or `nil` if it cannot be obtained (denied, disabled, or timed out).
  func currentCoordinate() async -> Coordinate?
}
