/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesMotionRepository.swift
//  birdspotter
//

import Foundation

/// The DAT-backed ``GlassesMotionRepository``.
///
/// Thin on purpose, for the same reason ``DatGlassesInputRepository`` is: the motion capability
/// is scoped to the running session, and the session — with its handles — lives in
/// ``DatGlassesSessionRepository``. This type exists so the *domain* keeps the sensors and the
/// session apart the way the feature docs split them, while the data layer admits they are one
/// Bluetooth link underneath.
@MainActor
final class DatGlassesMotionRepository: GlassesMotionRepository {

  private let link: DatGlassesSessionRepository

  init(link: DatGlassesSessionRepository) {
    self.link = link
  }

  func motionStream() -> AsyncStream<GlassesMotionSample> {
    link.motionSamplesFromActiveSession()
  }
}
