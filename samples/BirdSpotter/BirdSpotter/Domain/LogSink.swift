/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LogSink.swift
//  birdspotter
//

import Foundation

/// Somewhere a diagnostic line ends up. Two ship: ``ConsoleLogSink`` and ``FileLogSink``.
///
/// **`write` must not block and must not throw.** It is called from whatever thread was
/// running when something happened — a DAT callback, an audio buffer's queue, the main
/// thread mid-layout — and a logger that can stall or fail its caller is a logger that
/// changes the behaviour it was installed to observe. A sink that cannot do its job drops
/// the line; ``FileLogSink`` hands the work to its own queue and returns immediately.
protocol LogSink: Sendable {
  func write(_ entry: LogEntry)
}
