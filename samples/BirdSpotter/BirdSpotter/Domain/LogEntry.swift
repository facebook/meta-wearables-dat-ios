/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LogEntry.swift
//  birdspotter
//

import Foundation

/// One diagnostic line: when, how much it matters, which part of the app, and what happened.
///
/// **A line, singular.** ``init(timestampMillis:level:category:message:)`` folds every run
/// of whitespace in the message down to one space, so an entry can never be two lines in a
/// file. That is not tidiness — it is what lets ``parse(_:)`` be a regular expression
/// instead of a state machine, and what stops a multi-line SDK error from making every
/// line after it unreadable.
///
/// This type owns the file format, both directions: ``fileLine`` writes it and
/// ``parse(_:)`` reads it back for the viewer. One place, so the two can never drift — a
/// log the app cannot read is a log nobody will.
///
/// `timestampMillis` is epoch milliseconds, the same convention every timestamp in `journal.db`
/// uses.
struct LogEntry: Equatable, Sendable, Identifiable {

  let id: UUID
  let timestampMillis: Int64
  let level: LogLevel
  let category: LogCategory
  /// Already collapsed to one line — see the type's own doc.
  let message: String

  init(timestampMillis: Int64, level: LogLevel, category: LogCategory, message: String) {
    self.id = UUID()
    self.timestampMillis = timestampMillis
    self.level = level
    self.category = category
    self.message = Self.collapsed(message)
  }

  var date: Date { Date(timeIntervalSince1970: Double(timestampMillis) / 1000) }

  /// `2026-07-29T09:14:22.913-05:00 [INFO ] [glasses] glasses reading — paired: 2`
  ///
  /// **Local time, with the offset spelled out.** A demo post-mortem is someone saying
  /// "it froze around quarter past nine", and a column of UTC makes them do arithmetic
  /// before they can start. The offset keeps it unambiguous for anyone reading the file
  /// somewhere else.
  ///
  /// The level is padded and both fields bracketed so the messages line up in a text
  /// editor — these files get opened in one far more often than in the viewer.
  var fileLine: String {
    "\(Self.timestampFormatter.string(from: date)) [\(level.fileLabel)] [\(category.id)] \(message)"
  }

  /// Reads a line back, or `nil` if it is not one of ours.
  ///
  /// Unknown levels and categories fail the parse rather than defaulting, so a file
  /// written by a future build degrades to "some lines the viewer shows raw" instead of
  /// one quietly mis-filed under the wrong headings — see ``DiagnosticsLogStore/entries(in:)``
  /// for what becomes of the leftovers.
  static func parse(_ line: String) -> LogEntry? {
    guard let match = line.wholeMatch(of: filePattern),
      let date = timestampFormatter.date(from: String(match.1)),
      let level = LogLevel.parse(String(match.2)),
      let category = LogCategory.parse(String(match.3))
    else { return nil }
    return LogEntry(
      timestampMillis: Int64((date.timeIntervalSince1970 * 1000).rounded()),
      level: level,
      category: category,
      message: String(match.4)
    )
  }

  /// The one regular expression, matching what ``fileLine`` writes.
  private static let filePattern = /(\S+) \[([A-Za-z]+) *\] \[([a-z]+)\] (.*)/

  /// ISO 8601 to the millisecond, in the phone's own time zone.
  ///
  /// A fixed `en_US_POSIX` `DateFormatter` rather than `ISO8601DateFormatter`, which is
  /// the documented way to pin a machine-readable shape a user's locale cannot move.
  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
    return formatter
  }()

  /// Every run of whitespace — newlines included — down to one space.
  private static func collapsed(_ message: String) -> String {
    message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
