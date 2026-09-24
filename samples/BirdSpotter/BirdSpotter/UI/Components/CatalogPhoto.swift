/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CatalogPhoto.swift
//  birdspotter
//

import ImageIO
import SwiftUI

/// Hero photos are decoded to roughly a phone's width. The bundled files are 1200 px, so
/// this halves them once on most devices and keeps a 4 MB bitmap off the heap.
nonisolated let heroPhotoWidthPx = 720

/// Browse-list thumbnails are 64 pt on a 3× screen. Decoding the full 1200 px file for a
/// row that small is what turns a 93-row scroll into a memory problem.
nonisolated let thumbnailWidthPx = 200

/// A bundled catalog photo, decoded off the main thread at the size it will be drawn.
///
/// Renders the ruled placeholder until the image arrives rather than flashing empty —
/// decoding a local JPEG usually beats the next frame anyway. `ImageIO` rather than
/// `AsyncImage`, which exists for the network case and would add a URL session to read a
/// file already sitting in the bundle.
///
/// The crop fills the frame and keeps the photo's ``FocalPointAlignment`` target in view —
/// harvested photos put the bird anywhere, and a plain center crop routinely beheads it.
/// `scaledToFill` can't say which part survives, so the fill is laid out by hand: scale to
/// cover, then let the alignment choose the origin. Clipped here rather than by every
/// caller, because a view that quietly paints outside its bounds is a bug factory.
struct CatalogPhoto: View {
  @Environment(\.theme) private var theme

  let media: SpeciesMedia
  /// Set only where the photo is the sole thing identifying the bird. Left nil on a card
  /// that prints the species name right underneath, where labelling the image would make
  /// VoiceOver read the bird twice.
  var label: String?
  var maxWidthPx: Int = heroPhotoWidthPx
  var assets = CatalogAssetStore()

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        GeometryReader { geometry in
          let container = geometry.size
          let scale = max(
            container.width / image.size.width,
            container.height / image.size.height
          )
          let content = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
          )
          let origin = FocalPointAlignment(focus: media.focalPoint)
            .offset(content: content, container: container)
          Image(uiImage: image)
            .resizable()
            .frame(width: content.width, height: content.height)
            .offset(x: origin.x, y: origin.y)
        }
        .clipped()
      } else {
        theme.colors.rule
      }
    }
    .accessibilityHidden(label == nil)
    .accessibilityLabel(label ?? "")
    .task(id: media.id) {
      image = await Self.load(url: assets.url(for: media), maxWidthPx: maxWidthPx)
    }
  }

  /// Decodes straight to a bitmap no wider than `maxWidthPx`.
  ///
  /// `createThumbnailAtIndex` rather than loading and resizing: it never materialises the
  /// full-size bitmap at all, where `UIImage(contentsOfFile:)` followed by a resize pays
  /// for the 1200 px decode first and only then throws it away.
  private static func load(url: URL?, maxWidthPx: Int) async -> UIImage? {
    guard let url else { return nil }
    return await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxWidthPx,
      ]
      guard
        let cgImage = CGImageSourceCreateThumbnailAtIndex(
          source, 0, options as CFDictionary
        )
      else { return nil }
      return UIImage(cgImage: cgImage)
    }.value
  }
}
