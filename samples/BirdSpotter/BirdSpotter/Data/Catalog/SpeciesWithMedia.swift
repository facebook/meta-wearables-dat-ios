/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeciesWithMedia.swift
//  birdspotter
//

import Foundation

/// A species and everything bundled for it — what a species card renders.
///
/// Unlike its Journal counterpart, `media` is never empty in practice: the seed pipeline
/// refuses to ship a species without three photos and one vocalization. The accessors
/// still return optionals, because a shipped asset going missing should degrade the card,
/// not crash it.
nonisolated struct SpeciesWithMedia: Identifiable, Equatable, Sendable {
  var species: Species
  var media: [SpeciesMedia]

  var id: String { species.id }

  /// Every photo, hero first, then in the order the catalog set.
  var photos: [SpeciesMedia] {
    media
      .filter { $0.type == .photo }
      .sorted { ($0.isPrimary ? 0 : 1, $0.sortOrder) < ($1.isPrimary ? 0 : 1, $1.sortOrder) }
  }

  /// Song where the species has one, call otherwise — one clip per species.
  ///
  /// Named types rather than "everything that isn't a photo": the catalog also ships a
  /// ``SpeciesMediaType/sonogram``, which is an image, and the old test would have
  /// handed it to the player as a clip to play.
  var audio: [SpeciesMedia] {
    media.filter { $0.type == .song || $0.type == .call }.sorted { $0.sortOrder < $1.sortOrder }
  }

  /// The spectrogram of ``referenceAudio``, drawn beside it. One per species, or none.
  var sonogram: SpeciesMedia? {
    media.first { $0.type == .sonogram }
  }

  /// The card's lead image.
  var heroPhoto: SpeciesMedia? { photos.first }

  /// What the play button plays.
  var referenceAudio: SpeciesMedia? {
    audio.first { $0.isPrimary } ?? audio.first
  }

  init(species: Species, media: [SpeciesMedia] = []) {
    self.species = species
    self.media = media
  }
}
