/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemLocationProvider.swift
//  birdspotter
//

import CoreLocation
import Foundation

/// The ``LocationProvider`` the app ships: one `CLLocationManager` fix per call.
///
/// The mirror is ``LocationProvider``, not this class — the manager and the authorization dance are
/// the platform plumbing the architecture note keeps idiomatic.
///
/// Authorization is the Identify gate's concern, not this type's: the wizard is reachable only
/// once `location` is granted, so ``currentCoordinate()`` assumes it and returns `nil` rather than
/// prompting if it finds otherwise. `requestLocation()` delivers exactly one fix — through
/// `didUpdateLocations` on success or `didFailWithError` on a timeout or a denied service — which
/// is the whole reason a one-shot needs no manual timer.
@MainActor
final class SystemLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {

  private let manager = CLLocationManager()

  /// The single in-flight `currentCoordinate()` call, resumed by the first delegate callback.
  private var pending: CheckedContinuation<Coordinate?, Never>?

  override init() {
    super.init()
    manager.delegate = self
    // A sighting is stamped where the watcher stood, not surveyed — hundred-metre accuracy is
    // plenty and spares the battery a high-accuracy lock the journal would only round off.
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func currentCoordinate() async -> Coordinate? {
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways: break
    // Not our gate to open: unauthorized is "no stamp", the same nil a failed fix returns.
    default: return nil
    }
    // One request at a time; a second caller gets nil rather than racing the delegate for the
    // continuation. The wizard only ever asks once, so this is a guard, not a queue.
    guard pending == nil else { return nil }
    return await withCheckedContinuation { continuation in
      pending = continuation
      manager.requestLocation()
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    let fix = locations.last.map {
      Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
    }
    Task { @MainActor in self.resume(with: fix) }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didFailWithError error: Error
  ) {
    Task { @MainActor in self.resume(with: nil) }
  }

  private func resume(with coordinate: Coordinate?) {
    pending?.resume(returning: coordinate)
    pending = nil
  }
}
