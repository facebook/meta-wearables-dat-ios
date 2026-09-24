/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionSettingsStore.swift
//  birdspotter
//

import Foundation

/// What the real-time screen remembers between sessions.
///
/// UserDefaults, for the same reason ``DemoSettingsStore`` is: this is how somebody likes their
/// instrument set, not something the app *made*. `journal.db` stores outings and `catalog.db` is a
/// read-only seed; a preference about how a picture is drawn is neither, and losing one costs a tap.
///
/// **Written on the tap, not on the way out.** A session can end by being saved, discarded,
/// backgrounded or killed, and a preference that only survived one of those four is a preference
/// that appears to forget at random.
///
/// One key today, and it is still a store rather than a loose `UserDefaults` call in a view: the
/// screen has exactly one place to ask, the key is spelled once, and the unknown-value case is
/// answered here instead of at every call site.
nonisolated struct SessionSettingsStore: @unchecked Sendable {
  // @unchecked: UserDefaults is documented thread-safe, and there is nothing else in here.

  private static let stripReadingKey = "session.stripReading"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// How the watcher last had the strip drawn.
  ///
  /// **The sonogram is the answer to anything unreadable**, including a first run and a value
  /// written by some future build this one does not know: it is the reading the screen was born
  /// with and the one the rest of the feature is written around.
  var stripReading: StripReading {
    get {
      defaults.string(forKey: Self.stripReadingKey)
        .flatMap(StripReading.init(rawValue:)) ?? .sonogram
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: Self.stripReadingKey)
    }
  }
}
