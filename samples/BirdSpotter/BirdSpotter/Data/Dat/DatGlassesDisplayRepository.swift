/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesDisplayRepository.swift
//  birdspotter
//

import Foundation
import ImageIO
import MWDATDisplay
import UIKit

/// The DAT-backed ``GlassesDisplayRepository``.
///
/// Thin where the camera's twin is thin — the display capability rides the running session,
/// whose handles live in ``DatGlassesSessionRepository``. **The glasses hold no state**, and
/// every send replaces the screen whole; a card that says everything it has to say at once
/// is the layout that costs that model nothing. Nothing here is remembered between sends,
/// so a new identification is a new card and there is no page to keep straight.
///
/// The photographs are the catalog's own, scaled once at load to the display's canvas:
/// bytes sent up a Bluetooth link are time the wearer spends waiting, and the bundled
/// 1200 px originals are four times the pixels the panel can draw.
nonisolated final class DatGlassesDisplayRepository: GlassesDisplayRepository, Sendable {

  private let link: DatGlassesSessionRepository
  private let assets: CatalogAssetStore

  init(link: DatGlassesSessionRepository, assets: CatalogAssetStore) {
    self.link = link
    self.assets = assets
  }

  func showGallery(for bird: SpeciesWithMedia, message: String?) async {
    // A photograph that will not load is dropped rather than shown as a hole; a bird
    // with none still sends — the names and the description are worth having.
    let photos = bird.photos.compactMap(load)
    if photos.count < bird.photos.count {
      BirdLog.warning(
        .glasses,
        "display — \(bird.photos.count - photos.count) of \(bird.photos.count) photographs"
          + " would not load for \(bird.species.commonName); sending without them"
      )
    }
    do {
      BirdLog.debug(
        .glasses,
        "display — sending \(bird.species.commonName) (\(photos.count) photographs)"
      )
      try await link.sendThroughActiveDisplay(card(for: bird, photos: photos, message: message))
      // The send reporting nothing back on success is why this line exists: without it,
      // a card that landed and a card that vanished read identically from the phone.
      BirdLog.info(.glasses, "display — \(bird.species.commonName) is on the glass")
    } catch {
      // A pair with no display, or none on the link — the identification already
      // landed on the timeline, so there is nobody to tell but the log.
      BirdLog.info(.glasses, "display — no display to carry \(bird.species.commonName)")
    }
  }

  func clear() async {
    await link.clearActiveDisplay()
  }

  /// The card: the bird's two names at the top, its photographs stacked under them, and
  /// the description last — read top to bottom, the order a field guide answers in. A
  /// written `message` takes the description's place and nothing else moves: the card
  /// keeps one shape however its last line was authored.
  private func card(for bird: SpeciesWithMedia, photos: [UIImage], message: String?) -> FlexBox {
    FlexBox(direction: .column, spacing: 12) {
      Text(bird.species.commonName, style: .heading)
      Text(bird.species.scientificName, style: .meta, color: .secondary)
      for photo in photos {
        Image(image: photo)
      }
      Text(message ?? bird.species.aboutText, style: .body)
    }
    .padding(16)
  }

  /// A catalog photograph at the display's own size, decoded without ever inflating the
  /// original: the thumbnailing path reads the JPEG down to ``displayPhotoMaxPixels``
  /// directly, the same bargain the catalog's on-screen photos strike.
  private func load(_ media: SpeciesMedia) -> UIImage? {
    guard let url = assets.url(for: media),
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: displayPhotoMaxPixels,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }
}

/// The display's canvas is 600 × 600, and a photograph scaled past it is bytes the link
/// carries for nothing.
private nonisolated let displayPhotoMaxPixels = 600
