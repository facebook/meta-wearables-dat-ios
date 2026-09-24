/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CatalogAssetStore.swift
//  birdspotter
//

import Foundation

/// Turns a catalog `SpeciesMedia.assetKey` into a file on this platform.
///
/// The shipped database stores logical keys (`northern-cardinal/photo-01`) and no paths,
/// so this is the one type that knows they live in the app bundle under `SeedData/birds/`.
/// Everything above the data layer passes rows around and never builds a path.
///
/// The read-only mirror of ``MediaFileStore``, which owns what the user captured.
/// Neither knows about the other.
nonisolated struct CatalogAssetStore: Sendable {

  private static let root = "SeedData/birds"

  let bundle: Bundle

  init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  /// The bundled file, or nil when it is not there.
  ///
  /// Optional rather than throwing: a shipped file that went astray should leave a card
  /// without its photo, not take the screen down. The only caller that treats it as an
  /// error is the test that asserts every catalog row resolves.
  func url(for media: SpeciesMedia) -> URL? {
    let key = media.assetKey as NSString
    return bundle.url(
      forResource: key.lastPathComponent,
      withExtension: media.type.fileExtension,
      subdirectory: "\(Self.root)/\(key.deletingLastPathComponent)"
    )
  }

  func exists(_ media: SpeciesMedia) -> Bool {
    url(for: media) != nil
  }
}

extension SpeciesMediaType {
  /// The file extension the seed pipeline guarantees for each media type: photos ship
  /// as JPEG, vocalizations as MP3, and sonograms as PNG under `SeedData/birds/`.
  /// Storing it per row would be a column that is the same value 465 times over.
  ///
  /// PNG rather than JPEG for the sonogram because it is a synthetic image of
  /// hard-edged marks on a flat ground — exactly what JPEG smears and what a small
  /// palette compresses better than JPEG can.
  nonisolated var fileExtension: String {
    switch self {
    case .photo: "jpg"
    case .song, .call: "mp3"
    case .sonogram: "png"
    }
  }
}
