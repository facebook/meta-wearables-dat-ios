/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemGazeProvider.swift
//  birdspotter
//

import CoreMotion
import Foundation

/// The ``GazeProvider`` the app ships: Core Motion's device attitude, for as long as something is
/// listening.
///
/// The mirror is ``GazeProvider``, not this class — the manager and its handler are the platform
/// plumbing the architecture note keeps idiomatic.
///
/// **Core Motion rather than Core Location, which is the whole reason this is its own provider.**
/// `CLHeading` answers *which way*, and there is no elevation anywhere on it; attitude answers *how
/// high*, and knows nothing about north. Two instruments, two protocols — see ``GazeProvider``.
///
/// A device with no device-motion support ends the stream immediately rather than leaving the caller
/// waiting on a sensor that will never speak, which is exactly the empty stream ``GazeProvider``
/// describes.
@MainActor
final class SystemGazeProvider: GazeProvider {

  private let motion = CMMotionManager()

  /// Which stream the running updates belong to, counted up on every subscription.
  ///
  /// **A stream ending must not tear down the stream that replaced it.** One caller closing and
  /// reopening this provider is the normal case, not an edge one — it is what the session does
  /// every time the glasses take the elevation and every time they give it back. Termination is
  /// delivered asynchronously, so the old stream's cleanup routinely lands *after* the new one
  /// has started the manager, and one manager serves them both: cleanup that does not check
  /// whose it is stops the sensor out from under a live subscriber. The reading goes quiet for
  /// good, and every line in the log says it should be working.
  private var generation = 0

  func gazeStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      guard motion.isDeviceMotionAvailable else {
        continuation.finish()
        return
      }

      // The band is one word and it changes when someone lifts their arm. Twenty a second
      // is already far more than that needs — asking the sensor for a UI-rate feed rather
      // than for everything it has.
      motion.deviceMotionUpdateInterval = gazeUpdateInterval

      // Core Motion's own queue, one operation at a time: the handler reads a value and yields
      // it, and a concurrent queue would only reorder samples that are meant to arrive in the
      // order they were measured.
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = 1

      motion.startDeviceMotionUpdates(to: queue) { update, _ in
        guard let update else { return }
        continuation.yield(elevation(fromGravity: update.gravity) + phonePoseBias)
      }

      generation += 1
      let mine = generation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.stop(ifStillOn: mine) }
      }
    }
  }

  /// Puts the sensor down, but only on behalf of the stream that is still the current one —
  /// see ``generation``.
  private func stop(ifStillOn generation: Int) {
    guard generation == self.generation else { return }
    motion.stopDeviceMotionUpdates()
  }
}

/// How high the phone's camera is aimed, in degrees above the horizon, out of the gravity vector.
///
/// **One component, and Core Motion has already done the fusing.** `gravity` is which way down is,
/// expressed in the device's own axes, so up is its negation — and the camera looks out of the back
/// of the phone, along `-Z`. The camera's elevation above the horizon is therefore how much of the
/// device's `-Z` points at the sky, which after the two negations cancel is simply `gravity.z`. Flat
/// on its back the camera is aimed at the watcher's shoes and this reads `-90`; held upright it
/// reads `0`; face down at the sky, `+90`.
///
/// Clamped before the arcsine because a fused vector can land a hair past ±1, and `asin` of that is
/// `NaN` — one bad sample would otherwise blank the chip.
///
/// The quantity is the same one a rotation matrix carries in a single cell; gravity is simply
/// where this platform publishes it.
nonisolated func elevation(fromGravity gravity: CMAcceleration) -> Double {
  asin(min(max(gravity.z, -1), 1)) * 180 / .pi
}

/// How often the elevation is sampled. Twenty a second: fast enough that the chip turns over as the
/// phone comes up, slow enough that it is not work being done for its own sake.
private let gazeUpdateInterval: TimeInterval = 1.0 / 20.0

/// How far below the watcher's own idea of level this device reads, in degrees.
///
/// **The correction for a pose, applied where the pose is.** A phone aimed at something level is not
/// held vertical: the screen is tipped back towards the face so it can be read, which points the
/// camera down by roughly this much. Left uncorrected, a watcher looking straight out at a bird gets
/// told they are aiming into the understory.
///
/// It lives here rather than in the bands because it is a fact about holding *this* device, and
/// ``gazeBand(_:)`` is about where a bird is. An instrument that points where its wearer looks adds
/// nothing and lands on the same thresholds correctly.
///
/// Worth re-tuning against a few real hands; it is the pose of an average grip, not a measurement.
private let phonePoseBias: Double = 7.5
