/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FailoverAimTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// One reading carried over two instruments, as the instrument underneath comes and goes.
///
/// The scenarios are the three things a watcher can actually observe: the reading follows the
/// request, it comes back on its own when the preferred instrument has nothing to give, and it
/// stops only when there is genuinely nowhere left to read from.
///
/// **Each instrument is opened fresh and answers with a different number**, which is what makes
/// these assertions about *which* one is being read rather than about a value passing through. A
/// provider is a factory here exactly as it is in the app — the failover calls it again every time
/// it picks an instrument up — so counting the calls is how a test can tell the second opening of
/// the phone from the first.
@Suite("FailoverAim")
@MainActor
struct FailoverAimTests {

  @Test func askingForThePreferred_readsFromIt() async {
    let phone = Instrument(readings: [270, 271])
    let readings = FailoverReadings(
      reading: "bearing",
      preferred: { Instrument(readings: [90]).open() },
      fallback: { phone.open() }
    )
    var stream = readings.stream().makeAsyncIterator()

    #expect(await stream.next() == 270)
    readings.usePreferred(true)

    #expect(await stream.next() == 90)
  }

  /// The regression this suite exists for.
  ///
  /// A pair that reports motion but no magnetic field answers the compass by finishing at once,
  /// which is the failover's entire signal to hand back. What the watcher must see after that is
  /// the phone's bearing *moving again* — not the last reading from before the switch, held for
  /// the rest of the session while the log says the handback succeeded.
  ///
  /// The second reading is the whole test: it can only arrive from a second opening of the phone,
  /// which is the thing a handback is.
  @Test func aPreferredThatEndsAtOnce_handsBackToAFallbackThatKeepsReading() async {
    let phone = Instrument(readings: [12, 34])
    let readings = FailoverReadings(
      reading: "bearing",
      preferred: { Instrument(readings: []).open() },
      fallback: { phone.open() }
    )
    var stream = readings.stream().makeAsyncIterator()

    #expect(await stream.next() == 12)
    // The glasses are asked for, and have no compass to offer.
    readings.usePreferred(true)

    // The phone is picked back up, which a second opening of it is the proof of.
    #expect(await stream.next() == 34)
    // And it is still being *read* — the reading that the failover ending would swallow, and
    // the one a watcher turning on the spot is waiting for. Without it this scenario passes on
    // a reading that crossed back and then went silent forever.
    phone.report(56)

    #expect(await stream.next() == 56)
  }

  @Test func bothInstrumentsSilent_endsTheReading() async {
    let readings = FailoverReadings(
      reading: "bearing",
      preferred: { Instrument(readings: []).open() },
      fallback: { Instrument(readings: []).open() }
    )
    var stream = readings.stream().makeAsyncIterator()
    readings.usePreferred(true)

    #expect(await stream.next() == nil)
  }
}

// MARK: - A stand-in instrument

/// One sensor, opened as many times as the failover picks it up.
///
/// **It stays open after its reading**, which is what a working sensor does and what lets a test
/// tell *the failover ended this stream* from *this stream ran out of numbers*. An instrument with
/// no readings at all is the other case the app has to survive: a device that cannot help answers
/// by finishing immediately.
@MainActor
private final class Instrument {

  private var readings: [Double]
  /// The stream this instrument was most recently opened as, so a test can make it speak again
  /// after the failover has picked it up — which is the only way to ask whether that stream is
  /// still being read rather than merely still holding its last value.
  private var live: AsyncStream<Double>.Continuation?

  init(readings: [Double]) {
    self.readings = readings
  }

  /// The next reading this instrument has never yet given out, or an empty stream once it has
  /// given out all of them.
  func open() -> AsyncStream<Double> {
    AsyncStream { continuation in
      guard !readings.isEmpty else {
        continuation.finish()
        return
      }
      live = continuation
      continuation.yield(readings.removeFirst())
    }
  }

  /// A further reading, down whichever stream this instrument is open as right now.
  func report(_ reading: Double) {
    live?.yield(reading)
  }
}
