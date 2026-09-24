/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionTimeline.swift
//  birdspotter
//

import SwiftUI

/// The session's timeline: what it heard, and everything that has landed on it.
///
/// Two parts, one above the other. The **strip** is the spine — a live sonogram, scrolling right to
/// left, with the right edge always *now*. Under it, the **log**: every photo, phrase and
/// identification, newest first, each against the second of the session it happened at.
///
/// **The log is why the marks came off the strip.** They used to sit in two lanes either side of it,
/// pinned to their own column — which was a fine picture of the last eight seconds and nothing at
/// all after that. A detection nobody was looking at slid off the left edge and was gone. The
/// timeline's job is to say *when*; keeping the answers only where they were about to scroll away
/// was the one place it wasn't doing it. The stamp on a log row carries the same fact the mark's
/// position did, and carries it for the whole session.
///
/// The strip still runs **edge to edge** — it is an instrument, and its right edge and the phone's
/// are the same edge. The log is set in a gutter like everything else in the app that is read
/// rather than watched.
///
/// **The strip takes no touch.** While the microphone is open it shows now, and only now: a watcher
/// who has dragged back four seconds is a watcher no longer looking at what the app is hearing, and
/// it is the largest target on the screen. The log below it scrolls freely, which is where a
/// wandering thumb belongs — going back through a session ought to cost nothing, and nothing there
/// can move the live edge.
struct SessionTimeline: View {
  @Environment(\.theme) private var theme

  let sonogram: SonogramBuffer
  let elapsed: Double
  let session: RealtimeSession

  /// What the log says before anything has landed on it — see ``RealtimeUiState/emptyLogLabel``.
  let emptyLabel: String

  /// How much room the shutter takes at the foot of the screen, which the log runs under.
  let footroom: CGFloat

  /// Ends the recording. The control for it sits **on** the strip — see ``stopControl``.
  let onStop: () -> Void

  /// Which reading the strip is showing, and how to change it. Owned by the screen above, which
  /// is what remembers it between sessions — see ``SessionSettingsStore``.
  let reading: StripReading
  let onReadingChange: (StripReading) -> Void

  /// Whether a reachable pair has a panel to draw on — what makes a bird on the log pressable.

  /// Puts a bird already on the log back on the display — see
  /// ``RealtimeViewModel/showCard(_:)``.
  let onShowCard: (String) -> Void

  /// The window **ends at now**: the newest column sits on the right edge from the session's
  /// first second, and everything older slides off the left.
  ///
  /// Deliberately not clamped to zero. A session younger than one window would otherwise fill
  /// left-to-right and only begin scrolling once it was eight seconds old — two different
  /// motions for one strip, and a right edge that means "now" only after the first eight
  /// seconds. Letting the start go negative buys the same motion throughout: the session
  /// arrives at the right edge over silence, because ``SonogramBuffer/window(from:columns:)``
  /// answers zero for a column before the session began.
  private var start: Double { elapsed - timelineWindowSeconds }

  var body: some View {
    VStack(spacing: 0) {
      strip

      SessionLog(
        session: session,
        emptyLabel: emptyLabel,
        footroom: footroom,
        onShowCard: onShowCard
      )
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  /// The spine — in whichever of its two readings is up — and the two controls that belong on the
  /// instrument rather than beside it.
  ///
  /// **The strip still takes no touch; the two things laid over it do.** A tap anywhere else on
  /// it does nothing at all, which is the whole reason the live edge cannot be dragged away from
  /// now. What sits on it is a stop and a choice of reading, both of which are about the
  /// instrument and would be homeless anywhere else on the screen.
  private var strip: some View {
    ZStack {
      // The palette's own ground rather than `lacquer`, so a strip with nothing on it yet is
      // the same black as one the pipeline rendered. It is the ground under both readings —
      // whatever is drawn on top, an empty instrument is the same black.
      stripGround

      switch reading {
      case .sonogram: sonogramReading
      case .waveform: waveformReading
      }
    }
    .frame(height: stripHeight)
    // Square and full-bleed: the strip is an instrument reading edge to edge, and a rounded
    // corner would be the app rounding off the seconds at either end of the window.
    .clipped()
    .accessibilityElement()
    .accessibilityLabel(reading.label)
    .overlay(alignment: .bottom) { stripControls }
  }

  /// The instrument's foot: the choice of reading at one end, the stop at the other, **on one
  /// line**.
  ///
  /// **One row rather than two overlays, and that is the whole point of it.** The two used to be
  /// anchored separately — the stop bottom-centre, the switch bottom-trailing — which meant two
  /// capsules of slightly different heights sitting on a shared bottom edge and therefore on two
  /// different centre lines. A row centres them on each other, so the difference in their heights
  /// is spent symmetrically and the strip's foot reads as one band of chrome instead of two things
  /// that nearly line up.
  ///
  /// **The stop is at the trailing end because that is the thumb's end.** Centred, it sat directly
  /// under whatever the eye was reading on the instrument, and it is the one control here that
  /// ends the recording — a corner is further from a stray thumb than the middle of the screen is,
  /// and the trailing corner is the one a right hand reaches without crossing the strip. That puts
  /// the reading switch at the leading end, which is where the quieter of the two belongs anyway.
  ///
  /// Neither child is padded from here: each carries its own `related` inset, which is both its
  /// tap target and its clearance from the strip's edges — see ``stopControl``. Padding the row as
  /// well would be a second number in a gap that already has one.
  private var stripControls: some View {
    HStack(spacing: 0) {
      readingSwitch
      Spacer(minLength: 0)
      stopControl
    }
  }

  /// Eight seconds of history, scrolling, with the line marking now.
  ///
  /// The window is rasterised into one image per redraw — ``SonogramBuffer/window(from:columns:)``
  /// fills it in a single pass — and stretched to the strip's width. Drawing 500 columns as 500
  /// rectangles would cost the same picture and thousands of draw calls.
  private var sonogramReading: some View {
    ZStack(alignment: .trailing) {
      if let image = stripImage() {
        Image(decorative: image, scale: 1, orientation: .up)
          .resizable()
          .interpolation(.medium)
      }

      // Now, hard against the right edge. Always drawn, because the window is always the
      // live one — there is no scrubbed state left in which it could point at a moment that
      // has already gone.
      //
      // **It belongs to this reading alone.** The waveform has no time axis, so a line
      // saying "this edge is the present" would be pointing at a frequency.
      theme.colors.gilt.frame(width: playheadWidth)
    }
  }

  /// What the microphone is hearing **this instant** — see ``LiveWaveform``.
  ///
  /// **Each curve is drawn as the region between itself and its own reflection**, which is what
  /// turns a sine into the chain of lenses this shape is recognised by: the wave pinches to a
  /// point wherever it crosses zero and opens to its full height between. Filling one shape per
  /// curve rather than stroking two lines also means there is no line weight to keep matched
  /// between two drawing APIs.
  ///
  /// The three are laid over each other in the app's own three inks, part-transparent, so where
  /// they overlap the colour builds — see ``waveColours``.
  ///
  /// A hairline down the middle underneath them all, always: an open microphone hearing nothing
  /// is still an open microphone, and a strip drawing literally nothing reads as one that has
  /// stopped.
  ///
  /// **`TimelineView(.animation)`, not the session's tick.** The screen's clock runs at thirty a
  /// second, which is right for a strip that scrolls four points at a time and plainly wrong for
  /// a wave that is meant to glide — at thirty the travel reads as a flip-book. This asks the
  /// system for every frame the display can show, so the motion is as smooth as the phone is, and
  /// it only runs while this reading is the one on screen.
  private var waveformReading: some View {
    TimelineView(.animation) { frame in
      // Read here rather than inside the renderer: this closure runs on the main actor, which
      // is where the buffer may be read from, and a `Canvas` renderer is not.
      let curves = LiveWaveform.curves(
        bins: sonogram.recentBins(columns: liveWaveformColumns),
        level: sonogram.recentLevel(columns: liveWaveformColumns),
        phase: frame.date.timeIntervalSinceReferenceDate
      )

      Canvas { context, size in
        let centre = size.height / 2
        // A little short of the strip's own edge: a wave that touched the top would read as
        // clipped rather than as loud.
        let reach = centre - waveformInset

        context.fill(
          Path(
            CGRect(
              x: 0,
              y: centre - waveformHairline / 2,
              width: size.width,
              height: waveformHairline
            )
          ),
          with: .color(waveHairlineColour)
        )

        for (index, curve) in curves.enumerated() where curve.count > 1 {
          let step = size.width / CGFloat(curve.count - 1)

          var path = Path()
          for (i, height) in curve.enumerated() {
            let point = CGPoint(x: CGFloat(i) * step, y: centre - CGFloat(height) * reach)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
          }
          // Back along the reflection, so the curve closes into its own lens chain.
          for (i, height) in curve.enumerated().reversed() {
            path.addLine(
              to: CGPoint(x: CGFloat(i) * step, y: centre + CGFloat(height) * reach)
            )
          }
          path.closeSubpath()

          context.fill(path, with: .color(waveColours[index]))
        }
      }
    }
  }

  /// The three curves' inks, outermost first — **the cabinet's own colours, not the instrument's
  /// ramp**.
  ///
  /// The sonogram is magma because it is a *reading*, and magma is the map the reference strip on
  /// a bird's page is rendered in; a live column and a printed one have to be comparable. The wave
  /// is an indicator, and an indicator is the app talking. Drawing it in the app's inks is what
  /// says which of the two you are looking at, before reading the switch.
  ///
  /// **Blue, green, gold — low band to high, cool to warm.** The three curves carry the bottom,
  /// middle and top thirds of the spectrum (see ``LiveWaveform``), and running the inks up the
  /// same way the pitch runs means the picture says which third of the room is loud without
  /// anybody being told the mapping: a voice lifts the blue, a bird lifts the gold. Gilt lands on
  /// the high band, which is both the brightest ink here and the band a bird sings in.
  ///
  /// Cream used to hold the high band, and it went because a near-white curve was legible as
  /// *bright* rather than as a colour — at three overlapping shapes it bleached the two under it
  /// wherever they crossed. ``smalt`` is the one pigment of the three the cabinet does not
  /// otherwise stock, and lives in this file for that reason.
  ///
  /// **Vermilion is deliberately not among them** — it is the ink of *this ends something*, spent
  /// on exactly two controls, and one of those is the stop pill sitting on this very strip. A red
  /// wave beside a red stop is two reds meaning two different things a hand's width apart.
  ///
  /// Part-transparent so the overlaps build a fourth colour rather than the last one drawn simply
  /// winning — that layering is most of what the shape is. One alpha across all three now that
  /// none of them is near-white: the pigments are of a weight, so the picture has no accidental
  /// hierarchy beyond the one the bands themselves put there.
  private var waveColours: [Color] {
    [
      smalt.opacity(0.72),
      theme.colors.verdigris.opacity(0.72),
      theme.colors.gilt.opacity(0.72),
    ]
  }

  /// The zero line's ink: the quietest the palette has, because it is saying nothing.
  private var waveHairlineColour: Color { theme.colors.textFaint.opacity(0.5) }

  /// The stop, at the foot of the instrument it stops.
  ///
  /// **It used to sit at the head of the screen, and it is here because that is where the
  /// recording is.** In the header it was a red disc opposite the source switch — two unrelated
  /// controls sharing a bar, one of which ends the session. Down here it is on the one thing on
  /// the screen that is visibly running, which is what it is the control for; the header is left
  /// to say whose ears these are and nothing else.
  ///
  /// **The trailing corner, not the centre.** Centred it sat under the middle of the instrument,
  /// which is the part of the strip a watcher is actually reading, and it put the control that
  /// ends a recording where a thumb passes on its way to everything else. In the corner it is
  /// still the largest, reddest thing on the strip's foot — findable in a hurry — and it is
  /// nowhere the eye needs while the session is running. See ``stripControls``.
  ///
  /// **The inset around the drawing is the tap target, and it is doing both jobs.** A capsule of
  /// plate type is about twenty points tall, which is a small thing to hit for the one control
  /// that ends a recording — so the button is a `related` larger than the pill on every side. That
  /// same inset is what holds the pill clear of the strip's foot, which is why there is no second
  /// padding under it: one value, one gap, no arithmetic between two numbers nobody wrote down.
  private var stopControl: some View {
    Button(action: onStop) {
      StopControl()
        .padding(theme.space.related)
        .contentShape(.rect)
    }
    .accessibilityLabel("End session")
  }

  /// The visible columns, coloured and packed into an image.
  ///
  /// Coloured from ``SonogramPalette`` rather than from the theme, so the live strip and the
  /// reference strip on a bird's page are the same instrument — see the palette's note. The
  /// waveform is filled off the identical ramp for the identical reason, one step further in:
  /// the two readings are the same instrument as each other.
  private func stripImage() -> CGImage? {
    let columns = Int(timelineWindowSeconds * sonogramColumnsPerSecond)
    guard columns > 0 else { return nil }

    // Floored, not truncated: a window that has scrolled off the beginning has a negative
    // start, and truncation rounds those towards zero — a one-column stutter as the session's
    // opening seconds cross the left edge.
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

  /// The ramp, built once. It no longer depends on anything that can change at runtime, so
  /// rebuilding it per redraw would be 256 interpolations to reach the same 256 answers.
  private static let ramp = SonogramPalette.ramp()

  /// Which reading the strip is drawn as — **both sides always shown**, in the corner of the
  /// instrument they belong to.
  ///
  /// The same argument the source switch makes, at a quieter volume: a control that showed only
  /// the reading you are already looking at is a control nobody knows they can press, and this
  /// one has no other clue anywhere on the screen. Two words in a track says there is a choice
  /// here, and which way it is set, without anybody touching it.
  ///
  /// **Not gilt.** Gilt is what the app answers in — a named bird, a source that is live — and
  /// choosing how to draw a picture is not the app answering anything. The lit side takes the
  /// ordinary ink on a raised lacquer track; the unlit side is faint. Bottom-left, opposite the
  /// stop — the quieter of the strip's two controls, at the end a hand is not resting on, and
  /// where nothing a watcher is reading passes underneath.
  private var readingSwitch: some View {
    HStack(spacing: 0) {
      ForEach(StripReading.allCases, id: \.self) { option in
        let isSelected = option == reading
        PlateLabel(
          text: option.plate,
          color: isSelected ? theme.colors.textPrimary : theme.colors.textFaint
        )
        .padding(.horizontal, theme.space.snug)
        .padding(.vertical, theme.space.tight)
        .background(isSelected ? theme.colors.lacquerHigh : .clear, in: .capsule)
        .contentShape(.capsule)
        // Pressing the lit side is deliberately inert, exactly as it is on the source
        // switch: there is nothing on this side of the choice left to choose.
        .onTapGesture { if !isSelected { onReadingChange(option) } }
        .allowsHitTesting(!isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(option.label)
      }
    }
    // The track the two sides sit in, at the switch's own hairline inset — see `SourceSwitch`.
    .padding(switchTrackInset)
    .background(theme.colors.ink.opacity(readingTrackOpacity), in: .capsule)
    .animation(.easeInOut(duration: readingThrow), value: reading)
    .padding(theme.space.related)
  }
}

/// Everything that has happened this session, newest first.
///
/// **Newest first, rather than a feed that grows downwards.** A log that appended at the bottom
/// would have to be scrolled to on every arrival to be read at all. This way the new row appears
/// directly under the strip that caused it — where the eye already is.
///
/// Rows are keyed by their moment, which is what stops an arrival at the top renumbering every row
/// under it and rebuilding the lot.
///
/// **And the list returns to the top when one lands.** A list left to itself keeps the offset it
/// had, so an arrival *above* what is on screen pushes the rows down and the one event worth seeing
/// is the one event not visible. Holding position is the right behaviour for a list someone is
/// reading and the wrong one for a list that is reporting — this is reporting, and the newest row is
/// the whole point of it.
///
/// A user's own drag outranks this: a finger on the list takes the scroll and the animation gives
/// way rather than fighting it, so a watcher deliberately reading back through the session keeps
/// their place until they let go.
///
/// **It runs to the bottom of the phone, under the shutter, and fades out on the way.** A list that
/// stopped short of the control would be spending an inch of a small screen on saying "the rows end
/// here" about a list that does not end — and a hard edge there reads as a bug, as though something
/// clipped it. Instead the rows keep going and dim into the ground across the band the shutter
/// sits in, which says *there is more, and it is going under this*.
///
/// **The head of the list fades too, but only once there is something above it.** The strip's
/// bottom edge is hard — it is an instrument, and instruments have edges — so a row sliding up to
/// meet it collides with it rather than passing under it. A fade there says the rows continue
/// behind the strip, which is exactly what has happened. At rest it is *absent*, not merely faint:
/// a list already at its top has nothing hidden above the first row, and dimming it would be the
/// screen implying there is more to see in a direction there is nothing in. It arrives over the
/// first ``logHeadroom`` of scroll, which is the same distance the fade itself is tall.
///
/// The fade is a mask rather than a gradient laid on top, because a gradient would have to be the
/// colour of the ground, and the ground is the ground's business.
struct SessionLog: View {
  @Environment(\.theme) private var theme

  let session: RealtimeSession

  /// What stands in for the rows before there are any.
  let emptyLabel: String

  /// The shutter's band at the foot of the screen. Twice over: the last row can be scrolled up
  /// clear of it, and the fade is exactly this tall — so a row is dimming precisely while it is
  /// passing behind the control, rather than at some other height that happens to look right.
  let footroom: CGFloat

  /// Whether a reachable pair has a panel to draw on — what makes a bird on the log pressable.

  /// Puts a bird already on the log back on the display — see
  /// ``RealtimeViewModel/showCard(_:)``.
  let onShowCard: (String) -> Void

  /// How far the list has been dragged from its top, in points. Drives the head's fade, and
  /// nothing else — see ``headFade``.
  @State private var scrolled: CGFloat = 0

  /// How much of the head's fade is showing, 0 at the top of the list and 1 once a headroom's
  /// worth of rows has gone under the strip.
  private var headFade: CGFloat { min(max(scrolled / logHeadroom, 0), 1) }

  /// The photograph being looked at full screen, or `nil` — see ``PhotoLightbox``.
  ///
  /// **The session does not pause behind it.** The microphone is the screen's, not this list's,
  /// and a watcher who opened a photograph has not stopped birding — the strip keeps scrolling
  /// and rows keep landing underneath. What the cover does take away is the stop control, which
  /// is the right trade: ending a recording is not something to do by accident through a
  /// photograph.
  @State private var openPhoto: OpenPhoto?
  @Namespace private var photoNamespace

  /// The row the list is pinned to. Written by ``ScrollView``'s own position binding and read back
  /// by nothing — setting it is how an arrival is brought into view.
  ///
  /// `scrollPosition` rather than a `ScrollViewReader`: the reader needs a proxy threaded down
  /// through the view that owns the rows, and this says the same thing as a value the list is
  /// bound to.
  @State private var pinnedTo: Double?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: theme.space.related) {
        ForEach(session.events.reversed(), id: \.at) { event in
          LogRow(
            event: event,
            photoNamespace: photoNamespace,
            onOpenPhoto: { openPhoto = $0 },
            onShowCard: onShowCard
          )
        }
      }
      // On the stack itself, before anything wraps it: this is what marks the rows as the
      // things `scrollPosition` addresses, and it is the stack that has them.
      .scrollTargetLayout()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.separate)
      .padding(.bottom, footroom)
    }
    .fullScreenCover(item: $openPhoto) { photo in
      PhotoLightbox(source: photo.source, caption: photo.caption) { openPhoto = nil }
        .navigationTransition(.zoom(sourceID: photo.id, in: photoNamespace))
        // This screen runs dark, so the margin the zoom opens behind it should too — see
        // ``PhotoLightbox`` for why the asking belongs here and not around the flow.
        .preferredColorScheme(.dark)
    }
    .scrollPosition(id: $pinnedTo, anchor: .top)
    // Back to the newest row whenever one lands — see the note above for why a keyed list needs
    // telling. On the count rather than on the list, so it fires once per arrival and not again
    // on every redraw the session's other state causes.
    .onChange(of: session.events.count) {
      guard let newest = session.events.last else { return }
      withAnimation { pinnedTo = newest.at }
    }
    .scrollIndicators(.hidden)
    // Scroll geometry rather than a `PreferenceKey`, the way `BirdDetailScreen` reads its bar:
    // the offset never enters the preference system, so it cannot propagate up and rebuild
    // whatever emitted it. `contentInsets.top` is what makes a list at rest read exactly zero
    // rather than the list's own top padding.
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top
    } action: { _, offset in
      scrolled = offset
    }
    .mask {
      VStack(spacing: 0) {
        // Opaque at both ends when nothing is hidden above, so this band costs the head of
        // the list nothing until it has something to say.
        LinearGradient(
          colors: [.black.opacity(1 - headFade), .black],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: logHeadroom)

        Color.black

        LinearGradient(
          colors: [.black, .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: footroom)
      }
    }
    // Not "no results": a session that has heard nothing yet is a session doing exactly what it
    // said it would, and it says which of the two that is — still opening the microphone, or
    // listening through one that is open.
    .overlay(alignment: .top) {
      if session.events.isEmpty {
        PlateLabel(text: emptyLabel, color: theme.colors.textFaint)
          .padding(.top, theme.space.section)
      }
    }
  }
}

/// One thing that happened, and the second of the session it happened at.
///
/// The stamp is a column of its own so the times line up down the page — a log read by running an
/// eye down the left edge, which is what the marks' x-positions used to be for.
///
/// Inputs and answers are told apart by ink rather than by side: a bird is the app talking, in
/// gilt; a photo or a phrase is the watcher, in the quieter hand. That was the strip's two lanes,
/// and it survives the move down here intact.
///
/// A right-hand gutter closes the row, holding the device mark a photograph wears — see
/// ``sourceMark``. It is held open on every row, so the marks read down the page as a column.
///
/// **A row that named a bird takes a tap, and puts its card back up** — see ``namedBird``. Where
/// that card lands is not this row's business: on the glasses if the wearer has glass, and on the
/// phone if not, which is why the tap is here for every run rather than only the best-equipped
/// one. It wears no mark for it, deliberately: the gilt already says this row is the app's own
/// answer, and a badge repeating *this one is pressable* on every second row would be a column of
/// ink saying what the ink beside it says.
private struct LogRow: View {
  @Environment(\.theme) private var theme

  let event: SessionEvent
  let photoNamespace: Namespace.ID
  let onOpenPhoto: (OpenPhoto) -> Void
  let onShowCard: (String) -> Void

  /// The bird this row named, or `nil` for a row that named none — what decides whether it can
  /// be sent back to the display.
  ///
  /// **The three cases are exactly the three that put a card up in the first place** (see
  /// ``RealtimeViewModel/showCard(_:)``): a detection, a photograph the script identified,
  /// and an answer with a species behind it. A row that can be re-shown is a row that was shown,
  /// which is the rule that keeps this from needing a list of its own to stay in step with.
  ///
  /// A photograph still crossing is deliberately included when its answer has landed — the
  /// picture and the card are separate arrivals, and the card is the one being asked for.
  ///
  /// Everything else answers `nil`: a phrase the watcher said, an ambiguity the app would not
  /// commit to, a caption where there is no bird. The display never took those, so there is
  /// nothing to put back.
  private var namedBird: String? {
    switch event {
    case let .bird(_, speciesId, _, _): speciesId
    case let .answer(_, _, _, speciesId, _): speciesId
    case let .photo(_, _, _, _, _, _, identification):
      if case let .bird(speciesId, _, _) = identification { speciesId } else { nil }
    case .speech: nil
    }
  }

  /// This row's send, where it has one to make. The whole row is the target rather than the
  /// plate inside it, because the plate is a word and a word is a poor thing to hit — and
  /// because the stamp beside it belongs to the same event. The photograph keeps its own tap: a
  /// child that handles the press stops it here, so a thumbnail still opens full frame and the
  /// caption beside it still sends.
  private var sendable: String? { namedBird }

  /// This row's photograph, where it has one that has actually arrived. A capture still crossing
  /// from the glasses has a row and no picture yet, and there is nothing to open until it lands.
  private var openablePhoto: OpenPhoto? {
    guard case let .photo(at, _, image, _, _, _, identification) = event,
      let image
    else { return nil }
    var caption: String?
    switch identification {
    case let .bird(_, commonName, _): caption = commonName
    case let .words(text): caption = text
    default: caption = nil
    }
    return OpenPhoto(id: String(at), source: .image(image), caption: caption)
  }

  var body: some View {
    HStack(alignment: .center, spacing: theme.space.related) {
      Text(sessionStamp(event.at))
        .font(theme.type.data)
        .foregroundStyle(theme.colors.textFaint)
        .frame(width: stampWidth, alignment: .leading)

      switch event {
      case let .photo(_, _, image, _, _, _, identification):
        HStack(spacing: theme.space.related) {
          if let image {
            Image(decorative: image, scale: 1, orientation: .up)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: logPhotoSize, height: logPhotoSize)
              .clipShape(.rect(cornerRadius: theme.space.tight))
              .matchedTransitionSource(id: String(event.at), in: photoNamespace)
              .onTapGesture { if let photo = openablePhoto { onOpenPhoto(photo) } }
              .accessibilityAddTraits(.isButton)
              .accessibilityHint("View this photo")
          } else {
            // The picture's own space, held open at exactly the size it will fill,
            // so the arrival is the tile filling rather than the row growing and
            // shoving the log about under a thumb.
            RoundedRectangle(cornerRadius: theme.space.tight)
              .fill(theme.colors.rule)
              .frame(width: logPhotoSize, height: logPhotoSize)
          }
          photoAnswer(identification, isCrossing: image == nil)
        }

      case let .speech(_, text):
        Text(text)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)

      case let .bird(_, _, commonName, confidence):
        HStack(spacing: theme.space.snug) {
          PlateLabel(text: commonName, color: theme.colors.gilt)
          PlateLabel(
            text: "\(Int((confidence * 100).rounded()))%",
            color: theme.colors.textSecondary
          )
        }

      // The app talking in words — same gilt ink as a named bird, set as a sentence
      // rather than a plate because an answer is read, not scanned. A bird the script
      // linked wears the plate a named bird wears, with no confidence: the watcher
      // described it, and the app agreed.
      //
      // **The plate sits above the sentence rather than beside it.** Beside it, the two
      // shared the row's width, so a sentence of any length wrapped into a narrow column
      // with a name stranded out to the right of it — a paragraph and a label, laid out as
      // though they were two columns of a table. Stacked, the name lands where every other
      // row's name lands and the sentence gets the full width to be read across, which is
      // the shape both of them wanted: the plate is scanned down a column, the words are
      // read along one.
      case let .answer(_, text, _, _, commonName):
        VStack(alignment: .leading, spacing: theme.space.tight) {
          if let commonName {
            PlateLabel(text: commonName, color: theme.colors.gilt)
          }
          Text(text)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.gilt)
        }
      }

      // **One spacer, not four greedy branches.** Each case used to claim the width for
      // itself, which was harmless while nothing followed it and wrong the moment something
      // did: two children that both take everything offered split the row between them, and
      // a long phrase would wrap at half the width it actually has. The row is left-aligned
      // here, once, and the branches go back to asking for the width they need.
      //
      // `minLength: 0` because the gap either side is the stack's own `related` — a spacer
      // with a minimum of its own would add a third number to a distance that already has
      // two, which is exactly the sum nobody can find later.
      Spacer(minLength: 0)

      sourceMark
    }
    // On the whole row, and `contentShape` is what makes that true: a stack is only hit where
    // its children are drawn, so without it the gaps between the stamp, the plate and the
    // gutter would all be misses on a row that looks like one target.
    .contentShape(.rect)
    .onTapGesture { if let sendable { onShowCard(sendable) } }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(sendable != nil ? .isButton : [])
    .accessibilityHint(sendable != nil ? "Show this bird's card" : "")
  }

  /// Which device took this, for the rows that were taken by a device at all.
  ///
  /// Read off the event rather than bound in the switch above, so the mark can sit outside it —
  /// the branch draws what happened, the gutter says where it came from, and neither has to
  /// know about the other.
  private var source: CaptureSource? {
    if case let .photo(_, _, _, source, _, _, _) = event { source } else { nil }
  }

  /// The device that took the photograph, in the row's right-hand gutter.
  ///
  /// **The source pill cannot answer this.** A session's photographs do not all come from one
  /// place: the shutter routes per press, on whether the glasses can take one *at that moment*
  /// (see ``RealtimeViewModel/capturePhoto()``), so a session that loses or gains the glasses
  /// halfway holds both kinds. The pill reports what the session is riding *now* — it says
  /// nothing about the capture three minutes up the log, and this mark is the only place that
  /// fact survives.
  ///
  /// **It is drawn from the press, not from the arrival**, which is why the crossing needs no
  /// words of its own: a glasses photograph is marked as one for the whole second it is still
  /// in the air, so the dots beside the empty tile only have to say *still coming*. A sentence
  /// there would be text that dies before it is read and is replaced twice over — see
  /// ``photoAnswer(_:isCrossing:)``.
  ///
  /// Both devices are marked, deliberately. Marking only the glasses would leave an unmarked row
  /// ambiguous between *the phone took it* and *we forgot to say*.
  ///
  /// The width is held whether or not there is a mark, so the gutter is a column rather than a
  /// ragged edge, and so a row does not reflow the moment a photograph resolves.
  private var sourceMark: some View {
    Group {
      if let source {
        Image(glyph: source == .glasses ? theme.glyphs.glasses : theme.glyphs.device)
          .resizable()
          .frame(width: logSourceGlyphSize, height: logSourceGlyphSize)
          .foregroundStyle(theme.colors.textFaint)
          .accessibilityLabel(
            source == .glasses ? "Taken by the glasses" : "Taken by the phone"
          )
      }
    }
    .frame(width: logSourceGlyphSize)
  }

  /// What the app made of a photo, **on the photo's own row** — the space to the right of the
  /// thumbnail, which the answer grows into when it arrives.
  ///
  /// **This is the whole reason a photo's answer moved onto its event.** The scripted response
  /// used to land as a separate row a second or two below, which is a bird with no visible
  /// relation to the picture that produced it — and by the time it appeared the log had already
  /// put another row between them. Here nothing moves and nothing is inserted: the thumbnail
  /// lands, the dots run in the space beside it, and the name replaces them in place. One row,
  /// one thing that happened.
  ///
  /// The five states are the five things that can be true of a capture, and each has its own
  /// drawing:
  ///
  /// - **still crossing** — ``WorkingDots`` in the watcher's quieter ink, beside the empty tile
  ///   the picture will fill. Three things tell this wait from the one below it, and the ink is
  ///   the weakest of them: the tile is empty where the other has a picture in it, the gutter
  ///   already wears the glasses mark (see ``sourceMark``), and the dots are in the watcher's
  ///   own hand because this is their capture arriving — gilt is reserved for the app talking,
  ///   and nothing is being composed yet. **Deliberately wordless**: the row is on screen for
  ///   about a second before the dots are replaced by gilt dots and then by a name, and a
  ///   sentence in that slot is text that dies before it can be read;
  /// - **nothing coming** — `PHOTO`, the plate the row has always worn, in the watcher's quieter
  ///   ink;
  /// - **waiting** — ``WorkingDots``, in gilt, because what is composing is the app's answer;
  /// - **a bird** — the same gilt name-and-confidence pair a heard detection wears in the row
  ///   below, deliberately identical: a bird is a bird however it was reached;
  /// - **words** — an ambiguity or a decline, set as a sentence rather than a plate, because an
  ///   answer is read.
  @ViewBuilder
  private func photoAnswer(
    _ identification: PhotoIdentification?,
    isCrossing: Bool
  ) -> some View {
    if isCrossing {
      WorkingDots(color: theme.colors.textFaint)
        .accessibilityHidden(false)
        .accessibilityLabel("Receiving this photo from the glasses")
    } else {
      settledAnswer(identification)
    }
  }

  @ViewBuilder
  private func settledAnswer(_ identification: PhotoIdentification?) -> some View {
    switch identification {
    case .none:
      PlateLabel(text: "Photo", color: theme.colors.textSecondary)

    case .pending:
      WorkingDots(color: theme.colors.gilt)
        .accessibilityHidden(false)
        .accessibilityLabel("Identifying this photo")

    case let .bird(_, commonName, confidence):
      HStack(spacing: theme.space.snug) {
        PlateLabel(text: commonName, color: theme.colors.gilt)
        PlateLabel(
          text: "\(Int((confidence * 100).rounded()))%",
          color: theme.colors.textSecondary
        )
      }

    case let .words(text):
      Text(text)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.gilt)
    }
  }
}

/// Tall enough that 128 bins are more than a smear, short enough to leave the log room.
private let stripHeight: CGFloat = 132

/// The air between the reading switch's track and the side sitting in it. The same hairline the
/// source switch uses, and for the same reason — at `tight` the track reads as a second, larger
/// pill around the first.
private let switchTrackInset: CGFloat = 2

/// How dark the reading switch's track is. A step under the stop's capsule, because this is a
/// setting on the instrument rather than a way out of it: it should be findable, not noticed.
private let readingTrackOpacity: Double = 0.45

/// How long the reading switch takes to throw. Short — the picture has already changed, and this is
/// only the ink catching up.
private let readingThrow: Double = 0.18

/// The playhead. A hairline would disappear against a bright column.
private let playheadWidth: CGFloat = 2

/// The band the log's head fades across, and the distance of scroll that brings it in.
///
/// `space.section`'s 32, written out because a top-level constant has no theme to read — deep
/// enough that a row is dimming for a moment rather than winking out, and shallow enough that the
/// row under it is still a row you can read. The foot's fade is measured the same way, off the
/// shutter's band rather than off the scale, for the same reason: a fade should be as tall as
/// whatever it is fading behind.
private let logHeadroom: CGFloat = 32

/// Room for `12:00` in the stamp column, so the log's second column starts in the same place all
/// the way down however long the session runs.
private let stampWidth: CGFloat = 44

/// A photo in the log. Big enough to recognise the bird in it, small enough that a row is a row.
private let logPhotoSize: CGFloat = 44

/// The device mark in a row's gutter — smaller than the source pill's 16, because the pill is the
/// session announcing what it is riding and this is a footnote on one row.
private let logSourceGlyphSize: CGFloat = 14

/// Magma's darkest end, as a `Color` — what the strip shows where nothing has been heard.
private let stripGround: Color = magma(0)

/// The wave's third pigment: **smalt**, the cabinet's blue, and the one ink in this app that lives
/// in a screen rather than in the palette.
///
/// It is here rather than on ``BirdSpotterColors`` on purpose. The palette is a small set of inks
/// that each mean something everywhere they appear — gilt is the app answering, verdigris is the app
/// asking you to act, vermilion is *this ends something* — and a fourth pigment added for one
/// drawing would be a colour with no such job, waiting to be reached for by the next screen that
/// wanted a blue. This has exactly one use: the low band of the live waveform, on a strip that only
/// ever renders in the dark palette, which is why one value serves and there is no light twin.
///
/// Chosen against ``BirdSpotterColors/verdigris`` rather than in the abstract — the same muted,
/// mid-luminance register, far enough round the wheel that the two curves are plainly two colours
/// where they cross and not a green that has gone slightly cold.
private let smalt = Color(hex: 0x6E86B4)

/// How many of the newest columns the live waves take their heights from — see
/// ``SonogramBuffer/recentBins(columns:)``.
///
/// Eight at 62.5 columns a second is about an eighth of a second. **This is the one number that
/// decides whether the picture is smooth**: the sine and the envelope have no jitter in them, so
/// everything that can move suddenly moves through here. Four was visibly twitchy; much beyond
/// eight and a call has finished before the wave finishes rising to it.
private let liveWaveformColumns = 8

/// How far the waves stay clear of the strip's top and bottom edges. A loud moment should read as
/// loud, not as clipped, and the only way to see the difference is to leave somewhere to clip to.
private let waveformInset: CGFloat = 10

/// The line down the middle, under everything — the instrument's own zero.
private let waveformHairline: CGFloat = 1.5

/// One step of the magma ramp, as a `Color`.
private func magma(_ step: Int) -> Color {
  let colour = SonogramPalette.ramp()[step]
  return Color(
    .sRGB,
    red: Double(colour.red) / 255,
    green: Double(colour.green) / 255,
    blue: Double(colour.blue) / 255
  )
}
