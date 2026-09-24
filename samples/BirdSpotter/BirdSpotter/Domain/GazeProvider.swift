/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GazeProvider.swift
//  birdspotter
//

import Foundation

/// The stratum an elevation is aimed at, named the way a birder would name it.
///
/// **A band, not a number.** `+37°` is a fact about a phone; *canopy* is a fact about where a bird
/// would be, and it is the one a watcher can act on. It is also the reason this is five names
/// rather than a degree readout: a number would twitch at sensor rate on a screen already carrying
/// a moving sonogram, and it would never settle while a hand holds the phone.
///
/// **It returns ``GazeContext``, not a label.** This is the same value the journal stores against a
/// photo or a detection, so the reading a watcher was shown while aiming is exactly the one written
/// down beside what they caught. It used to hand back a `String`, which left no way for the two to
/// be the same thing and let their vocabularies drift apart — the chip said *Horizon* where the
/// journal said *Eye level*. Turning degrees into words is
/// ``JournalFormatting/gazeLabel(_:)``'s job, in one place.
///
/// The bands are **symmetric about zero, and that is the geometry rather than any one instrument's
/// habits**. Five strata, four thresholds, 35° apart: *horizon* owns the level line and the two
/// pairs either side of it are mirror images, because looking 30° up and 30° down are the same
/// distance from level whatever is doing the looking.
///
/// **An instrument that is not aimed where it reads corrects itself before it gets here.** A phone
/// is the case that has one: it is tipped back towards the face to be read, which points its camera
/// slightly below whatever the watcher means by level, and the fix for that is a bias on the phone's
/// own readings rather than a set of bands bent to fit one way of holding one device. Something worn
/// on a face has no such offset — it points where the wearer looks — so it reports what it measures
/// and lands on these thresholds unaltered. The thresholds are the geometry; the pose belongs to
/// whatever has one.
///
/// Any elevation is accepted, including past the poles, because it arrives as whatever the sensor
/// last computed and clamping it is this function's job rather than every caller's.
nonisolated func gazeBand(_ degrees: Double) -> GazeContext {
  switch degrees {
  case overheadDegrees...: .overhead
  case canopyDegrees...: .canopy
  case horizonDegrees...: .horizon
  case understoryDegrees...: .understory
  default: .ground
  }
}

/// Straight up, or near enough: sky, and whatever is crossing it.
private let overheadDegrees: Double = 52.5

/// Up into the branches — where most of a session's birds are.
private let canopyDegrees: Double = 17.5

/// Level, give or take.
private let horizonDegrees: Double = -17.5

/// Down into the scrub, below eye line but not at one's feet.
private let understoryDegrees: Double = -52.5

/// How high the watcher is aiming, as a stream of elevations in degrees above the horizon: `0` is
/// level, `+90` is straight up, `-90` is straight down.
///
/// A stream, and a live one, for the same reason ``HeadingProvider`` is: this says where they are
/// looking *now*. The stream itself is never recorded — where a watcher was pointing four minutes
/// ago, on its own, is not a fact worth keeping — but the reading *at a moment something happened*
/// very much is, and that is the ``GazeContext`` the journal stores against a photo or a detection.
/// Sampled at the moment, never replayed from a track.
///
/// Separate from ``HeadingProvider`` rather than folded into it, because the two are separate
/// instruments on both platforms: the bearing comes off `CLLocationManager`, which has no elevation
/// to give, and this comes from Core Motion instead. One protocol carrying both would be one
/// protocol that could only ever be half-answered.
///
/// **Not throwing, and never empty by way of an error.** A phone that cannot answer produces a
/// stream that simply yields nothing — the same shape as ``HeadingProvider``'s silence, and for the
/// same reason.
///
/// The protocol is the mirrored surface. The engine behind it — `CMMotionManager` — is the
/// platform plumbing the architecture note keeps idiomatic.
@MainActor
protocol GazeProvider {
  /// Elevations as they change, in degrees above the horizon.
  func gazeStream() -> AsyncStream<Double>
}
