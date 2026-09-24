/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesCameraRepository.swift
//  birdspotter
//

import Foundation

/// The DAT-backed ``GlassesCameraRepository``.
///
/// Thin on purpose: a capture is scoped to the running session's camera capability, and the
/// session — with its handles — lives in ``DatGlassesSessionRepository``. This type exists so
/// the *domain* keeps camera and session apart the way the feature docs split them, while the
/// data layer admits they are one Bluetooth link underneath.
nonisolated final class DatGlassesCameraRepository: GlassesCameraRepository, @unchecked Sendable {

  private let link: DatGlassesSessionRepository

  init(link: DatGlassesSessionRepository) {
    self.link = link
  }

  /// The photo capability takes both settings on the request, so both are asked for and
  /// both arrive.
  let honoursCaptureSettings = true

  func capturePhoto(
    format: PhotoFormat,
    resolution: CaptureResolution,
    quality: CaptureQuality
  ) async throws -> CapturedPhoto {
    try await link.captureThroughActiveCamera(
      format: format,
      resolution: resolution,
      quality: quality
    )
  }
}
