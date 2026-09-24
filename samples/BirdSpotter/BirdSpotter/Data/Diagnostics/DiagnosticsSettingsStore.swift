/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsSettingsStore.swift
//  birdspotter
//

import Foundation

/// How the diagnostic log is set: whether it writes to files at all, and how far down it
/// records.
///
/// UserDefaults, for the same reason ``DemoSettingsStore`` and ``SessionSettingsStore``
/// are there — this is how somebody has their instrument set, not something the app made.
///
/// **Read at launch, before the first line.** The composition root asks for both values
/// while it is installing the sinks, so a raised floor is in force from the first line of
/// the run rather than from whenever Settings first opened.
nonisolated struct DiagnosticsSettingsStore: @unchecked Sendable {
  // @unchecked: UserDefaults is documented thread-safe, and there is nothing else here.

  private static let fileLoggingKey = "diagnostics.fileLogging"
  private static let minimumLevelKey = "diagnostics.minimumLevel"

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  static func open(defaults: UserDefaults = .standard) -> DiagnosticsSettingsStore {
    DiagnosticsSettingsStore(defaults: defaults)
  }

  /// Whether lines are written to disk. On by default — a log that has to be switched on
  /// before it is useful is a log that was off during the run you needed it for.
  ///
  /// The console sink is not affected: turning this off stops the files, not the
  /// developer's own console.
  var isFileLoggingEnabled: Bool {
    get {
      // `object(forKey:)` first, because `bool(forKey:)` cannot tell "never set"
      // from "set to false", and the default here is true.
      defaults.object(forKey: Self.fileLoggingKey) as? Bool ?? true
    }
    nonmutating set {
      defaults.set(newValue, forKey: Self.fileLoggingKey)
    }
  }

  /// The floor lines have to clear. ``LogLevel/debug`` unless somebody has raised it —
  /// see ``BirdLog/minimumLevel`` for why the noisy default is the right one here.
  var minimumLevel: LogLevel {
    get {
      defaults.string(forKey: Self.minimumLevelKey).flatMap(LogLevel.parse) ?? .debug
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: Self.minimumLevelKey)
    }
  }
}
