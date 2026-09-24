/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LogLevel.swift
//  birdspotter
//

import Foundation

/// How much a diagnostic line matters — the four every logging library has settled on.
///
/// Ordered, and the order is the whole point: ``BirdLog/minimumLevel`` keeps a line only
/// when its level is at least that one, so raising the floor to ``warning`` silences the
/// two below it without any call site learning about it.
///
/// **Four, not five.** No `trace`/`verbose` tier: this app has one thing that would fill one
/// — audio buffers arriving eighty times a second — and a per-buffer line is not a
/// diagnostic, it is a denial of service against the file the diagnostics are in. Anything
/// that frequent gets logged as a *transition* instead.
///
/// The raw value is what a log file carries, so it is fixed by contract: renaming a case
/// would orphan every line already written.
enum LogLevel: String, CaseIterable, Comparable, Sendable {

  /// The step-by-step: a stream attaching, a fallback taken, a file written. Off by
  /// default in Release, on for the demo team.
  case debug

  /// The beats worth reading back — a session starting, a photograph landing, an outing
  /// saved. What a post-mortem is reconstructed from.
  case info

  /// Something went the long way round but the app carried on: a capture that failed and
  /// fell back to the phone, a preset that would not decode.
  case warning

  /// Something the user can see is broken.
  case error

  /// Rank, low to high. Not the `CaseIterable` index by accident — the order below *is*
  /// the severity order, and `Comparable` is what ``BirdLog`` filters on.
  private var rank: Int {
    switch self {
    case .debug: 0
    case .info: 1
    case .warning: 2
    case .error: 3
    }
  }

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

  /// Fixed width, so a column of them in a log file and in the viewer stays a column.
  var fileLabel: String {
    switch self {
    case .debug: "DEBUG"
    case .info: "INFO "
    case .warning: "WARN "
    case .error: "ERROR"
    }
  }

  /// What the viewer prints. Trimmed — a screen has its own alignment.
  var displayLabel: String { fileLabel.trimmingCharacters(in: .whitespaces) }

  /// Parses a level back off a log line, or out of a stored preference.
  ///
  /// **Both spellings, because the two callers write different ones.** A log line carries
  /// ``fileLabel`` (`WARN`) and a stored preference carries ``rawValue`` (`warning`), and
  /// a parser that knew only the second silently failed every warning line in every file.
  ///
  /// Unknown text is `nil` rather than a guess: a line whose level cannot be read is
  /// better shown as whatever the reader chooses than filed under a severity it never had.
  static func parse(_ raw: String) -> LogLevel? {
    let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
    return allCases.first {
      $0.rawValue == normalized || $0.displayLabel.lowercased() == normalized
    }
  }
}
