/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingSonogram.swift
//  birdspotter
//

import SwiftUI

/// A saved outing's sonogram, playing back — the live strip's other half, exactly as the
/// design doc promises it: no touch while recording, all touch afterwards.
///
/// The same instrument, read the other way round. The live strip pins *now* to the right
/// edge and the session slides under it; here the **playhead holds the centre** and the
/// outing slides under that — pressing play is what scrolls it. The whole recording is
/// reachable the other way too: a drag scrubs, a tap seeks within the window, and both hand
/// the position up rather than keeping any state of their own.
///
/// Colours come from ``SonogramPalette`` rather than the theme, like every strip, so what
/// the journal shows is what the session showed. Rasterised per redraw from the buffer's
/// window, the way `SonogramStrip` does it — one image, one pass, however long the outing
/// ran.
struct OutingSonogram: View {
  @Environment(\.theme) private var theme

  let sonogram: SonogramBuffer
  let positionMs: Int64
  let totalMs: Int64

  /// The playhead under a moving finger, reported every frame of the drag.
  let onScrub: (Int64) -> Void

  /// Where the finger settled — the end of a drag, or a tap. Parted from ``onScrub`` so a
  /// recording that was playing can pick up here rather than at every frame of the drag.
  let onSeek: (Int64) -> Void

  /// The playhead position when the current drag landed — the anchor deltas move from.
  @State private var dragStartMs: Int64?

  var body: some View {
    ZStack {
      stripGround

      if let image = stripImage() {
        Image(decorative: image, scale: 1, orientation: .up)
          .resizable()
          .interpolation(.medium)
      }

      // The playhead, dead centre — always drawn: unlike the live strip's edge line it
      // marks a position that exists at every moment of a finished recording.
      theme.colors.gilt.frame(width: playheadWidth)
    }
    .frame(height: stripHeight)
    // Rounded like the reference sonogram on a bird's page: this one is read in the
    // page's gutter, not watched edge to edge like the live instrument.
    .clipShape(RoundedRectangle(cornerRadius: theme.space.snug))
    .accessibilityElement()
    .accessibilityLabel("Recording sonogram")
    .overlay { scrubLayer }
  }

  /// A transparent layer that turns a tap or a horizontal drag into a scrub — the bird
  /// page's gesture, moved into window coordinates. Simultaneous with the page's scroll,
  /// so a vertical swipe that happens to start on the strip still scrolls the page.
  ///
  /// Dragging moves the recording under the fixed playhead, so it runs the way paper
  /// would: content follows the finger, the playhead stays put.
  private var scrubLayer: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      Color.clear
        .contentShape(.rect)
        .simultaneousGesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard width > 0 else { return }
              let dx = abs(value.translation.width)
              let dy = abs(value.translation.height)
              guard dx > dy, dx > Self.slop else { return }
              let anchor = dragStartMs ?? positionMs
              if dragStartMs == nil { dragStartMs = anchor }
              onScrub(
                scrubbed(from: anchor, by: value.translation.width, across: width)
              )
            }
            .onEnded { value in
              let anchor = dragStartMs
              dragStartMs = nil
              guard width > 0 else { return }
              if let anchor {
                // The drag has been scrubbing through onChanged; this settles
                // it where the finger let go, which is where playback resumes.
                onSeek(
                  scrubbed(from: anchor, by: value.translation.width, across: width)
                )
              } else if abs(value.translation.width) < Self.slop,
                abs(value.translation.height) < Self.slop
              {
                // A tap — negligible travel either way — seeks to the moment
                // under the finger.
                let windowStart = positionMs - playbackWindowMillis / 2
                let tapped =
                  windowStart
                  + Int64(
                    value.location.x / width * CGFloat(playbackWindowMillis)
                  )
                onSeek(min(max(tapped, 0), totalMs))
              }
            }
        )
    }
  }

  /// Where a drag of `translation` points has carried the playhead from its anchor: the
  /// recording moves under the finger, so dragging right walks the clock back.
  private func scrubbed(from anchor: Int64, by translation: CGFloat, across width: CGFloat) -> Int64 {
    let dragged = Int64(translation / width * CGFloat(playbackWindowMillis))
    return min(max(anchor - dragged, 0), totalMs)
  }

  /// The visible columns, coloured and packed into an image — `SonogramStrip`'s raster
  /// with the window centred on the playhead instead of ending at now.
  private func stripImage() -> CGImage? {
    let columns = Int(playbackWindowSeconds * sonogramColumnsPerSecond)
    guard columns > 0 else { return nil }

    let start = Double(positionMs) / 1000.0 - playbackWindowSeconds / 2
    // Floored, not truncated: the window's start goes negative around the outing's
    // opening seconds, and truncation rounds those towards zero — a one-column stutter.
    let first = Int((start * sonogramColumnsPerSecond).rounded(.down))
    let greyscale = sonogram.window(from: first, columns: columns)
    let ramp = Self.ramp

    var pixels = [UInt8](repeating: 0, count: greyscale.count * 4)
    for i in greyscale.indices {
      let colour = ramp[Int(greyscale[i])]
      pixels[i * 4] = colour.red
      pixels[i * 4 + 1] = colour.green
      pixels[i * 4 + 2] = colour.blue
      pixels[i * 4 + 3] = 255
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: columns,
      height: sonogramBins,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: columns * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )
  }

  /// Travel, in points, before a drag counts as a scrub rather than a tap or a scroll.
  private static let slop: CGFloat = 4

  /// The ramp, built once — see `SonogramStrip`'s note on why it is precomputed.
  private static let ramp = SonogramPalette.ramp()
}

/// Seconds across the strip — the live timeline's eight, so a bird's call is the same width
/// on the journal page as it was on the session that heard it.
private let playbackWindowSeconds = 8.0

private let playbackWindowMillis = Int64(playbackWindowSeconds * 1000)

/// The live strip's height, kept — same instrument, same proportions.
private let stripHeight: CGFloat = 132

/// The playhead, in points — a hairline would disappear against a bright column.
private let playheadWidth: CGFloat = 2

/// Magma's darkest end — what the strip shows where the outing held no sound.
private let stripGround: Color = {
  let ground = SonogramPalette.ramp()[0]
  return Color(
    red: Double(ground.red) / 255,
    green: Double(ground.green) / 255,
    blue: Double(ground.blue) / 255
  )
}()
