/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FailoverAim.swift
//  birdspotter
//

import Foundation

/// One stream of readings over two real ones, so a session can change instruments without changing
/// its spine.
///
/// **The screen must not learn that failover exists.** Both aim readings are cold streams of
/// degrees that run for as long as anyone iterates them, and that contract holds while the
/// instrument underneath comes and goes.
///
/// **The two transitions are asymmetric**, the same way the microphone's are, and building them as
/// one thing gets the good half wrong. Crossing *to* the glasses costs nothing, so it is only ever
/// done on request. Losing them is discovered rather than announced — a stream that ends is all the
/// notice there is — so the fallback is reopened immediately, without asking anybody.
///
/// **A stream that ends is the whole failure signal here**, because neither reading throws. Both
/// providers answer a device that cannot help by yielding nothing and finishing, so *the glasses
/// have no compass* and *the glasses went away* arrive identically, and identically is how they
/// should be handled: go back to the instrument in the watcher's hand.
@MainActor
final class FailoverReadings {

  private let reading: String
  private let preferred: () -> AsyncStream<Double>
  private let fallback: () -> AsyncStream<Double>

  private var wantsPreferred = false
  /// Wakes the running stream when the request changes. `nil` while nobody is listening.
  private var onRequestChanged: (() -> Void)?

  init(
    reading: String,
    preferred: @escaping () -> AsyncStream<Double>,
    fallback: @escaping () -> AsyncStream<Double>
  ) {
    self.reading = reading
    self.preferred = preferred
    self.fallback = fallback
  }

  /// Ask for the preferred instrument, or hand the session back to the fallback.
  ///
  /// A request, not a promise. Safe to call when no stream is running — the answer is remembered
  /// for the next one.
  func usePreferred(_ wanted: Bool) {
    guard wantsPreferred != wanted else { return }
    wantsPreferred = wanted
    onRequestChanged?()
  }

  func stream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        defer { onRequestChanged = nil }

        while !Task.isCancelled {
          let wanted = wantsPreferred
          let source = wanted ? preferred() : fallback()

          // Signals a change of request to the loop below without it having to poll.
          //
          // **One per instrument, and the lifetime is the whole point.** ``pump`` waits
          // on this and on the source together and cancels whichever did not finish
          // first — and a cancelled wait leaves the stream it was waiting on terminated
          // for good. A single signal shared across iterations is therefore dead from
          // the first source that ended by itself, which is the *handback* case: every
          // pump after it finds the signal already finished, treats that as a change
          // arriving instantly, and tears down the instrument it just picked up before
          // it can yield anything. The loop then falls out of its own `guard` and ends
          // the reading — silently, and with "handing back to the phone" as the last
          // thing in the log. A pair with no compass would freeze the bearing on screen
          // at the exact moment the phone was supposed to take it back.
          let (changes, changed) = AsyncStream.makeStream(of: Void.self)
          onRequestChanged = { changed.yield(()) }

          // **Which instrument is answering is invisible from anywhere else**, by
          // design: that is the whole point of the wrapper. It is also the first thing
          // anyone asks when a reading on screen does not move with the wearer's head,
          // and there is no other way to find out.
          BirdLog.info(
            .glasses,
            "\(reading) — reading from the \(wanted ? "glasses" : "phone")"
          )

          let requestChanged = await pump(source, into: continuation, until: changes)
          changed.finish()
          if Task.isCancelled { break }
          if requestChanged { continue }

          // The source ended on its own. From the glasses that means they have nothing
          // to give, so the phone takes the question back; from the phone it means this
          // device has no such instrument, and there is nowhere left to go.
          guard wanted else { break }
          // The one handback nothing else records: the instrument was asked for, said it
          // had nothing, and the question went quietly back to the phone.
          BirdLog.info(
            .glasses,
            "\(reading) — the glasses had none to give; handing back to the phone"
          )
          wantsPreferred = false
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Forwards one source's readings until it ends or `changes` fires.
  ///
  /// Returns whether the request changed — which is what separates *switch instruments* from
  /// *this instrument has nothing more to say*.
  private func pump(
    _ source: AsyncStream<Double>,
    into continuation: AsyncStream<Double>.Continuation,
    until changes: AsyncStream<Void>
  ) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await reading in source { continuation.yield(reading) }
        return false
      }
      group.addTask {
        for await _ in changes { return true }
        return false
      }

      // Whichever finishes first decides; the other is cancelled with the group.
      let changed = await group.next() ?? false
      group.cancelAll()
      return changed
    }
  }
}

/// Which way the watcher is facing, from the glasses when the session has them and the phone when
/// it does not.
///
/// The bearing worth having is the one the camera that took the photograph was pointing along, and
/// on a glasses capture that camera is on the wearer's face — so the glasses win whenever they are
/// live, and the phone in the hand is what the session falls back to.
@MainActor
final class FailoverHeadingProvider: HeadingProvider {

  private let readings: FailoverReadings

  init(preferred: any HeadingProvider, fallback: any HeadingProvider) {
    readings = FailoverReadings(
      reading: "bearing",
      preferred: { preferred.headingStream() },
      fallback: { fallback.headingStream() }
    )
  }

  /// Ask for the glasses' compass, or hand the session back to the phone's.
  func usePreferred(_ wanted: Bool) {
    readings.usePreferred(wanted)
  }

  func headingStream() -> AsyncStream<Double> {
    readings.stream()
  }
}

/// How high the watcher is aiming, from the glasses when the session has them and the phone when it
/// does not.
///
/// The strongest case of the two for preferring the glasses: a phone reports where the *phone* is
/// pointing, so a watcher looking up into the canopy with their hand at their side is a watcher the
/// phone reads as staring at the grass. A head is the thing actually aimed at the bird.
@MainActor
final class FailoverGazeProvider: GazeProvider {

  private let readings: FailoverReadings

  init(preferred: any GazeProvider, fallback: any GazeProvider) {
    readings = FailoverReadings(
      reading: "elevation",
      preferred: { preferred.gazeStream() },
      fallback: { fallback.gazeStream() }
    )
  }

  /// Ask for the glasses' attitude, or hand the session back to the phone's.
  func usePreferred(_ wanted: Bool) {
    readings.usePreferred(wanted)
  }

  func gazeStream() -> AsyncStream<Double> {
    readings.stream()
  }
}
