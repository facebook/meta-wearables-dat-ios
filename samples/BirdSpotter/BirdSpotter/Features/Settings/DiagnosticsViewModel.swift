/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsViewModel.swift
//  birdspotter
//

import Foundation

/// What the Diagnostics screen shows: how the log is set, and the files it has written.
///
/// **Reads on demand rather than watching.** A log that redrew the list under the reader as
/// lines landed would be a screen nobody could scroll — and the *current* file grows on
/// every tap, so the sizes would never sit still. The list is re-read on appearing, which
/// is when the answer changed anyway.
@MainActor
@Observable
final class DiagnosticsViewModel {

  private let store: DiagnosticsLogStore
  private let settings: DiagnosticsSettingsStore
  /// Re-run whenever a setting changes, so the sinks match what the screen says. The
  /// composition root's own method — see ``AppContainer/installDiagnostics()``.
  private let reinstall: () -> Void

  private(set) var files: [DiagnosticsLogFile] = []
  private(set) var isFileLoggingEnabled: Bool
  private(set) var minimumLevel: LogLevel

  /// Every level, for the picker. Held here rather than read off ``LogLevel`` in the view
  /// so the order the screen offers is a decision this class owns.
  let levels = LogLevel.allCases

  init(
    store: DiagnosticsLogStore,
    settings: DiagnosticsSettingsStore,
    reinstall: @escaping () -> Void
  ) {
    self.store = store
    self.settings = settings
    self.reinstall = reinstall
    self.isFileLoggingEnabled = settings.isFileLoggingEnabled
    self.minimumLevel = settings.minimumLevel
  }

  /// Re-reads the directory. Cheap — a dozen `stat`s — and off the main thread all the
  /// same, because it is a filesystem walk and this is a `@MainActor` class.
  func refresh() async {
    let store = self.store
    files = await Task.detached { store.files() }.value
  }

  func setFileLogging(_ enabled: Bool) {
    guard enabled != isFileLoggingEnabled else { return }
    isFileLoggingEnabled = enabled
    settings.isFileLoggingEnabled = enabled
    // Through the composition root, so "which sinks are installed" stays written in one
    // place — and so switching files back on opens a fresh one rather than appending to
    // a run that stopped being recorded halfway through.
    reinstall()
    Task { await refresh() }
  }

  func setMinimumLevel(_ level: LogLevel) {
    guard level != minimumLevel else { return }
    minimumLevel = level
    settings.minimumLevel = level
    reinstall()
  }

  /// Empties the directory. The screen asks first — nothing here asks a second time.
  func deleteAll() async {
    let store = self.store
    await Task.detached { store.deleteAll() }.value
    BirdLog.info(.app, "diagnostics — every log file deleted from Settings")
    await refresh()
  }

  /// What a row says under its title: how big, and whether it is the run happening now.
  func summary(for file: DiagnosticsLogFile) -> String {
    let size = ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    return file.isCurrent ? "\(size) · recording now" : size
  }

  /// A file's own heading — the moment the run started, in the reader's own formatting.
  func title(for file: DiagnosticsLogFile) -> String {
    Self.titleFormatter.string(from: Date(timeIntervalSince1970: Double(file.startedAtMillis) / 1000))
  }

  private static let titleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
  }()
}
