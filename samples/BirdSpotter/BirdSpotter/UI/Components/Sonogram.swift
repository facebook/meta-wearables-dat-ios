/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  Sonogram.swift
//  birdspotter
//

import ImageIO
import SwiftUI

/// The spectrogram of a bird's reference clip, drawn under the play button with a playhead
/// that tracks playback.
///
/// The seed pipeline renders the strip from the same trimmed audio the play button plays, so
/// the playhead crossing a mark and the ear hearing it line up. Shown whole, never cropped: a
/// spectrogram is data — a center crop would lop off the top of every bird's frequency range —
/// so this fits the image where ``CatalogPhoto`` fills its frame.
struct Sonogram: View {
  @Environment(\.theme) private var theme

  let media: SpeciesMedia
  /// `0...1` playback position; the playhead and the reveal read from it. Zero draws the
  /// strip clean, the way it looks before the clip has been played.
  var progress: Double
  /// Called with a `0...1` position as the strip is tapped or dragged. Nil leaves the
  /// sonogram a plain picture; the bird page passes the view model's `seek(to:)` to make it
  /// a scrubber.
  var onScrub: ((Double) -> Void)?

  var assets = CatalogAssetStore()

  @State private var image: UIImage?
  /// Where the finger is during a scrub, which the playhead follows instead of `progress`.
  /// This keeps the head under the finger even while the clip plays on and the ticker is
  /// still writing `progress` — the two only have to agree once the finger lifts.
  @State private var dragFraction: Double?

  /// The strip is 640 × 160 out of the pipeline.
  private static let aspect: CGFloat = 4
  private static let widthPx = 1200

  var body: some View {
    // A fixed 4:1 box so the strip holds its shape whether or not the image has decoded.
    Color.clear
      .aspectRatio(Self.aspect, contentMode: .fit)
      .overlay { plate }
      .overlay { if onScrub != nil { scrubLayer } }
      .clipShape(.rect(cornerRadius: theme.space.snug))
      .task(id: media.id) {
        image = await Self.load(url: assets.url(for: media), maxWidthPx: Self.widthPx)
      }
      .accessibilityLabel("Sonogram")
  }

  private var plate: some View {
    // Finger wins while scrubbing; otherwise the playback position.
    let position = dragFraction ?? progress
    return ZStack {
      // Ground and placeholder both read as the strip's own black, so a slow decode or a
      // missing file leaves a dark plate rather than a flash of paper.
      theme.colors.lacquer

      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
      }

      if position > 0 {
        GeometryReader { geometry in
          let width = geometry.size.width
          let height = geometry.size.height
          let x = width * CGFloat(min(max(position, 0), 1))

          // Dim what has not played yet; the swept head stays at full strength.
          theme.colors.lacquer.opacity(0.5)
            .frame(width: max(width - x, 0), height: height)
            .position(x: (x + width) / 2, y: height / 2)

          // The playhead, a touch heavier under the finger.
          theme.colors.gilt
            .frame(width: dragFraction == nil ? 2 : 3, height: height)
            .position(x: x, y: height / 2)
        }
      }
    }
  }

  /// A transparent layer that turns a tap or a horizontal drag into a scrub. Simultaneous
  /// with the page's scroll, so a vertical swipe that happens to start on the strip still
  /// scrolls the page: a scrub commits only once the drag is clearly horizontal, and a tap
  /// (negligible travel) seeks on release rather than on first touch.
  private var scrubLayer: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      Color.clear
        .contentShape(.rect)
        .simultaneousGesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard let onScrub, width > 0 else { return }
              let dx = abs(value.translation.width)
              let dy = abs(value.translation.height)
              guard dx > dy, dx > Self.slop else { return }
              let fraction = min(max(value.location.x / width, 0), 1)
              dragFraction = fraction
              onScrub(fraction)
            }
            .onEnded { value in
              defer { dragFraction = nil }
              guard let onScrub, width > 0 else { return }
              // A tap — negligible travel either way — seeks to where it landed;
              // a drag has already seeked through `onChanged`.
              if abs(value.translation.width) < Self.slop,
                abs(value.translation.height) < Self.slop
              {
                onScrub(min(max(value.location.x / width, 0), 1))
              }
            }
        )
    }
  }

  /// Travel, in points, before a drag counts as a scrub rather than a tap or a scroll.
  private static let slop: CGFloat = 4

  /// Decodes the strip off the main thread, mirroring ``CatalogPhoto`` — `ImageIO` rather
  /// than `AsyncImage`, which would add a URL session to read a file already in the bundle.
  private static func load(url: URL?, maxWidthPx: Int) async -> UIImage? {
    guard let url else { return nil }
    return await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
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

#Preview("Sonogram") {
  Sonogram(
    media: SpeciesMedia(
      id: "northern-cardinal-sonogram-01",
      speciesId: "northern-cardinal",
      type: .sonogram,
      assetKey: "northern-cardinal/sonogram-01",
      isPrimary: false,
      sortOrder: 0
    ),
    progress: 0.45
  )
  .padding()
  .birdSpotterTheme()
}
