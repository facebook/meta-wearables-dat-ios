/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesSpeechRepository.swift
//  birdspotter
//

import Foundation

/// The DAT-backed ``GlassesSpeechRepository``.
///
/// Thin on purpose, for the same reason ``DatGlassesMotionRepository`` is: the speech
/// capability is scoped to the running session, and the session — with its handles — lives in
/// ``DatGlassesSessionRepository``. This type exists so the *domain* keeps the recogniser and
/// the session apart the way the feature docs split them, while the data layer admits they are
/// one Bluetooth link underneath.
nonisolated final class DatGlassesSpeechRepository: GlassesSpeechRepository, @unchecked Sendable {

  private let link: DatGlassesSessionRepository

  init(link: DatGlassesSessionRepository) {
    self.link = link
  }

  func transcriptionStream() -> AsyncStream<Transcription> {
    link.transcriptionsFromActiveSession()
  }

  func speechStateStream() -> AsyncStream<GlassesSpeechState> {
    link.speechStateFromActiveSession()
  }
}
