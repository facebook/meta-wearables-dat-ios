/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DisplaySettingsStore.swift
//  birdspotter
//

import Foundation

/// The display screen's custom card, as the presenter last set it up: which bird, and the
/// line to show in place of the catalog's description.
///
/// UserDefaults, for the same reason ``DemoSettingsStore`` is: a custom card is presenter
/// configuration, not something the app *made*. `journal.db` stores outings and `catalog.db`
/// is a read-only seed — and staying out of the seed is the point: the catalog's own
/// description is untouched, and taking the custom card down is a clear, not a database
/// migration.
///
/// **Written on the keystroke, not on the way out.** A card is typically set up before the
/// demo and shown during it, with an app restart anywhere in between; a message that only
/// survived a graceful exit is a message that appears to forget at random.
nonisolated struct DisplaySettingsStore: @unchecked Sendable {
  // @unchecked: UserDefaults is documented thread-safe, and there is nothing else in here.

  private static let customBirdIdKey = "display.customBirdId"
  private static let customMessageKey = "display.customMessage"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The chosen bird's catalog slug, or `nil` when none has been chosen. A slug is stable
  /// by contract — see ``Species`` — so a stored one stays good across a seed bump; one
  /// that still fails to resolve reads as unchosen.
  var customBirdId: String? {
    get {
      let stored = defaults.string(forKey: Self.customBirdIdKey)
      return stored?.isEmpty == false ? stored : nil
    }
    nonmutating set {
      defaults.set(newValue ?? "", forKey: Self.customBirdIdKey)
    }
  }

  /// The presenter's line. Blank means none has been written.
  var customMessage: String {
    get {
      defaults.string(forKey: Self.customMessageKey) ?? ""
    }
    nonmutating set {
      defaults.set(newValue, forKey: Self.customMessageKey)
    }
  }
}
