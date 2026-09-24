/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesMotionRepository.swift
//  birdspotter
//

import Foundation

/// Three components in the glasses' own axes. Whatever the sample measured, in whatever unit that
/// quantity is measured in — this type carries the triple and nothing else.
nonisolated struct Vector3: Equatable, Sendable {
  let x: Double
  let y: Double
  let z: Double
}

/// One reading off the glasses' motion sensors.
///
/// **Two fields, where the sensor offers five.** The pair also report a gyroscope and a fused
/// orientation quaternion, and neither is here: this app asks the IMU exactly two questions — *how
/// high is the wearer looking* and *which way are they facing* — and both are answered by where
/// down is and where magnetic north is. A rate of turn has no reader, and a quaternion is expressed
/// against a reference frame the sensor does not document, which would make it the one value in the
/// app whose meaning nobody could check. Adding either is a line in the data layer the day
/// something needs it.
///
/// Samples arriving from anything other than the glasses are dropped before they reach here. A
/// single motion feed can interleave two rigid bodies, and averaging a head with a wrist produces a
/// number that describes neither.
nonisolated struct GlassesMotionSample: Equatable, Sendable {
  /// Proper acceleration in m/s², gravity included — so a still pair reads roughly `9.81`
  /// along whichever axis is pointing at the sky.
  let acceleration: Vector3

  /// The magnetic field in µT, or `nil` when this pair does not report one.
  ///
  /// Optional at the source and therefore optional here. A compass derived from it is
  /// best-effort by construction, which is why ``HeadingProvider`` is allowed to say nothing.
  let magneticField: Vector3?

  init(acceleration: Vector3, magneticField: Vector3? = nil) {
    self.acceleration = acceleration
    self.magneticField = magneticField
  }
}

/// The glasses' motion sensors, for as long as something is listening.
///
/// A cold stream, like every other sense the session opens: iterating starts the sensor and
/// cancelling stops it, so a screen that has gone away is not one still costing the wearer battery.
///
/// **Not throwing, and never empty by way of an error.** A pair with no session, no IMU, or a
/// capability that refused to attach produces a stream that simply yields nothing — the same shape
/// ``HeadingProvider`` and ``GazeProvider`` already use, and for the same reason: there is nothing
/// to tell a watcher about a sensor that isn't there beyond not showing them a reading.
@MainActor
protocol GlassesMotionRepository {
  /// Readings as they are measured.
  func motionStream() -> AsyncStream<GlassesMotionSample>
}
