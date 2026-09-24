/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsFileViewModel.swift
//  birdspotter
//

import Foundation

/// One log file, read and filtered — what the reader is actually hunting through.
///
/// **Newest first.** A log reads naturally oldest-to-newest, but nobody opens this at the
/// beginning: they open it because something just went wrong, and the answer is the last
/// few lines. So the file is reversed once, here, and the screen says so.
///
/// **The filters are the feature.** "Was that the glasses or the phone?" is a category tap,
/// and a level floor drops the step-by-step once the shape of the failure is clear. Both
/// are applied over the whole file rather than a page of it — these top out at 256 KB, so
/// filtering in memory is a few thousand comparisons.
@MainActor
@Observable
final class DiagnosticsFileViewModel {

  private let store: DiagnosticsLogStore
  let fileName: String

  /// Everything in the file, newest first. Filtering reads from this rather than the disk.
  private(set) var allEntries: [LogEntry] = []

  /// `nil` means every category — the state the screen opens in.
  private(set) var category: LogCategory?
  private(set) var level: LogLevel = .debug
  private(set) var isLoading = true

  init(store: DiagnosticsLogStore, fileName: String) {
    self.store = store
    self.fileName = fileName
  }

  /// The lines the screen draws.
  var entries: [LogEntry] {
    allEntries.filter { entry in
      entry.level >= level && (category == nil || entry.category == category)
    }
  }

  /// Only the categories this file actually contains, in the canonical order.
  ///
  /// Offering all nine would be nine chips of which six find nothing — a filter that can
  /// only disappoint is worse than no filter.
  var availableCategories: [LogCategory] {
    let present = Set(allEntries.map(\.category))
    return LogCategory.allCases.filter(present.contains)
  }

  /// What the toolbar shares out: the file exactly as written.
  var shareURL: URL { store.url(for: fileName) }

  func load() async {
    let store = self.store
    let name = fileName
    allEntries = await Task.detached { store.entries(in: name).reversed() }.value
    isLoading = false
  }

  func setCategory(_ category: LogCategory?) {
    self.category = category
  }

  func setLevel(_ level: LogLevel) {
    self.level = level
  }

  /// The line's own timestamp, to the second — the column the eye scans down.
  ///
  /// Seconds, not milliseconds: the file carries them for ordering two lines inside one
  /// tick, which is a machine's concern, and a screen full of `.913` is three characters
  /// of noise on every row.
  func timestamp(for entry: LogEntry) -> String {
    Self.timeFormatter.string(from: entry.date)
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}
