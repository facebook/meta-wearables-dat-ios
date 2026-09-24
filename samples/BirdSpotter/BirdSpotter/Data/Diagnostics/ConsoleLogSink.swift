/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  ConsoleLogSink.swift
//  birdspotter
//

import Foundation
import OSLog

/// Puts a line where a developer at a desk will see it — Xcode's console, and Console.app.
///
/// One `Logger` per ``LogCategory``, built once, so the category is a real OSLog category
/// rather than a prefix inside the message: Console.app filters on it, and so does
/// `log stream --predicate`. That is the same job the Diagnostics screen's chips do for
/// someone holding the phone, and the two agree because both read ``LogEntry/category``.
///
/// **Everything is `.public`.** The default for an interpolated value is `.private`, which
/// on a device redacts it to `<private>` — and a log full of `<private>` is the exact
/// failure this feature exists to prevent. Nothing logged here is a secret: the app has no
/// account, no token and no user identity, and the one identifier it prints is a Bluetooth
/// device id belonging to glasses the wearer is holding.
struct ConsoleLogSink: LogSink {

  private static let subsystem = "com.pixelandtexel.birdspotter"

  /// Built once for the whole set. `Logger` is cheap but not free, and a sink on the hot
  /// path should not be allocating one per line.
  private static let loggers: [LogCategory: Logger] = Dictionary(
    uniqueKeysWithValues: LogCategory.allCases.map {
      ($0, Logger(subsystem: subsystem, category: $0.id))
    }
  )

  func write(_ entry: LogEntry) {
    guard let logger = Self.loggers[entry.category] else { return }
    let message = entry.message
    switch entry.level {
    case .debug: logger.debug("\(message, privacy: .public)")
    case .info: logger.info("\(message, privacy: .public)")
    case .warning: logger.warning("\(message, privacy: .public)")
    case .error: logger.error("\(message, privacy: .public)")
    }
  }
}
