/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PhotoLightbox.swift
//  birdspotter
//

import SwiftUI

/// Where a full-screen photograph gets its pixels: a picture the session is still holding, or
/// one the journal has on disk.
///
/// **Two cases rather than one, because the two are genuinely different pictures.** A session's
/// capture is a live buffer at capture resolution that has not been encoded yet — asking it for
/// a file path would mean writing one, and the whole point of encoding at Save is that a
/// discarded session never pays for compression. A journal photo is bytes on disk, decoded on
/// demand at whatever size is being drawn. The lightbox does not care which it is given; the
/// call sites cannot honestly offer the other.
enum PhotoLightboxSource {

  /// A picture already in memory — a capture on a running or just-stopped session.
  case image(CGImage)

  /// A picture in the captured-media directory, decoded when the lightbox opens.
  case media(OutingMedia)
}

/// The photograph a lightbox is open on, if one is.
///
/// The `id` is doing two jobs at once, and they have to be the same value: it identifies the
/// presentation, and it is what the zoom transition matches the thumbnail against. A screen
/// stamps it with whatever identifies the row the picture came from — a session event's stamp,
/// a media row's id — and puts the same value on that row's ``SwiftUI/View/matchedTransitionSource(id:in:)``.
struct OpenPhoto: Identifiable {
  let id: String
  let source: PhotoLightboxSource
  var caption: String?
}

/// One photograph, full screen, magnifiable — what a tapped thumbnail opens into.
///
/// **The two drags never negotiate, and that is the design.** Swipe-to-dismiss and pan want the
/// same gesture, so exactly one of them is live at a time: at rest the drag belongs to the
/// system's own interactive dismissal, and the moment the picture is magnified it belongs to the
/// pan. ``PhotoZoom/isZoomed`` is the switch, and because it is one reading of one value there is
/// no state in which both are half-enabled — which is the failure mode every hand-rolled viewer
/// of this kind eventually grows.
///
/// The close control is not a fallback for that. A magnified picture has no dismissing drag left,
/// so without a button the only way out would be to zoom back out first, and a viewer that traps
/// somebody who pinched too far is a viewer with a bug in it.
///
/// Presented as a `.fullScreenCover` carrying `.navigationTransition(.zoom)`, which is what
/// makes the thumbnail grow into the picture and the picture fall back into the thumbnail. The
/// transition resolves its source at the moment it runs rather than at the moment it opened, so
/// a log that scrolled underneath — the live session's does, on every arrival — returns the
/// picture to wherever the row is *now*; and a row that has gone entirely degrades to a fade on
/// its own. Both are the right answer, and neither needed writing.
///
/// **The zoom is also why the appearance is the caller's to ask for.** Growing the picture scales
/// the screen underneath it down and rounds its corners, and what shows in the margin that opens
/// up is the window — which a view merely painted dark has told nothing. So a caller already
/// running dark asks for the dark appearance at its own presentation of this cover, and a caller
/// running light leaves the margin light to match the screen the picture came off.
///
/// Asking for it here, at the presentation, is what keeps it invisible: the request lands on the
/// window in the same instant the zoom begins, while the margin still has no width. Asking any
/// earlier — around a whole flow, say — repaints a screen that is still on display, and *that* is
/// seen, as a flash of the other palette before the cover it belongs to has arrived.
struct PhotoLightbox: View {
  @Environment(\.theme) private var theme

  let source: PhotoLightboxSource
  /// What the app made of this picture, printed under it — a bird's name, or nothing where the
  /// app never named one.
  var caption: String?
  var mediaFileStore: MediaFileStore?
  let onClose: () -> Void

  /// The magnification, and the whole of the state this screen holds. See ``PhotoZoom``.
  @State private var zoom = PhotoZoom.idle

  /// What the pinch is measured against — a magnify gesture reports its total since the fingers
  /// landed, so the step is this over the last reading rather than the value itself.
  @State private var pinchAnchor = 1.0

  /// The drag's own running total, for the same reason ``pinchAnchor`` exists: a drag reports
  /// how far it has come, and ``PhotoZoom/panned(byX:y:in:fitting:)`` wants how far it has moved
  /// since last time.
  @State private var dragAnchor: CGSize = .zero

  /// The viewport, measured. Nothing can be clamped until this has landed, which is why
  /// ``PhotoZoom/settled(in:fitting:)`` is required to survive a zero.
  @State private var viewport: CGSize = .zero

  var body: some View {
    ZStack {
      // The cabinet's own black rather than a system scrim: this opens over the session's
      // dark cover as often as over the journal's paper, and a photograph is looked at
      // against one ground or the other, never against whichever it happened to come from.
      theme.colors.ink.ignoresSafeArea()

      picture
        .scaleEffect(zoom.scale)
        .offset(x: zoom.offsetX, y: zoom.offsetY)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(.rect)
        .gesture(magnify)
        // **Only while magnified**, so at rest the cover's own dismissing drag is the one
        // that sees the touch — see the note on this type. `.subviews` disables this
        // gesture without disabling anything around it.
        .gesture(pan, including: zoom.isZoomed ? .all : .subviews)
        .onTapGesture(count: 2) { toggleZoom() }
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: {
          viewport = $0
        }

      controls
    }
    .accessibilityAction(named: "Close") { onClose() }
  }

  @ViewBuilder
  private var picture: some View {
    switch source {
    case let .image(image):
      Image(decorative: image, scale: 1, orientation: .up)
        .resizable()
        .aspectRatio(contentMode: .fit)

    case let .media(media):
      if let mediaFileStore {
        // A decode target in the screen's own pixels rather than the thumbnail's: this is
        // the one place the whole photograph is being looked at, and the row's 176 blown
        // up to fill a phone is a row's thumbnail with its pixels showing. Asked for at
        // the ceiling the magnification can reach, so pinching in finds detail rather
        // than finding the decode.
        OutingPhoto(
          media: media,
          mediaFileStore: mediaFileStore,
          maxWidthPx: lightboxDecodeWidthPx,
          fillsFrame: false
        )
      }
    }
  }

  /// The close mark and the caption — the only two things laid over the picture.
  ///
  /// Both ride the safe area rather than the picture: a photograph is fitted, so what is behind
  /// them at any moment is the black above and below it as often as the image itself, and
  /// chrome that tracked the picture would move every time the magnification did.
  private var controls: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: onClose) {
          Image(glyph: theme.glyphs.close)
            .font(.system(size: lightboxCloseGlyphSize))
            .foregroundStyle(theme.colors.textPrimary)
            .padding(theme.space.related)
            .background(theme.colors.ink.opacity(lightboxChromeOpacity), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close this photo")
      }

      Spacer()

      if let caption, !caption.isEmpty {
        PlateLabel(text: caption, color: theme.colors.gilt)
          .padding(.horizontal, theme.space.related)
          .padding(.vertical, theme.space.snug)
          .background(theme.colors.ink.opacity(lightboxChromeOpacity), in: .capsule)
      }
    }
    .padding(theme.space.gutter)
  }

  /// The pinch. Reported as a total since the fingers landed, so the step is the difference
  /// from the last reading — see ``pinchAnchor``.
  private var magnify: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let step = value.magnification / pinchAnchor
        pinchAnchor = value.magnification
        zoom = zoom.scaled(by: step, in: viewport, fitting: fittedSize)
      }
      .onEnded { _ in pinchAnchor = 1 }
  }

  /// The pan, live only while there is somewhere to pan to.
  private var pan: some Gesture {
    DragGesture()
      .onChanged { value in
        zoom = zoom.panned(
          byX: value.translation.width - dragAnchor.width,
          y: value.translation.height - dragAnchor.height,
          in: viewport,
          fitting: fittedSize
        )
        dragAnchor = value.translation
      }
      .onEnded { _ in dragAnchor = .zero }
  }

  private func toggleZoom() {
    withAnimation(.snappy(duration: lightboxZoomDuration)) {
      zoom = zoom.toggledZoom(in: viewport, fitting: fittedSize)
    }
  }

  /// The photograph as it sits at rest: the whole picture fitted inside the viewport, letterboxed
  /// on whichever axis has room to spare.
  ///
  /// **This, and not the viewport, is what the pan clamps against.** The offset limit is the
  /// overhang past the screen, and a letterboxed picture at 2× may genuinely have overhang on
  /// one axis and none on the other — clamping both against the viewport would let a photograph
  /// be dragged up and down inside its own black bars.
  private var fittedSize: CGSize {
    guard let aspect = sourceAspect, viewport.width > 0, viewport.height > 0 else {
      return viewport
    }
    let viewportAspect = viewport.width / viewport.height
    return aspect > viewportAspect
      ? CGSize(width: viewport.width, height: viewport.width / aspect)
      : CGSize(width: viewport.height * aspect, height: viewport.height)
  }

  /// The picture's width over its height, or `nil` for a journal photo saved before the
  /// dimensions were recorded — in which case the fit falls back to the viewport, and the pan
  /// is merely more generous than it needed to be.
  private var sourceAspect: Double? {
    switch source {
    case let .image(image):
      image.height > 0 ? Double(image.width) / Double(image.height) : nil
    case let .media(media):
      if let width = media.width, let height = media.height, height > 0 {
        Double(width) / Double(height)
      } else {
        nil
      }
    }
  }
}

/// How wide a journal photo is decoded for the lightbox. Generous, because this is the one
/// screen where the whole photograph is the subject and the magnification goes to ``maxScale``.
private let lightboxDecodeWidthPx = 2048

/// The close mark's drawn size — the app's other round glyph buttons, at the size a thumb finds
/// without looking.
private let lightboxCloseGlyphSize: CGFloat = 17

/// How dark the chrome laid over a picture sits. The same depth the session's controls use over
/// the strip and the viewfinder — one value for everything this app floats over an image.
private let lightboxChromeOpacity: Double = 0.6

/// How long a double-tapped magnification takes. Short enough to feel like the picture answered
/// the tap rather than played an animation at it.
private let lightboxZoomDuration: TimeInterval = 0.25
