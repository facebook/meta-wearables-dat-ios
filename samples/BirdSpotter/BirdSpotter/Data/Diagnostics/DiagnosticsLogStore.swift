/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsLogStore.swift
//  birdspotter
//

import Foundation

/// One log file on disk, as the Diagnostics screen lists it.
///
/// `startedAtMillis` is read back out of the file's own name rather than from its
/// filesystem dates — a restored backup or a file copied off the device keeps its name and
/// loses its dates, and the name is the only thing that still says when the run happened.
struct DiagnosticsLogFile: Equatable, Sendable, Identifiable {
  /// The file name, and the id the viewer is addressed by.
  let name: String
  let startedAtMillis: Int64
  let sizeBytes: Int64
  /// Whether lines are still landing in this one.
  let isCurrent: Bool

  var id: String { name }
}

/// The rolling diagnostic log: a directory of plain-text files, newest still being written.
///
/// **A file per run, and a size cap within one.** A run is the unit anybody actually asks
/// about — "the demo at eleven" is one launch — so ``beginNewRun()`` starts a fresh file
/// each time the app comes up, and a run long enough to fill ``maxFileBytes`` rolls onto
/// another. Once there are more than ``maxFiles``, the oldest go. That bounds the whole
/// feature at a little under 3 MB without anything having to run a sweep on a timer.
///
/// **Plain text, not JSON.** These get read three ways — in the Diagnostics screen, in a text
/// editor after being shared out, and by `grep` — and only the first would be helped by a
/// structured format. ``LogEntry`` owns the line shape in both directions. (A JSONL log would
/// answer a different job: one file per identify flow, structured because a *machine* diffs
/// two platforms' runs. This one is for a person.)
///
/// **Writes are immediate.** Nothing is buffered waiting for a flush, because the run this
/// exists to explain is very often the one that ended in a crash, and a buffer is exactly
/// the last few lines that matter. ``FileLogSink`` keeps the caller off the disk instead,
/// by owning the queue this is called on.
nonisolated final class DiagnosticsLogStore: @unchecked Sendable {
  // @unchecked: every mutable field is behind `lock`, and nothing here awaits at all,
  // let alone while holding it.

  /// How large one file may grow before the run rolls onto another.
  static let maxFileBytes: Int64 = 256 * 1024

  /// How many files are kept. Twelve runs is more demo history than anyone has needed,
  /// and with the size cap it holds the directory under 3 MB.
  static let maxFiles = 12

  private static let filePrefix = "birdspotter-"
  private static let fileExtension = "log"

  let rootURL: URL

  private let lock = NSLock()
  private var currentName: String?
  private var currentHandle: FileHandle?
  /// The stamp the last file was named with. See ``nextFileMillisLocked()``.
  private var lastFileMillis: Int64 = 0
  /// Tracked rather than re-read: the size is checked on every line, and a `stat` per
  /// line is a syscall this does not need to make.
  private var currentBytes: Int64 = 0

  init(rootURL: URL) {
    self.rootURL = rootURL
  }

  /// The store rooted at Application Support / `diagnostics`.
  ///
  /// Beside `media`, and for the same reason ``MediaFileStore`` is there: it is the app's
  /// own storage rather than the user's, and unlike a cache directory the system will not
  /// evict it out from under a run somebody still means to read.
  ///
  /// **Does not throw, unlike its neighbours.** ``MediaFileStore/open()`` is allowed to
  /// take the app down because a filesystem that will not hold a photograph loses the
  /// user's work — but taking the app down because the *log* directory would not open
  /// trades a working app for a diagnostic about a demo that then never happens. A store
  /// that cannot write is simply one whose files list is empty; every write already fails
  /// in silence.
  static func open() -> DiagnosticsLogStore {
    let base =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let root = base.appendingPathComponent("diagnostics")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return DiagnosticsLogStore(rootURL: root)
  }

  // MARK: Writing

  /// Starts a fresh file for a new run of the app, and prunes back to ``maxFiles``.
  ///
  /// Safe to call more than once; each call simply starts another file.
  func beginNewRun() {
    lock.withLock {
      closeCurrentLocked()
      openFileLocked(named: Self.fileName(forMillis: nextFileMillisLocked()))
      pruneLocked()
    }
  }

  /// Appends one already-formatted line, rolling onto a new file if this one has had
  /// enough.
  ///
  /// **One writer.** ``FileLogSink`` calls this from its own serial queue and nothing
  /// else calls it at all, which is what keeps lines in the order they happened. The lock
  /// is here for the readers below, not for a second writer.
  func append(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    lock.withLock {
      if currentHandle == nil {
        openFileLocked(named: Self.fileName(forMillis: nextFileMillisLocked()))
      }
      // Rolled *before* the write, not after, so `maxFileBytes` is a ceiling the file
      // stays under rather than one it steps over by a line each time.
      if currentBytes + Int64(data.count) > Self.maxFileBytes {
        closeCurrentLocked()
        openFileLocked(named: Self.fileName(forMillis: nextFileMillisLocked()))
        pruneLocked()
      }
      // A failed write is dropped in silence, which is the one place in the app that
      // is right: the alternative is a logger that logs about logging, and a disk
      // that will not take a diagnostic line will not take the complaint either.
      try? currentHandle?.write(contentsOf: data)
      currentBytes += Int64(data.count)
    }
  }

  // MARK: Reading

  /// Every file, newest first — which is the order the screen lists them in, because the
  /// run somebody is asking about is nearly always the one that just happened.
  func files() -> [DiagnosticsLogFile] {
    let current = lock.withLock { currentName }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
    return
      names
      .filter { $0.hasPrefix(Self.filePrefix) && $0.hasSuffix(".\(Self.fileExtension)") }
      // Lexicographic *is* chronological: the stamp in the name is fixed-width and
      // most-significant-first, which is the whole reason it is shaped that way.
      .sorted(by: >)
      .compactMap { name in
        guard let startedAt = Self.millis(fromFileName: name) else { return nil }
        let path = rootURL.appendingPathComponent(name).path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return DiagnosticsLogFile(
          name: name,
          startedAtMillis: startedAt,
          sizeBytes: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
          isCurrent: name == current
        )
      }
  }

  /// One file's raw text — what the share sheet hands out.
  func text(in name: String) -> String {
    (try? String(contentsOf: url(for: name), encoding: .utf8)) ?? ""
  }

  /// One file, parsed back into entries, oldest first.
  ///
  /// A line that will not parse is kept rather than dropped, filed under
  /// ``LogCategory/app`` at ``LogLevel/info`` with its text intact — it is far more
  /// likely to be a line from a build with a category this one has not heard of than
  /// noise, and a viewer that silently eats what it does not understand is a viewer you
  /// cannot trust to be showing you everything.
  func entries(in name: String) -> [LogEntry] {
    text(in: name)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { line in
        LogEntry.parse(String(line))
          ?? LogEntry(
            timestampMillis: 0,
            level: .info,
            category: .app,
            message: String(line)
          )
      }
  }

  func url(for name: String) -> URL {
    rootURL.appendingPathComponent(name)
  }

  // MARK: Deleting

  /// Empties the directory and starts a fresh file, so logging carries on straight after.
  ///
  /// The fresh file is the point: without it the next line would reopen the file that was
  /// just deleted, and the screen would show a log the user had asked to be rid of.
  func deleteAll() {
    lock.withLock {
      closeCurrentLocked()
      let names = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
      for name in names {
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name))
      }
      openFileLocked(named: Self.fileName(forMillis: nextFileMillisLocked()))
    }
  }

  // MARK: Behind the lock

  /// The stamp to name the next file with — now, or one millisecond past the last one,
  /// whichever is later.
  ///
  /// **Names have to be strictly increasing, not merely current.** Two files opened inside
  /// one millisecond would otherwise be handed the same name, and the second would reopen
  /// the first: a rotation that rotates onto itself, and — worse — a launch that appends to
  /// the previous run's file. `files()` also sorts on the name, so equal names would make
  /// the order of two runs undefined. The clock is only ever read forwards.
  private func nextFileMillisLocked() -> Int64 {
    let millis = max(Self.nowMillis(), lastFileMillis + 1)
    lastFileMillis = millis
    return millis
  }

  private func closeCurrentLocked() {
    try? currentHandle?.close()
    currentHandle = nil
    currentName = nil
    currentBytes = 0
  }

  private func openFileLocked(named name: String) {
    let url = rootURL.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    currentBytes = Int64((try? handle.seekToEnd()) ?? 0)
    currentHandle = handle
    currentName = name
  }

  /// Drops the oldest files past ``maxFiles``. Never the current one — it is the newest,
  /// so the sort keeps it at the front regardless.
  private func pruneLocked() {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? [])
      .filter { $0.hasPrefix(Self.filePrefix) && $0.hasSuffix(".\(Self.fileExtension)") }
      .sorted(by: >)
    guard names.count > Self.maxFiles else { return }
    for name in names.dropFirst(Self.maxFiles) {
      try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name))
    }
  }

  // MARK: Names

  /// `birdspotter-20260729-091422-913.log`
  ///
  /// Fixed width and most-significant-first, so sorting the names sorts the runs — see
  /// ``files()``. To the millisecond because a long run can roll twice inside one second,
  /// and two files with one name is a run that overwrites itself.
  static func fileName(forMillis millis: Int64) -> String {
    let stamp = nameFormatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    return "\(filePrefix)\(stamp).\(fileExtension)"
  }

  /// The run's start time, read back out of the name. `nil` for anything not ours.
  static func millis(fromFileName name: String) -> Int64? {
    guard name.hasPrefix(filePrefix), name.hasSuffix(".\(fileExtension)") else { return nil }
    let stamp = String(
      name.dropFirst(filePrefix.count).dropLast(fileExtension.count + 1)
    )
    guard let date = nameFormatter.date(from: stamp) else { return nil }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  private static let nameFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
    return formatter
  }()

  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }
}
