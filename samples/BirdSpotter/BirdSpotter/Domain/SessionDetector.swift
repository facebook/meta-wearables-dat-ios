/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionDetector.swift
//  birdspotter
//

import Foundation

/// Whatever is deciding that a bird was heard, or that the watcher said something.
///
/// The app ships **no classifier and no speech model**, and this protocol is where the absence
/// is kept honest: the implementation the app runs is the Demo Director — ``DemoDirector``, as
/// ``PresetDemoDirector`` — which plays the ambient calls of the armed ``DemoPreset`` and is
/// named so that nobody has to guess. A real classifier implements this one member and the
/// session above it does not change.
///
/// Cold, per the architecture contract: iterating starts the preset's timeline, cancelling abandons
/// it. The findings carry no timestamp; the session stamps them against its own clock — see
/// ``SessionFinding``.
nonisolated protocol SessionDetector: Sendable {

  /// Findings as they are made, until the iteration ends.
  func findingStream() -> AsyncThrowingStream<SessionFinding, Error>
}
