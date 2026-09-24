/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemHeadingProvider.swift
//  birdspotter
//

import CoreLocation
import Foundation

/// The ``HeadingProvider`` the app ships: `CLLocationManager`'s heading updates, for as long as
/// something is listening.
///
/// The mirror is ``HeadingProvider``, not this class — the manager and its delegate are the
/// platform plumbing the architecture note keeps idiomatic.
///
/// **True north where there is one, magnetic otherwise.** `trueHeading` is only valid once location
/// updates are running and the device knows its declination; until then it reads negative, and the
/// magnetic bearing is the honest answer rather than a wrong one. Both are degrees clockwise from
/// their own north and only ever differ by declination — single digits over the demo's ground.
///
/// A device with no magnetometer never calls the delegate at all, which is exactly the empty stream
/// ``HeadingProvider`` describes: `headingAvailable()` returning false ends it immediately rather
/// than leaving the caller waiting on a sensor that will never speak. The Simulator is that case.
@MainActor
final class SystemHeadingProvider: NSObject, HeadingProvider, CLLocationManagerDelegate {

  private let manager = CLLocationManager()

  /// The sink for the current stream, or `nil` when nobody is listening. One at a time: the
  /// session is the only caller and a second would be a second compass on one screen.
  private var continuation: AsyncStream<Double>.Continuation?

  /// Which stream the sink belongs to, counted up on every subscription.
  ///
  /// **A stream ending must not tear down the stream that replaced it.** One caller closing and
  /// reopening this provider is the normal case, not an edge one — it is what the session does
  /// every time the glasses take the compass and every time they give it back. Termination is
  /// delivered asynchronously, so the old stream's cleanup routinely lands *after* the new one
  /// has stored its sink and started the manager, and cleanup that does not check whose it is
  /// then stops the hardware and nils the sink that a live subscriber is waiting on. The reading
  /// goes quiet for good, and every line in the log says it should be working.
  private var generation = 0

  override init() {
    super.init()
    manager.delegate = self
    // A bearing shown as one of eight points does not need to be redrawn for two degrees of
    // wobble; this is the coarsest filter that still turns the plate over promptly.
    manager.headingFilter = 5
  }

  func headingStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      guard CLLocationManager.headingAvailable() else {
        continuation.finish()
        return
      }
      generation += 1
      let mine = generation
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.stop(ifStillOn: mine) }
      }
      manager.startUpdatingHeading()
    }
  }

  /// Puts the compass down, but only on behalf of the stream that is still the current one —
  /// see ``generation``.
  private func stop(ifStillOn generation: Int) {
    guard generation == self.generation else { return }
    manager.stopUpdatingHeading()
    continuation = nil
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
  ) {
    // `trueHeading` is negative until declination is known; magnetic is what there is until it.
    let bearing =
      newHeading.trueHeading >= 0
      ? newHeading.trueHeading
      : newHeading.magneticHeading
    guard bearing >= 0 else { return }
    Task { @MainActor in self.continuation?.yield(bearing) }
  }

  nonisolated func locationManagerShouldDisplayHeadingCalibration(
    _ manager: CLLocationManager
  ) -> Bool {
    // Never. The calibration sheet is a full-screen interruption over a running session, and a
    // bearing that is a few degrees out still names the same one of eight points.
    false
  }
}
