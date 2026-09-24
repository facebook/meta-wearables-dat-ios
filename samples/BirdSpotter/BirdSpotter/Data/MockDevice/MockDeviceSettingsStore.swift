/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceSettingsStore.swift
//  birdspotter
//

import Foundation

/// Where the floating mock button was left on the screen, as fractions of the screen's
/// width and height — so the pin survives a rotation and a phone with a different screen.
nonisolated struct MockDeviceButtonPosition: Equatable, Sendable {
  /// 0 at the left edge, 1 at the right.
  let x: Double
  /// 0 at the top edge, 1 at the bottom.
  let y: Double

  /// Where the button starts: low on the right, where a thumb finds it and where it is
  /// over nothing a screen puts its own controls on.
  static let initial = MockDeviceButtonPosition(x: 0.9, y: 0.78)
}

/// How the mock is set: whether it stands in for the real SDK, which model it fakes, and
/// where its button was pinned.
///
/// UserDefaults, for the same reason ``DiagnosticsSettingsStore`` is — this is how somebody
/// has their instrument set, not something the app made. The kit itself remembers nothing
/// between launches, so this store is what lets a relaunch come back up simulated.
nonisolated struct MockDeviceSettingsStore: @unchecked Sendable {
  // @unchecked: UserDefaults is documented thread-safe, and there is nothing else here.

  private static let enabledKey = "mockDevice.isEnabled"
  private static let modelKey = "mockDevice.model"
  private static let buttonXKey = "mockDevice.buttonX"
  private static let buttonYKey = "mockDevice.buttonY"

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  static func open(defaults: UserDefaults = .standard) -> MockDeviceSettingsStore {
    MockDeviceSettingsStore(defaults: defaults)
  }

  /// Whether the kit should be standing in for the real SDK. Off by default: the real
  /// glasses are the app's whole point, and the mock is the thing you reach for without them.
  var isEnabled: Bool {
    get { defaults.bool(forKey: Self.enabledKey) }
    nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
  }

  /// The model paired last, and the one a relaunch pairs again.
  var model: MockGlassesModel {
    get {
      defaults.string(forKey: Self.modelKey).flatMap(MockGlassesModel.init(rawValue:))
        ?? .rayBanMeta
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modelKey) }
  }

  /// Where the floating button was pinned.
  var buttonPosition: MockDeviceButtonPosition {
    get {
      // `object(forKey:)` first, because `double(forKey:)` cannot tell "never set"
      // from zero, and zero here would pin the button in the corner.
      guard let x = defaults.object(forKey: Self.buttonXKey) as? Double,
        let y = defaults.object(forKey: Self.buttonYKey) as? Double
      else { return .initial }
      return MockDeviceButtonPosition(x: x, y: y)
    }
    nonmutating set {
      defaults.set(newValue.x, forKey: Self.buttonXKey)
      defaults.set(newValue.y, forKey: Self.buttonYKey)
    }
  }
}
