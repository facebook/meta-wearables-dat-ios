/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesDisplayRepository.swift
//  birdspotter
//

import Foundation

/// The display on the glasses, reduced to the one thing a session asks of it: **the bird
/// just identified, put where the wearer is already looking.**
///
/// What goes up is the whole gallery at once: the bird's two names, its catalog photographs
/// stacked under them, and a line of description last — the phone stamps the identification
/// onto the timeline and the glasses answer the next question, *what does it look like?*,
/// without anyone reaching for a pocket or pressing anything.
///
/// Both calls are quiet about hardware. Most pairs have no display, and an identification
/// is not allowed to care: a send with nowhere to land simply lands nowhere, and the
/// session goes on exactly as it would have. Asking first would make every identification
/// wait on a question whose answer changes nothing about the timeline.
nonisolated protocol GlassesDisplayRepository: Sendable {

  /// Puts the bird's gallery on the display, whole. Replaces whatever the display was
  /// showing — a new identification is a new gallery.
  ///
  /// `message` stands in for the catalog's description when a presenter has written one —
  /// the card is otherwise identical, and `nil` means the bird's own line goes up as ever.
  func showGallery(for bird: SpeciesWithMedia, message: String?) async

  /// Takes the gallery down. A session that has stopped has nothing to say up there.
  func clear() async
}

extension GlassesDisplayRepository {
  /// The everyday send: the bird's card exactly as the catalog wrote it.
  func showGallery(for bird: SpeciesWithMedia) async {
    await showGallery(for: bird, message: nil)
  }
}
