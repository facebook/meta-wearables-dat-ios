/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  HeadingProvider.swift
//  birdspotter
//

import Foundation

/// The eight-point compass name for a bearing in degrees clockwise from north.
///
/// Eight points, not sixteen: this answers *which way was the watcher looking*, and `NNW` claims a
/// precision a phone held in one hand while the other holds binoculars does not have. Any bearing
/// is accepted — negative, or past a full turn — because a magnetometer reading arrives as whatever
/// the sensor last computed, and wrapping it is this function's job rather than every caller's.
nonisolated func compassPoint(_ degrees: Double) -> String {
  let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
  // Each point owns 45°, centred on its own bearing — so N runs from 337.5° round to 22.5°, which
  // is what the half-sector offset before the divide buys.
  let wrapped = degrees.truncatingRemainder(dividingBy: 360)
  let positive = wrapped < 0 ? wrapped + 360 : wrapped
  let sector = Int((positive / 45).rounded()) % points.count
  return points[sector]
}

/// Which way the watcher is facing, as a stream of bearings in degrees clockwise from north.
///
/// A stream where ``LocationProvider`` is one shot, and for the same reason each is what it is: a
/// sighting is stamped at one moment and stays stamped, but a heading is only true while you are
/// standing that way, so the screen shows it live and stops showing it when the session ends.
///
/// **Not throwing, and never empty by way of an error.** A phone with no magnetometer, or one whose
/// compass has not settled, produces a stream that simply yields nothing — the same shape as
/// `LocationProvider`'s `nil`, and for the same reason: there is nothing to tell the user about a
/// compass that isn't there beyond not showing them a bearing.
///
/// The protocol is the mirrored surface. The engine behind it — `CLLocationManager` — is the
/// platform plumbing the architecture note keeps idiomatic.
@MainActor
protocol HeadingProvider {
  /// Bearings as they change, in degrees clockwise from north.
  func headingStream() -> AsyncStream<Double>
}
