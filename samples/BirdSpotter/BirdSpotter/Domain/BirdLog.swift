/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdLog.swift
//  birdspotter
//

import Foundation
import os

/// The app's diagnostic log — the one call any code makes to say what just happened.
///
/// ```swift
/// BirdLog.info(.glasses, "session started on \(name)")
/// BirdLog.warning(.audio, "glasses mic unavailable — falling back to the phone")
/// BirdLog.error(.journal, "could not save the outing", error)
/// ```
///
/// **A global, deliberately, and the only one in the app.** Everything else here is
/// injected through ``AppContainer`` — but a logger threaded through initialisers is a
/// logger that does not get called from the awkward places, and the awkward places are
/// where the demo breaks. Every logging library that people actually reach for makes the
/// same trade.
///
/// **Not a wrapper around `Logger`.** Lines fan out to whatever sinks are installed, which
/// is what puts the same line in Xcode's console *and* in a file the demo team can read on
/// the phone at the venue with no Mac in sight. ``install(sinks:)`` is called once from the
/// composition root; before it lands, lines go nowhere but are still cheap — see below.
///
/// **Callable from anywhere, at any level.** Free functions on a `nonisolated enum`, with
/// state behind a lock, so a DAT callback on some SDK queue and a `@MainActor` view model
/// use the same three words. Messages are `@autoclosure`, so a line filtered out by
/// ``minimumLevel`` never builds its string — the reason a `debug` line in a hot path
/// costs a comparison rather than an interpolation.
nonisolated enum BirdLog {

  // MARK: Writing

  /// The step-by-step. Free when the floor is above it.
  static func debug(
    _ category: LogCategory,
    _ message: @autoclosure () -> String
  ) {
    emit(.debug, category, message)
  }

  /// The beats worth reading back.
  static func info(
    _ category: LogCategory,
    _ message: @autoclosure () -> String
  ) {
    emit(.info, category, message)
  }

  /// The long way round, taken and survived.
  static func warning(
    _ category: LogCategory,
    _ message: @autoclosure () -> String
  ) {
    emit(.warning, category, message)
  }

  /// Something the user can see is broken.
  static func error(
    _ category: LogCategory,
    _ message: @autoclosure () -> String
  ) {
    emit(.error, category, message)
  }

  /// An error, with the thing that went wrong appended.
  ///
  /// A convenience worth having its own overload: `"\(message) — \(error)"` written by
  /// hand at forty call sites is forty chances to format it differently, and a log whose
  /// error lines do not look alike is one nobody can grep.
  static func error(
    _ category: LogCategory,
    _ message: @autoclosure () -> String,
    _ error: any Error
  ) {
    emit(.error, category, { "\(message()) — \(String(describing: error))" })
  }

  // MARK: Installing

  /// Points the log at its sinks. Called once, from the composition root.
  ///
  /// Replaces rather than appends, so a test can install a fake and be sure nothing else
  /// is listening.
  static func install(sinks: [any LogSink]) {
    state.withLock { $0.sinks = sinks }
  }

  /// Adds one more sink to whatever is already installed — how the file sink joins the
  /// console one once the store has opened.
  static func add(sink: any LogSink) {
    state.withLock { $0.sinks.append(sink) }
  }

  /// The floor. Lines below it are dropped before their message is built.
  ///
  /// ``LogLevel/debug`` by default: this app's whole reason for having a diagnostic log
  /// is a demo that went sideways in a room with no debugger in it, and a default that
  /// hides the step-by-step is a default that hides the answer. The Diagnostics screen
  /// raises it for anyone who finds the noise unhelpful.
  static var minimumLevel: LogLevel {
    get { state.withLock { $0.minimumLevel } }
    set { state.withLock { $0.minimumLevel = newValue } }
  }

  /// Drops every sink. For tests, and for the Diagnostics screen turning file logging off.
  static func removeAllSinks() {
    state.withLock { $0.sinks = [] }
  }

  // MARK: The state itself

  private struct State {
    var sinks: [any LogSink] = []
    var minimumLevel: LogLevel = .debug
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())

  private static func emit(
    _ level: LogLevel,
    _ category: LogCategory,
    _ message: () -> String
  ) {
    // Read once, under the lock, then let it go: a sink must never be called while the
    // log's own lock is held, or two sinks that log about each other would deadlock.
    let (sinks, floor) = state.withLock { ($0.sinks, $0.minimumLevel) }
    guard level >= floor, !sinks.isEmpty else { return }

    let entry = LogEntry(
      timestampMillis: Int64(Date().timeIntervalSince1970 * 1000),
      level: level,
      category: category,
      message: message()
    )
    for sink in sinks { sink.write(entry) }
  }
}
