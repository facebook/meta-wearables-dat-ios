/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingPhoto.swift
//  birdspotter
//

import ImageIO
import SwiftUI

/// A photo the user captured, decoded off the main thread at the size it will be drawn.
///
/// The Journal's counterpart to ``CatalogPhoto``: the same ImageIO thumbnail decode — which
/// never materialises the full-size bitmap — but the bytes come from the app's captured-media
/// directory (``MediaFileStore``) rather than the bundle. Captured photos carry no focal
/// point, since a phone or the glasses framed them and not our pipeline, so the crop is a
/// plain centre fill rather than ``CatalogPhoto``'s focal one.
///
/// Fills whatever frame it is given and relies on the caller to size and clip it, the same
/// contract ``CatalogPhoto`` has with its callers. Renders the ruled placeholder until the
/// image arrives, so a row with a captured photo settles the way a catalog one does.
struct OutingPhoto: View {
  @Environment(\.theme) private var theme

  let media: OutingMedia
  let mediaFileStore: MediaFileStore
  /// Set where the photo is the only thing identifying the entry; left nil where a name
  /// prints right beside it, so VoiceOver doesn't read the entry twice.
  var label: String?
  var maxWidthPx: Int = thumbnailWidthPx

  /// Whether the photo fills its frame and loses its edges to the crop, or fits inside it
  /// whole.
  ///
  /// Filling is right nearly everywhere — a thumbnail in a row is a square by design, and a
  /// bird recognised at 44 points is recognised in the middle of the frame. Fitting exists for
  /// the one place the *composition* is the point rather than the subject: opened full screen,
  /// a photograph cropped to the phone's aspect would be a photograph with its edges quietly
  /// taken away, which is precisely what somebody who tapped to see it properly did not ask
  /// for.
  var fillsFrame = true

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: fillsFrame ? .fill : .fit)
      } else {
        theme.colors.rule
      }
    }
    .accessibilityHidden(label == nil)
    .accessibilityLabel(label ?? "")
    .task(id: media.id) {
      image = await Self.load(
        url: mediaFileStore.resolve(media.filePath),
        maxWidthPx: maxWidthPx
      )
    }
  }

  /// Decodes straight to a bitmap no wider than `maxWidthPx`, exactly as ``CatalogPhoto``
  /// does — `createThumbnailAtIndex` never pays for the full-size decode.
  private static func load(url: URL, maxWidthPx: Int) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
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
