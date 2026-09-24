/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesAim.swift
//  birdspotter
//

import Foundation

// MARK: - The body frame

/// Which way the glasses look, in their own axes.
///
/// **Measured, not assumed.** The sensor documents its units — metres per second squared,
/// microtesla — and not which way its axes point on the frames, so this was read off a worn pair
/// rather than inferred. With a head held still the accelerometer reports a vector of magnitude
/// *g* carrying `0.94`–`0.97` of itself on **X**: the sky axis is `+X`, and the reading is the
/// reaction to gravity rather than gravity itself. **Y** stays within a few hundredths and does
/// not move with pitch, which makes it the lateral axis and leaves `±Z` as the one the wearer
/// looks along. `+Z` is forward: with `-Z` a wearer looking *down* read `+12°` to `+21°`, which is
/// past `canopyDegrees` — the chip said *canopy* at the exact moment the wearer was looking at
/// their feet.
///
/// The earlier guess — `+Y` at the sky, `+X` at the wearer's right, `-Z` forward — was the phone's
/// convention carried across, and it was wrong on every axis but the lateral one.
///
/// **How to re-check it on a different pair, in one sitting:** put the glasses on, look level at
/// something across the room, and read the gaze chip. *Horizon* means this is still right.
/// *Overhead* or *Ground* with a level head means the forward axis is not `+Z` — swap in the axis
/// that reads zero. A chip that moves the wrong way when the wearer looks up means the sign is
/// inverted, not the axis.
private let forward = Vector3(x: 0, y: 0, z: 1)

// MARK: - What a sample says about where the wearer is aiming

/// How high the wearer is looking, in degrees above the horizon — or `nil` when the sample cannot
/// say.
///
/// **Gravity is the whole instrument, and a still head is what makes it one.** At rest an
/// accelerometer reads the reaction to gravity, which points at the sky, so normalising it gives
/// *up* in the glasses' own axes; how much of the forward axis lies along that is the sine of the
/// angle above the horizon. A head that is turning fast adds its own acceleration to the reading
/// and tilts the answer for as long as the turn lasts — acceptable, because the answer is one of
/// five words and a wearer swinging their head is not reading it.
///
/// Answers `nil` only in freefall, where there is no up to be had. Clamped before the arcsine
/// because a normalised vector can land a hair past ±1 through rounding, and `asin` of that is
/// `NaN` — one bad sample would otherwise blank the chip.
nonisolated func elevation(fromAcceleration acceleration: Vector3) -> Double? {
  guard let up = acceleration.normalized else { return nil }
  return asin(min(max(forward.dot(up), -1), 1)) * 180 / .pi
}

/// Which way the wearer is facing, in degrees clockwise from magnetic north — or `nil` when the
/// sample cannot say.
///
/// **Tilt-compensated, because a head is never level.** A magnetometer reports the field in the
/// glasses' own axes, and the field dips steeply into the ground at most latitudes, so the raw
/// reading swings with pitch and roll. Taking gravity as *up*, the horizontal part of the field is
/// north, the cross product of the two is east, and the forward axis flattened into that same plane
/// is the bearing — which is the standard construction and the reason both vectors are needed to
/// answer a question that sounds like it only needs one.
///
/// **Magnetic north, not true.** Correcting it needs a declination this app has no model for, and
/// the difference is single digits over the demo's ground — which the phone's own compass already
/// treats as the honest answer whenever true north is not available to it. A bearing shown as one
/// of eight points is a 45° sector; single digits do not usually move it.
///
/// `nil` covers every way of not knowing: no field reported, a pair in freefall, a field parallel
/// to gravity (which has no horizontal part to call north), and a wearer looking straight up or
/// straight down — where the forward axis has no horizontal part either, and *which way* stops
/// having an answer rather than getting a wrong one.
nonisolated func bearing(fromMotion sample: GlassesMotionSample) -> Double? {
  guard let field = sample.magneticField,
    let up = sample.acceleration.normalized,
    let north = field.perpendicular(to: up)?.normalized,
    let aim = forward.perpendicular(to: up)?.normalized
  else { return nil }

  let east = north.cross(up)
  let degrees = atan2(aim.dot(east), aim.dot(north)) * 180 / .pi
  return degrees < 0 ? degrees + 360 : degrees
}

// MARK: - The providers

/// The ``GazeProvider`` backed by the glasses' own IMU.
///
/// A wearer's head is the thing actually aimed at the bird, which is what makes this the better
/// answer than the phone's attitude whenever it is available — the phone reports where the *phone*
/// is pointing, and a watcher looking up while their hand hangs at their side is a watcher the
/// phone reads as staring at the grass.
///
/// Samples that cannot answer are dropped rather than published as a value, so the chip keeps the
/// last stratum it had instead of flickering to nothing at the top of a swing.
@MainActor
final class GlassesGazeProvider: GazeProvider {

  private let motion: any GlassesMotionRepository

  init(motion: any GlassesMotionRepository) {
    self.motion = motion
  }

  func gazeStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      let task = Task { [motion] in
        for await sample in motion.motionStream() {
          guard let degrees = elevation(fromAcceleration: sample.acceleration) else {
            continue
          }
          continuation.yield(degrees)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// The ``HeadingProvider`` backed by the glasses' own IMU.
///
/// The same argument the gaze provider makes: the bearing worth stamping on a photograph is the
/// one the camera that took it was pointing along, and on a glasses capture that camera is on the
/// wearer's face.
///
/// **A pair with no magnetometer ends the stream rather than going quiet on it**, and the
/// difference matters more than it looks. Silence and *there is no compass here* are the same thing
/// to anything waiting on a value, so a pair that reports motion without a field would hold the
/// failover open forever on a bearing that is never coming — and the phone's compass, which was
/// working, would never be asked again. A sample that arrives without a field is a fact about the
/// hardware, so it ends this stream and hands the question back.
///
/// The other silences are transient and stay silent: the bearing is undefined at the top and bottom
/// of a swing, where *which way* stops having an answer for a moment rather than for good.
@MainActor
final class GlassesHeadingProvider: HeadingProvider {

  private let motion: any GlassesMotionRepository

  init(motion: any GlassesMotionRepository) {
    self.motion = motion
  }

  func headingStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      let task = Task { [motion] in
        for await sample in motion.motionStream() {
          guard sample.magneticField != nil else { break }
          guard let degrees = bearing(fromMotion: sample) else { continue }
          continuation.yield(degrees)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

// MARK: - Vector arithmetic

/// The three operations the two derivations above are built from. Kept here rather than on
/// ``Vector3`` itself so the domain type stays what it says it is — a triple, in whatever unit the
/// thing it measures is measured in — and the geometry lives with the geometry.
extension Vector3 {

  fileprivate var length: Double { (x * x + y * y + z * z).squareRoot() }

  /// The same direction at unit length, or `nil` for a vector too short to have a direction.
  /// The threshold is well under any real reading and well over the rounding noise around zero.
  fileprivate var normalized: Vector3? {
    let length = length
    guard length > 1e-9 else { return nil }
    return Vector3(x: x / length, y: y / length, z: z / length)
  }

  fileprivate func dot(_ other: Vector3) -> Double {
    x * other.x + y * other.y + z * other.z
  }

  fileprivate func cross(_ other: Vector3) -> Vector3 {
    Vector3(
      x: y * other.z - z * other.y,
      y: z * other.x - x * other.z,
      z: x * other.y - y * other.x
    )
  }

  /// This vector with everything along `axis` taken out of it — its shadow on the plane `axis`
  /// stands on. `nil` when nothing measurable is left, which is what a vector parallel to the
  /// axis reduces to.
  fileprivate func perpendicular(to axis: Vector3) -> Vector3? {
    let along = dot(axis)
    let flattened = Vector3(
      x: x - along * axis.x,
      y: y - along * axis.y,
      z: z - along * axis.z
    )
    return flattened.length > 1e-9 ? flattened : nil
  }
}
