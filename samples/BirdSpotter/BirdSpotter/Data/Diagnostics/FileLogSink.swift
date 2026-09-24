/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FileLogSink.swift
//  birdspotter
//

import Foundation

/// Writes lines into the rolling ``DiagnosticsLogStore``, off whatever thread logged them.
///
/// **One serial queue, and it is the whole design.** ``LogSink`` promises not to block its
/// caller, and the caller here is routinely a DAT callback or an audio queue — code that
/// must not go anywhere near a disk. Hopping to a `.utility` queue keeps the write off the
/// hot path, and keeping that queue *serial* is what makes the file's order the order
/// things actually happened in. A concurrent queue would interleave lines and quietly
/// destroy the only property a log has.
///
/// It is also what lets ``DiagnosticsLogStore/append(_:)`` be a single-writer method: this
/// is the only thing that calls it.
///
/// The line is rendered on the calling thread, deliberately — ``LogEntry/fileLine`` is
/// string work, not I/O, and rendering it here means the queue holds a `String` rather
/// than a closure capturing whatever the caller had in scope.
struct FileLogSink: LogSink {

  private let store: DiagnosticsLogStore
  private let queue: DispatchQueue

  init(store: DiagnosticsLogStore) {
    self.store = store
    self.queue = DispatchQueue(
      label: "com.pixelandtexel.birdspotter.diagnostics",
      qos: .utility
    )
  }

  func write(_ entry: LogEntry) {
    let line = entry.fileLine
    queue.async { [store] in store.append(line) }
  }
}
