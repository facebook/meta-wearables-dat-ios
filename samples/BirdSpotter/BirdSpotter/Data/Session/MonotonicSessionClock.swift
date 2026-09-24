/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MonotonicSessionClock.swift
//  birdspotter
//

import Foundation

/// The clock a real session runs on: the platform's monotonic elapsed time.
///
/// `ContinuousClock` rather than `SuspendingClock`, and `SystemClock.elapsedRealtime()` rather
/// than `uptimeMillis()` on the other side — the pair that keep counting while the phone is
/// asleep. A session recording with the screen off is still a session, and a minute that passed
/// while it did is a minute of the recording.
///
/// **Never `Date`.** A wall clock can be set backwards mid-session, by hand or by the network, and
/// a timeline that ran backwards would put an event before the one that caused it.
@MainActor final class MonotonicSessionClock: SessionClock {

  private let clock = ContinuousClock()
  private var origin: ContinuousClock.Instant

  init() {
    origin = clock.now
  }

  var elapsed: Double {
    let since = clock.now - origin
    return Double(since.components.seconds)
      + Double(since.components.attoseconds) / 1e18
  }

  func start() {
    origin = clock.now
  }
}
