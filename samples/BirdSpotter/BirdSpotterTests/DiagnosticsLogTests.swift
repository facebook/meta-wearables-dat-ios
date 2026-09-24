/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DiagnosticsLogTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The diagnostic log: the line format both ends of it agree on, the rolling files, and the
/// floor that decides what is written at all.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("DiagnosticsLog")
struct DiagnosticsLogTests {

  // MARK: - The line format

  @Test func fileLine_roundTripsThroughParse() {
    let entry = LogEntry(
      timestampMillis: 1_753_142_405_210,
      level: .warning,
      category: .glasses,
      message: "capture — nothing arrived after 15000 ms"
    )

    let parsed = LogEntry.parse(entry.fileLine)

    // Everything but the id, which is minted per instance and is not in the file.
    #expect(parsed?.timestampMillis == entry.timestampMillis)
    #expect(parsed?.level == entry.level)
    #expect(parsed?.category == entry.category)
    #expect(parsed?.message == entry.message)
  }

  @Test func fileLine_collapsesAMultiLineMessageToOneLine() {
    let entry = LogEntry(
      timestampMillis: 0,
      level: .info,
      category: .app,
      message: "first\n   second\t\tthird\n"
    )

    // The whole reason parsing can be one regular expression: a multi-line SDK error
    // must not be able to make every line after it unreadable.
    #expect(entry.message == "first second third")
    #expect(!entry.fileLine.contains("\n"))
  }

  @Test func parse_refusesALineThatIsNotOurs() {
    #expect(LogEntry.parse("just some text") == nil)
    #expect(LogEntry.parse("") == nil)
    // A level this build does not know fails rather than defaulting to one it does.
    #expect(LogEntry.parse("2026-07-29T09:14:22.913-05:00 [TRACE] [glasses] hello") == nil)
    // Likewise a category.
    #expect(LogEntry.parse("2026-07-29T09:14:22.913-05:00 [INFO ] [weather] hello") == nil)
  }

  // MARK: - Levels

  @Test func levels_areOrderedBySeverity() {
    #expect(LogLevel.debug < LogLevel.info)
    #expect(LogLevel.info < LogLevel.warning)
    #expect(LogLevel.warning < LogLevel.error)
  }

  // MARK: - The rolling store

  @Test func append_rollsOntoANewFileAtTheSizeCap() throws {
    let store = try temporaryStore()
    store.beginNewRun()

    // Comfortably past the cap, in lines big enough that the count stays small.
    let line = String(repeating: "x", count: 4_096)
    for _ in 0..<80 { store.append(line) }

    let files = store.files()
    #expect(files.count > 1)
    // The cap is a ceiling the file stays under, not one it steps over.
    #expect(files.allSatisfy { $0.sizeBytes <= DiagnosticsLogStore.maxFileBytes })
  }

  @Test func beginNewRun_prunesToTheFileLimit() throws {
    let store = try temporaryStore()

    for _ in 0..<(DiagnosticsLogStore.maxFiles + 5) {
      store.beginNewRun()
      store.append("a line, so the file is not empty")
    }

    #expect(store.files().count == DiagnosticsLogStore.maxFiles)
  }

  @Test func files_areNewestFirstAndNameTheCurrentOne() throws {
    let store = try temporaryStore()
    store.beginNewRun()
    store.append("older run")
    store.beginNewRun()
    store.append("newer run")

    let files = store.files()
    #expect(files.count == 2)
    #expect(files.first?.isCurrent == true)
    #expect(files.last?.isCurrent == false)
    #expect(files[0].startedAtMillis >= files[1].startedAtMillis)
  }

  @Test func entries_readTheRunBackInOrder() throws {
    let store = try temporaryStore()
    store.beginNewRun()
    store.append(LogEntry(timestampMillis: 1_000, level: .info, category: .glasses, message: "one").fileLine)
    store.append(LogEntry(timestampMillis: 2_000, level: .error, category: .audio, message: "two").fileLine)

    let name = try #require(store.files().first?.name)
    let entries = store.entries(in: name)

    // Oldest first — the file's own order. Reversing for the screen is the view model's.
    #expect(entries.count == 2)
    #expect(entries[0].message == "one")
    #expect(entries[1].category == .audio)
  }

  @Test func entries_keepALineItCannotParse() throws {
    let store = try temporaryStore()
    store.beginNewRun()
    store.append("something a future build wrote")

    let name = try #require(store.files().first?.name)
    let entries = store.entries(in: name)

    // Kept rather than dropped: a viewer that eats what it does not understand is one
    // you cannot trust to be showing you everything.
    #expect(entries.count == 1)
    #expect(entries[0].message == "something a future build wrote")
  }

  @Test func deleteAll_emptiesTheDirectoryAndKeepsWriting() throws {
    let store = try temporaryStore()
    store.beginNewRun()
    store.append("before")

    store.deleteAll()
    store.append("after")

    let files = store.files()
    #expect(files.count == 1)
    let name = try #require(files.first?.name)
    #expect(store.text(in: name).contains("after"))
    #expect(!store.text(in: name).contains("before"))
  }

  @Test func fileName_roundTripsItsStartTime() {
    let millis: Int64 = 1_753_142_405_210
    let name = DiagnosticsLogStore.fileName(forMillis: millis)

    #expect(DiagnosticsLogStore.millis(fromFileName: name) == millis)
    #expect(DiagnosticsLogStore.millis(fromFileName: "not-ours.txt") == nil)
  }

  // MARK: - The facade

  @Test func birdLog_dropsLinesBelowTheFloor() {
    let sink = RecordingLogSink()
    BirdLog.install(sinks: [sink])
    defer {
      BirdLog.removeAllSinks()
      BirdLog.minimumLevel = .debug
    }

    BirdLog.minimumLevel = .warning
    BirdLog.debug(.app, "quiet")
    BirdLog.info(.app, "also quiet")
    BirdLog.warning(.app, "loud")
    BirdLog.error(.app, "louder")

    #expect(sink.messages == ["loud", "louder"])
  }

  @Test func birdLog_doesNotBuildAMessageItWillDrop() {
    let sink = RecordingLogSink()
    BirdLog.install(sinks: [sink])
    defer {
      BirdLog.removeAllSinks()
      BirdLog.minimumLevel = .debug
    }
    BirdLog.minimumLevel = .error

    // The reason messages are autoclosures: a `debug` line in a hot path costs a
    // comparison rather than an interpolation.
    var built = false
    BirdLog.debug(
      .app,
      {
        built = true
        return "expensive"
      }())

    #expect(built == false)
    #expect(sink.messages.isEmpty)
  }

  // MARK: - Helpers

  /// A store in its own throwaway directory, so tests never touch the real one.
  private func temporaryStore() throws -> DiagnosticsLogStore {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("diagnostics-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return DiagnosticsLogStore(rootURL: root)
  }
}

/// Remembers what it was handed.
private final class RecordingLogSink: LogSink, @unchecked Sendable {
  private let lock = NSLock()
  private var written: [LogEntry] = []

  var messages: [String] { lock.withLock { written.map(\.message) } }

  func write(_ entry: LogEntry) {
    lock.withLock { written.append(entry) }
  }
}
