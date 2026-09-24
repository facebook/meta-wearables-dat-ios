/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  RealtimeScreen.swift
//  birdspotter
//

import SwiftUI

/// Real-time identification — **a listening session**, presented full screen.
///
/// The microphone runs from the moment the cover rises to the moment it falls, and everything else
/// lands on a timeline at the second it happened: a photo the watcher took, a phrase they said, a
/// bird the app thinks it heard. The camera is a **mode inside the session**, not the way into it —
/// opening it does not stop the session listening, and the shutter drops its photo onto the
/// timeline and comes straight back.
///
/// Why not camera-first: two of the three identification paths in the spec need no camera at
/// all, and a viewfinder has nowhere to put *when* something happened. The reasoning, and the
/// format the strip is drawn from, are.
///
/// The cover comes up from the bottom over the whole shell, tab bar included, which is why
/// `IdentifyScreen` raises it as a `.fullScreenCover` rather than pushing a `Route`. The stop sits
/// at the foot of the strip — on the instrument it stops — and ends the recording onto the review;
/// the review's Save and Discard are what finally dismiss.
///
/// The whole cover runs in the **dark palette**, whatever the phone is set to — a sonogram is a
/// light-on-dark instrument in both, and forcing the theme here lets every control below go on
/// reading `textPrimary` and `gilt` as usual.
struct RealtimeScreen: View {
  @Environment(\.dismiss) private var dismiss

  /// The session, which is the app's rather than this cover's: built once in the composition
  /// root and handed in, so a run started by a voice launch before the cover rose is the run
  /// the cover shows, and one still going when the cover falls goes on going.
  let model: RealtimeViewModel

  /// Where the camera control sits, in ``sessionSpace``. The panel's closed geometry — it starts
  /// and ends its life as exactly this rectangle, which is what makes the two one object.
  @State private var cameraControlFrame: CGRect = .zero

  /// The zoom a pinch started from. `MagnifyGesture` reports magnification relative to the start
  /// of the gesture, so this is what it is relative *to* — see ``magnify``.
  @State private var zoomAnchor: Double = 1

  /// How the strip is drawn, and where that survives. Seeded from the store on the way in and
  /// written back on the tap: the choice is about how somebody likes to read an instrument, not
  /// about this session, so it outlives the cover.
  ///
  /// **State as well as store, rather than reading the store every redraw.** `UserDefaults` has
  /// no way to tell SwiftUI something changed, so a view that only read it would go on drawing
  /// the old reading until something else happened to invalidate it.
  @State private var stripReading: StripReading
  private let sessionSettings: SessionSettingsStore

  /// The dark tokens this screen draws in, resolved once rather than read from the environment —
  /// the environment carries whatever the phone is set to, which is the thing being overruled.
  private let theme = BirdSpotterTheme.resolve(for: .dark)

  init(model: RealtimeViewModel, sessionSettings: SessionSettingsStore = SessionSettingsStore()) {
    self.model = model
    self.sessionSettings = sessionSettings
    _stripReading = State(initialValue: sessionSettings.stripReading)
  }

  var body: some View {
    ZStack {
      theme.colors.paper
        .ignoresSafeArea()

      if let review = model.uiState.review {
        // The confirmation, in the session's place: same cover, second screen of the
        // flow. The strip and the camera are gone because the session is — what is
        // being looked at now is what it left behind.
        SessionReviewScreen(
          session: model.uiState.session,
          review: review,
          onToggleBird: { model.toggleBirdKept(at: $0) },
          onNotesChange: { model.setReviewNotes($0) },
          onSave: { model.saveOuting() },
          onDiscard: { dismiss() }
        )
        .transition(
          .opacity
            .combined(with: .offset(y: reviewRise))
            .animation(reviewArrival)
        )
      } else {
        Group {
          session

          // Over the session rather than instead of it: the strip keeps filling
          // behind this, and closing the camera reveals the seconds the session went
          // on recording.
          cameraMode
        }
        // The session goes on the shorter curve, and only fades: it is ending, and a
        // recording that slid off the screen would be claiming to have gone somewhere.
        .transition(.opacity.animation(reviewDeparture))
      }

      // The phone's own copy of the glasses card, for a log tap that had nowhere else to
      // put it — see ``BirdCardDialog``. Last in the stack rather than a layer inside the
      // session, so it sits over the camera panel and the review alike without either
      // having to know.
      if let bird = model.uiState.cardOnPhone {
        BirdCardDialog(bird: bird) { model.dismissCard() }
      }
    }
    // **The stop is two beats, not a cut.** The instrument settles, then what it left
    // behind comes up — the session dissolves where it stands, and the review rises the
    // last inch into its place as that finishes.
    //
    // Both halves at once is a cross-fade of two full screens, which reads as a glitch;
    // straight replacement is what made the stop feel like the app had skipped a frame.
    // The two curves are asymmetric for the reason ``cameraDismiss`` is: the session is
    // *ending* and has nothing to settle into, while the review is arriving and should
    // land. The value is what drives them — the stop can come from the control here or
    // from the view model, and neither should have to remember to wrap itself.
    .animation(reviewArrival, value: model.uiState.isReviewing)
    // The space the morph is measured in. The camera control reports its frame here and the
    // panel reads it back, which is the only way the panel can start life exactly where the
    // button is rather than merely near it.
    .coordinateSpace(.named(sessionSpace))
    // The cover rising is a run starting — unless one is already going, in which case this
    // is a no-op and the cover simply shows it. The run is the view model's own, so
    // neither the stop nor the cover falling is handled here: the stop cancels it, and
    // a cover that falls on a running session (it cannot today, but the ownership is what
    // makes that true rather than the chrome) leaves it running.
    .task { model.start() }
    // The camera's own life, inside the session's — cancelled when the mode closes, without
    // touching the microphone.
    .task(id: model.uiState.isCameraOpen) {
      if model.uiState.isCameraOpen {
        // Every open starts at 1×, and so does what the next pinch measures from.
        zoomAnchor = 1
        await model.observeCamera()
      }
    }
    // The cover falls once the journal has the outing — the "In your journal" beat on the
    // button is all the confirmation a successful save gets.
    .onChange(of: model.uiState.review?.savedOutingId) { _, saved in
      if saved != nil { dismiss() }
    }
    .environment(\.theme, theme)
  }

  /// The session itself: its header, its timeline, and the one control that opens the camera.
  ///
  /// The shutter is **over** the timeline rather than below it, and the log runs the full height
  /// of the screen underneath it — see ``SessionLog``. A control that took layout space would cut
  /// the log off a clean inch above the bottom of the phone, which is a screen's worth of rows
  /// spent saying "the list ends here" on a list that does not end.
  private var session: some View {
    ZStack(alignment: .bottom) {
      sessionBody
      controls
    }
  }

  private var sessionBody: some View {
    VStack(spacing: 0) {
      header

      // **The Director says nothing here, deliberately.** A caption naming the armed
      // preset — or saying none was — used to sit under the header, and it is the one
      // line on this screen that is about the demo rather than about the birds. What is
      // playing is read where it is chosen, on the Demo Director page.

      // One line about the source, under the pill that controls it — a missing camera
      // grant, a crossing that failed. Rare, quiet, and cleared the next time the
      // toggle is asked.
      if let notice = model.uiState.sourceNotice {
        Text(notice)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.horizontal, theme.space.gutter)
          .padding(.top, theme.space.snug)
      }

      Group {
        if model.uiState.status == .failed {
          failureNotice
        } else {
          // No gutter: the strip is the screen's one deliberate full-bleed element, so
          // its right edge and the right edge of the phone are the same edge, and that
          // edge is *now*.
          //
          // It sits directly under the header rather than centred in what is left: the
          // strip is the top of the timeline and the log runs down from it, so the
          // session reads top to bottom in one column.
          SessionTimeline(
            sonogram: model.sonogram,
            elapsed: model.elapsed,
            session: model.uiState.session,
            emptyLabel: model.uiState.emptyLogLabel,
            footroom: controlsHeight,
            onStop: { model.stopSession() },
            reading: stripReading,
            onReadingChange: { reading in
              stripReading = reading
              sessionSettings.stripReading = reading
            },
            onShowCard: { model.showCard($0) }
          )
        }
      }
      .frame(maxHeight: .infinity)
      // The air the bearing row used to stand in. It went to the foot of the screen — see
      // ``controls`` — and the instrument still wants clearing from the chrome above it, so
      // the gap stays and only the row that was in it left.
      .padding(.top, theme.space.section)
    }
  }

  /// The band the shutter occupies at the foot of the screen. The log leaves this much room
  /// below its last row and fades out across it — see ``SessionLog``.
  private var controlsHeight: CGFloat { shutterTargetSize + theme.space.gutter * 2 }

  /// Whose ears these are — **and nothing else**.
  ///
  /// **The stop used to sit opposite the source control here, and it went to the strip.** Two
  /// unrelated controls sharing a bar made a header that had to be read left to right before
  /// either could be used, and pinned the one that ends the session as far as a thumb can get
  /// from the session itself. With the stop on the instrument it stops — see
  /// ``SessionTimeline`` — the bar has exactly one thing on it, and a bar with one thing on it
  /// puts that thing in the middle.
  ///
  /// **No clock.** A running total of seconds is a number that changes sixty times a minute and
  /// answers nothing a watcher asked — where the time matters is against a particular thing that
  /// happened, and that is what the log's stamps are. The session's elapsed seconds are still the
  /// column count; nothing now prints them on their own.
  ///
  /// **No battery plate either.** The charge was the bar's only other occupant, hanging off the
  /// trailing edge — a reading about the glasses as far from the control naming them as the
  /// header allows. It is on that control now, beside the word it is about; see
  /// ``RealtimeUiState/glassesSourceLabel``.
  private var header: some View {
    ZStack {
      // The way out of a session that never opened. There is no strip to put a stop on when
      // the microphone was refused, and nothing is running for a stop to be honest about —
      // so this one state, and only this one, keeps a control in the bar, and it is a close
      // mark rather than a stop because putting the screen away is all it does.
      if model.uiState.status == .failed {
        Button {
          dismiss()
        } label: {
          Image(glyph: theme.glyphs.close)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: closeControlSize, height: closeControlSize)
            .contentShape(.rect)
        }
        .accessibilityLabel("Close")
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      sourceControl
        // **The switch is measured at the width it wants, not the width the bar has.**
        // Two words, two silhouettes and a set of dots is wider than a narrow phone's bar
        // at a large text size, and a control that is merely *given* the bar's width hands
        // the shortfall to whichever label is laid out last — which is how `LINKING` came
        // to be set as `LINKIN` over a lone `G` the moment the dots appeared beside it.
        // Sized to its content it keeps its shape and leans into the bar's own margins
        // instead, symmetrically, because it is centred.
        .fixedSize(horizontal: true, vertical: false)
    }
    // The bar keeps the height the 48-point control gave it, whether or not that control is
    // there — otherwise a session that fails is a session whose header grows on the way in.
    .frame(minHeight: closeControlSize)
    .padding(.horizontal, theme.space.snug)
  }

  /// The header's source control, in whichever of its two forms the session has a use for.
  ///
  /// **A choice should look like one before it is made — and only when there is one.** With no
  /// pair registered or none in reach there is exactly one device in the story, so the control is
  /// the label it always was: one pill, naming the phone. The moment a pair is reachable it
  /// becomes a two-sided chip with both devices on it, because an audience and a presenter can now
  /// both see that there is a switch here and which way it is thrown. A single pill that silently
  /// became tappable said neither.
  ///
  /// Which form is ``RealtimeUiState/canToggleSource``'s to answer, so the reading and the control
  /// stay one decision rather than two that can disagree.
  @ViewBuilder
  private var sourceControl: some View {
    if model.uiState.canToggleSource {
      sourceSwitch
    } else {
      sourcePill
    }
  }

  /// The source as a **two-sided chip**: the device in the hand on the left, the glasses on the
  /// right, one of them lit.
  ///
  /// **Both sides are always drawn, and that is the point.** The switch is the one control on this
  /// screen a presenter may have to explain from a stage — *watch, I'm moving this to the
  /// glasses* — and a control that only shows where it currently is makes them describe an option
  /// the audience cannot see. Drawn as a track with a lit side, the throw is legible from the back
  /// of a room before anything happens, and afterwards.
  ///
  /// **The lit side is the ink, not a moving thumb.** A sliding indicator is the usual answer and
  /// it is the wrong idiom in this cabinet: everything on this screen is printed — plates, washes,
  /// plain inks — and a piece of travelling chrome would be the first thing on it borrowed from a
  /// system control. The wash and the ink cross-fade instead, which is the same arithmetic on both
  /// platforms and therefore genuinely the same animation.
  ///
  /// The selection moves on the tap, ahead of the ears: see ``RealtimeUiState/isGlassesSelected``
  /// for why a switch that waited to move is a switch that gets pressed twice. What stays honest
  /// through the crossing is the *ink* — `Linking` runs its dots in the app's gilt, and a paused
  /// run drops out of gilt entirely, since a pause is not the session claiming anything.
  ///
  /// **Each side only takes a tap when it would change something.** Pressing the lit side does
  /// nothing at all rather than toggling: with a single pill there was no way to say *put it back
  /// on the phone* except by pressing the same thing again, and a control that hangs up a live
  /// glasses session on a stray second tap is a control nobody should have to be careful with.
  private var sourceSwitch: some View {
    let onGlasses = model.uiState.isGlassesSelected

    return HStack(spacing: 0) {
      sourceSegment(
        glyph: theme.glyphs.device,
        label: model.uiState.deviceSourceLabel,
        isSelected: !onGlasses,
        // Unlit but not idle: while the glasses are away this is the device actually
        // recording — see ``RealtimeUiState/isDeviceCarrying``.
        isCarrying: model.uiState.isDeviceCarrying,
        isWorking: false,
        isPaused: false,
        // Only live from the glasses side — pressing the lit side is deliberately inert.
        action: onGlasses ? { model.toggleSource() } : nil
      )
      sourceSegment(
        // The frames alone until the pair says it is on a face — see
        // ``RealtimeUiState/isGlassesWorn``. A pair that has not reported yet draws as
        // the resting pair, because *not known* and *not worn* look the same from here
        // and the quieter of the two is the honest one to guess.
        glyph: model.uiState.isGlassesWorn == true
          ? theme.glyphs.glassesWorn
          : theme.glyphs.glasses,
        label: model.uiState.glassesSourceLabel,
        isSelected: onGlasses,
        isCarrying: false,
        isWorking: model.uiState.sourceState == .linking,
        isPaused: model.uiState.sourceState == .glassesPaused,
        action: onGlasses ? nil : { model.toggleSource() }
      )
    }
    // The track the two sides sit in. Without it the unlit side is a word floating beside a
    // chip rather than the other half of one object.
    .padding(switchTrackInset)
    .background(theme.colors.lacquerRaised, in: .capsule)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      onGlasses
        ? "Session source: \(model.uiState.glassesSourceLabel). Tap the phone to bring it back."
        : "Session source: \(model.uiState.deviceSourceLabel). Tap the glasses to move it there."
    )
  }

  /// One side of the switch: a silhouette, its word, and — while it is reaching — its dots.
  private func sourceSegment(
    glyph: String,
    label: String,
    isSelected: Bool,
    isCarrying: Bool,
    isWorking: Bool,
    isPaused: Bool,
    action: (() -> Void)?
  ) -> some View {
    // Three inks, and the middle one is the whole point of `isCarrying`. Gilt is what the app
    // answers in, so a *live* side wears it. A paused run answers nothing. An unlit side is
    // usually making no claim at all — unless it is the one quietly doing the recording, which
    // is worth more than the faint ink and less than the gilt.
    let ink: Color =
      if isSelected && !isPaused {
        theme.colors.gilt
      } else if isSelected || isCarrying {
        theme.colors.textSecondary
      } else {
        theme.colors.textFaint
      }
    let wash: Color =
      if !isSelected {
        .clear
      } else if isPaused {
        theme.colors.lacquerHigh
      } else {
        theme.colors.giltWash
      }

    return HStack(spacing: theme.space.snug) {
      Image(glyph: glyph)
        .resizable()
        .frame(width: sourceGlyphSize, height: sourceGlyphSize)
        .foregroundStyle(ink)
      // One line, always: a plate on a shared row that breaks a word reads as a
      // rendering fault rather than as a wrapped label.
      PlateLabel(text: label, color: ink, lineLimit: 1)

      // Trailing, so the silhouette that opens the side does not shift as the link comes
      // and goes.
      if isWorking {
        WorkingDots(color: ink)
      }
    }
    .padding(.horizontal, theme.space.snug)
    .padding(.vertical, theme.space.tight)
    .background(wash, in: .capsule)
    .animation(.easeInOut(duration: switchThrow), value: isSelected)
    .animation(.easeInOut(duration: switchThrow), value: isPaused)
    .animation(.easeInOut(duration: switchThrow), value: isCarrying)
    .contentShape(.capsule)
    .onTapGesture { action?() }
    .allowsHitTesting(action != nil)
  }

  /// The source when there is nothing to switch to: **one device, said plainly.**
  ///
  /// **In gilt, and in a pill.** It is the one line of chrome on this screen that a presenter may
  /// have to point at from the stage — *these are the phone's ears* — and a grey plate among grey
  /// plates is not something an audience finds. Gilt on the gilt wash is the app's own chip, the
  /// same one a named bird wears in the log below; the source is the session's answer to a
  /// question too, so it is set in the ink the app answers in.
  ///
  /// **A glyph before the word, and it is the whole point of the redraw.** A pill that read
  /// `PHONE` from the third row of a room said nothing; a phone and a pair of glasses are two
  /// silhouettes anybody can tell apart at that distance, and the word is then confirmation
  /// rather than the only evidence. The two drawings come off ``BirdSpotterGlyphs`` like every
  /// other icon in the app.
  ///
  /// It takes no tap, and it is not drawn as though it might: with no pair in reach there is
  /// nothing on the other side of a switch, and a control that quietly became live the moment a
  /// pair walked into the room would be a control nobody knew they had. That is ``sourceSwitch``'s
  /// job, and the header changes shape when it applies.
  ///
  /// The glasses' states are still reachable here — a run that was live when the pair went out of
  /// reach keeps `canToggleSource` true, so in practice this draws the phone or a simulated feed —
  /// but the inks are the switch's, so the two forms never disagree about what a state looks like.
  private var sourcePill: some View {
    let state = model.uiState.sourceState
    // A paused run is the one state the pill does not answer in gilt: nothing is arriving, so
    // there is nothing for the app's answering ink to be claiming.
    let isPaused = state == .glassesPaused
    let ink = isPaused ? theme.colors.textSecondary : theme.colors.gilt
    let wash = isPaused ? theme.colors.lacquerHigh : theme.colors.giltWash
    // Which device the pill is about, which is not always the device it is *on*: the linking
    // beat wears the glasses it is reaching for.
    let isAboutGlasses = state != .onDevice && state != .simulated

    return HStack(spacing: theme.space.snug) {
      Image(glyph: isAboutGlasses ? theme.glyphs.glasses : theme.glyphs.device)
        .resizable()
        .frame(width: sourceGlyphSize, height: sourceGlyphSize)
        .foregroundStyle(ink)
      PlateLabel(text: model.uiState.sourceLabel, color: ink, lineLimit: 1)

      // The one state that is *doing* something. Trailing rather than leading, so the row's
      // left edge — the silhouette — does not shift as the link comes and goes.
      if state == .linking {
        WorkingDots(color: ink)
      }
    }
    .padding(.horizontal, theme.space.snug)
    .padding(.vertical, theme.space.tight)
    .background(wash, in: .capsule)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Session source: \(model.uiState.sourceLabel)")
  }

  /// Where the watcher is standing — the pin, and the dot that is the fix landing.
  ///
  /// It goes quiet rather than guessing: a pin still in the faint ink is a session that has not
  /// been answered yet, not an error worth a sentence.
  ///
  /// The dot belongs *here*, next to the thing that means where. Beside the source plate it was a
  /// second, vaguer claim about the session at large, which is why that copy of it went and this
  /// one did not.
  private var locationReading: some View {
    HStack(spacing: theme.space.snug) {
      Image(glyph: theme.glyphs.location)
        .foregroundStyle(
          model.uiState.isLocated ? theme.colors.textSecondary : theme.colors.textFaint
        )
      LocationDot(isLocated: model.uiState.isLocated)
    }
    .accessibilityElement()
    .accessibilityLabel(model.uiState.isLocated ? "Location found" : "Finding location")
  }

  /// Which way the watcher is facing, as one of eight points.
  ///
  /// Quiet in the same way the pin is: a compass with no letters is a phone that cannot answer,
  /// and saying so in faint ink is the whole message.
  private var bearingReading: some View {
    HStack(spacing: theme.space.snug) {
      Image(glyph: theme.glyphs.compass)
        .foregroundStyle(
          model.uiState.headingPoint == nil
            ? theme.colors.textFaint
            : theme.colors.textSecondary
        )
      // Reserved whether or not there is a bearing, so nothing jumps the first time the
      // compass speaks.
      PlateLabel(
        text: model.uiState.headingPoint ?? "",
        color: theme.colors.textSecondary
      )
      .frame(minWidth: bearingPlateWidth, alignment: .leading)
    }
    .accessibilityElement()
    .accessibilityLabel(model.uiState.headingPoint.map { "Facing \($0)" } ?? "No compass")
  }

  /// The standing spot: where the watcher is, and which way they are turned.
  ///
  /// **One sentence, so one group.** *Here, facing north-east* is a single fact about where the
  /// watcher is planted, and the two halves of it read as one only when they are side by side.
  /// Split across the shutter they were two unrelated instruments that happened to share a row.
  private var standingReading: some View {
    HStack(spacing: theme.space.related) {
      locationReading
      bearingReading
    }
  }

  /// How high the watcher is looking, as one of five strata.
  ///
  /// **The other question the foot answers, and the reason it gets its own end of the row.** The
  /// pin and the compass are about a standing spot and are true while the watcher stands still;
  /// this changes the moment they raise their head, and it is the one reading on the screen a
  /// presenter can demonstrate by looking up.
  ///
  /// A word, not an angle: `Canopy` is where a bird would be, where `+37°` is a fact about a
  /// sensor. See ``gazeBand(_:)``.
  ///
  /// Quiet in the same way the compass is — a mark in faint ink and no word — rather than absent
  /// the way the chip over the viewfinder is. It has a neighbour across the row to stay level
  /// with now, and a foot that loses a whole side while the sensors settle is a foot that moves.
  private var elevationReading: some View {
    // The journal's formatter, not a local one: the foot and the saved entry name a stratum the
    // same way or they are two vocabularies for one reading.
    //
    // Called straight rather than through `map`, which would hand the formatter to a closure
    // that does not inherit this view's isolation and warn for it.
    let label: String? =
      if let band = model.uiState.elevationBand { JournalFormatting.gazeLabel(band) } else { nil }
    // The mark trails the word here, where the pin and the compass lead theirs. Both readings
    // put their mark on the row's outer edge, which is the edge that holds still: this half is
    // trailing-aligned, so a mark on the inside would slide by the width of the word every time
    // the stratum changed — `Sky` and `Understory` would draw the eye in two different places.
    return HStack(spacing: theme.space.snug) {
      PlateLabel(text: label ?? "", color: theme.colors.textSecondary, lineLimit: 1)
      Image(glyph: theme.glyphs.gaze)
        .foregroundStyle(
          label == nil ? theme.colors.textFaint : theme.colors.textSecondary
        )
    }
    .accessibilityElement()
    .accessibilityLabel(label.map { "Aimed at the \($0)" } ?? "No tilt reading")
  }

  /// The session's foot: the shutter, centred, with **where the watcher is standing** on one side
  /// of it and **where they are looking** on the other.
  ///
  /// The shutter is centred and unlabelled, at the size it will be once the panel has grown — it
  /// is the thing a thumb goes looking for without aiming, and a word beside it only says what the
  /// shape already does. Drawn here at exactly the panel's own shutter size, so the control the
  /// watcher presses and the control they press next are the same drawing at the same scale.
  ///
  /// **The readings used to be a row under the header, and this is a better place for them.** They
  /// are chrome about the standing spot, not part of the instrument, and up there they pushed the
  /// strip a section's worth down the screen to say so. Down here they flank the one control the
  /// screen has, in the band the log already leaves clear — at no cost in timeline. The gap they
  /// vacated stays where it was, because the strip still wants clearing from the header.
  ///
  /// **The split is by question, not by count.** The pin and the compass are one thought — *I am
  /// here, facing that way* — and they were never two readings that wanted opposite ends of a row;
  /// putting the bearing across the shutter from the pin made a watcher read the foot twice to
  /// assemble one sentence. Together on the leading edge they are the standing spot, and the
  /// trailing edge is left to the other question entirely: how high.
  ///
  /// **Halves rather than a centred overlay**, so the two groups can never run under the shutter.
  /// Both sides take the same flexible width, which centres the control exactly while giving each
  /// reading a hard bound to lay out in — a stratum spelled *Understory* at an accessibility text
  /// size truncates inside its own half instead of colliding with the thing a thumb is aiming for.
  ///
  /// They fade with the shutter rather than staying put, and not only because the panel covers
  /// them: the foot is one object, and half of it hanging on while the other half becomes a
  /// viewfinder would read as two.
  ///
  /// `LIVE` used to sit opposite the shutter. It was a plate that never changed, on a screen whose
  /// strip is already moving because the microphone is open.
  private var controls: some View {
    HStack(spacing: 0) {
      standingReading
        .frame(maxWidth: .infinity, alignment: .leading)

      // On the phone the shutter opens the viewfinder panel; on the glasses it *is*
      // the shutter — the wearer's eyes already framed the shot, so the press asks the
      // glasses for the photograph and the panel never enters into it. While one is
      // mid-crossing the control dims and holds still; what the crossing itself looks
      // like is a row on the log, where the photograph is going to land.
      Button {
        if model.uiState.isGlassesSessionLive {
          model.capturePhoto()
        } else {
          model.openCamera()
        }
      } label: {
        Image(glyph: theme.glyphs.shutter)
          .resizable()
          .frame(width: shutterSize, height: shutterSize)
          .foregroundStyle(
            model.uiState.isCapturing
              ? theme.colors.textFaint
              : theme.colors.textPrimary
          )
          .frame(width: shutterTargetSize, height: shutterTargetSize)
          .contentShape(.rect)
      }
      .disabled(model.uiState.status != .listening || model.uiState.isCapturing)
      .accessibilityLabel(
        model.uiState.isGlassesSessionLive
          ? "Photograph through the glasses"
          : "Open the camera"
      )
      // What the panel grows out of, measured rather than guessed. `onGeometryChange` rather
      // than a preference read at the root: a preference has to survive being reduced up
      // through every ancestor between here and there, and when it doesn't the panel silently
      // grows out of `CGRect.zero` — the top-left corner of the screen. This reports the frame
      // straight to the state that draws the panel.
      .onGeometryChange(for: CGRect.self) { proxy in
        proxy.frame(in: .named(sessionSpace))
      } action: { frame in
        cameraControlFrame = frame
      }

      elevationReading
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    // The foot *becomes* the panel, so it goes rather than sitting underneath it — what leaves
    // and what arrives are meant to read as one object, which means arriving on the same curve
    // the panel leaves on.
    .opacity(model.uiState.isCameraOpen ? 0 : 1)
    .animation(
      model.uiState.isCameraOpen ? cameraMorph : cameraDismiss,
      value: model.uiState.isCameraOpen
    )
    .frame(maxWidth: .infinity)
    .padding(theme.space.gutter)
  }

  /// The camera, over the session — **a panel that is the button, grown**.
  ///
  /// It starts life as exactly the camera control's rectangle and grows from there into a rounded
  /// card over the lower part of the session, then shrinks back into it. Not a transition: the
  /// panel is always in the tree and its frame is animated between the two rectangles, so there
  /// is one object on screen throughout rather than a small one leaving and a large one arriving.
  /// A scale transition can only be anchored to a *corner of the thing being scaled*, which is
  /// near the button but never it — this is measured.
  ///
  /// A card rather than a screen, and that is the point: the camera is a mode *inside* a session
  /// that never stopped listening, and a viewfinder that swallowed the phone would say the
  /// opposite. The whole strip and the top of the log stay in view behind it.
  ///
  /// The shutter is real here — it takes the frame on screen, puts it on the timeline at this
  /// second, and closes the mode. The X leaves without taking one.
  private var cameraMode: some View {
    GeometryReader { proxy in
      let open = model.uiState.isCameraOpen
      let openRect = openPanelRect(in: proxy.size)
      // Before the control has been measured there is nowhere to grow from, so the panel
      // simply is its open rectangle — one frame at most, and only on the first composition.
      let closedRect = closedPanelRect(openRect: openRect)
      let rect = open ? openRect : closedRect

      ZStack(alignment: .bottom) {
        // A scrim, so the panel reads as raised over a session that is still running.
        theme.colors.ink
          .opacity(open ? scrimOpacity : 0)
          .ignoresSafeArea()

        cameraPanel
          // The contents fade in over the growth rather than being scaled up from
          // nothing: a viewfinder squeezed into 48 points is a smear, and the button it
          // is standing in for is a shape, not a picture.
          //
          // **Leaving is not arriving played backwards.** On the way in there is
          // something to watch become the panel. On the way out the panel has already
          // done its job, and a spring that overshoots on the way down is a card of live
          // viewfinder being re-laid-out and re-drawn for four hundred milliseconds after
          // anyone stopped caring what it showed. So it leaves on a short curve instead:
          // one motion, no bounce, done before the eye follows it.
          .opacity(open ? 1 : 0)
          // Both animatable, so the whole rectangle travels from the control to the card
          // and back.
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Every animatable thing in here — the scrim, the rectangle, the fade — on one curve,
      // chosen by direction. Stated here rather than left to whatever transaction the tap
      // arrived in, because a flash capture closes the panel from an async continuation with
      // no transaction at all, and a panel that vanished instantly after a lit photo was the
      // other half of the jank.
      .animation(open ? cameraMorph : cameraDismiss, value: open)
    }
    // Closed, this is an empty layer over the whole screen — it must not take the taps meant
    // for the session's own controls underneath it.
    .allowsHitTesting(model.uiState.isCameraOpen)
  }

  /// Where the panel starts and ends its life: the camera control's own rectangle, with its foot
  /// dropped onto the open panel's.
  ///
  /// **The two rectangles share a bottom edge, and that is the whole point of this.** The panel
  /// lays its controls out from that edge, so if it travels during the morph the shutter travels
  /// with it — pressed, the button lifted an inset and settled back, which is the one thing on
  /// the screen that must not move while a thumb is on it. Matching the *ends* was not enough;
  /// this matches every frame in between.
  ///
  /// Growing the closed rectangle down by that inset costs nothing visible: the panel's contents
  /// are still fading in at that point, and what is on screen is a rounded shape the size of the
  /// button, twelve points taller than the button.
  private func closedPanelRect(openRect: CGRect) -> CGRect {
    guard !cameraControlFrame.isEmpty else { return openRect }
    return CGRect(
      x: cameraControlFrame.minX,
      y: cameraControlFrame.minY,
      width: cameraControlFrame.width,
      height: max(openRect.maxY - cameraControlFrame.minY, 0)
    )
  }

  /// Where the panel sits once it is open: the lower part of the screen, inset from three edges.
  private func openPanelRect(in size: CGSize) -> CGRect {
    let inset = theme.space.related
    let height = size.height * cameraPanelHeight
    return CGRect(
      x: inset,
      y: size.height - inset - height,
      width: max(size.width - inset * 2, 0),
      height: height
    )
  }

  /// The panel itself: the picture, the band it is aimed at across the head of it, and the
  /// controls laid over the foot.
  private var cameraPanel: some View {
    ZStack(alignment: .bottom) {
      // What the panel is made of while it is still becoming one. A flat fill made the
      // growing rectangle read as a hole cut in the session; a screened surface reads as
      // something laid over it — see ``FrostedGround``.
      FrostedGround()

      // **The picture is the platform's own layer, and that is the whole viewfinder
      // story.** The camera draws into it on the hardware path — no frame of the live
      // picture ever crosses app code — which is what makes a pinch here feel like the
      // camera app's: the preview is not waiting on any copy this process makes. Three
      // earlier rounds of zoom machinery (request pacing, frame stamps, a lead-scale
      // correction) were all compensation for drawing the viewfinder out of frames, and
      // all three went when the layer came in. The frames are still collected — they are
      // what the shutter *takes*, and the picture a source with no layer falls back to.
      //
      // The pinch sits on whichever picture is up. Only offered by a camera that can
      // actually do it; a gesture that silently does nothing is worse than no gesture.
      if let viewfinder = model.viewfinder {
        CameraViewfinderView(viewfinder: viewfinder)
          .accessibilityElement()
          .accessibilityLabel("Live camera")
          .gesture(model.uiState.cameraControls.contains(.zoom) ? magnify : nil)
      } else if let frame = model.frame {
        // No layer, but frames — a SwiftUI preview, a simulated feed. The picture costs a
        // conversion per frame here and that is fine: nothing without a real camera
        // produces enough of them to matter.
        GeometryReader { proxy in
          Image(decorative: frame.image, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityElement()
        .accessibilityLabel("Live camera")
        .gesture(model.uiState.cameraControls.contains(.zoom) ? magnify : nil)
      } else {
        PlateLabel(text: "Opening the camera", color: theme.colors.textSecondary)
          .frame(maxHeight: .infinity)
      }

      // What the viewfinder is aimed at, across the head of the picture — see ``gazeChip``.
      if let band = model.uiState.elevationBand {
        gazeChip(band)
          .padding(.top, theme.space.related)
          .frame(maxHeight: .infinity, alignment: .top)
      }

      panelControls
    }
    .clipShape(.rect(cornerRadius: theme.space.gutter))
  }

  /// Which stratum the viewfinder is pointed at, over the top of the picture.
  ///
  /// **The same reading ``elevationReading`` carries, drawn where the foot cannot follow.** The
  /// foot fades out as the panel grows, so the two are never on screen together — this is that
  /// reading continuing across the one moment it matters most, when the watcher is actually
  /// aiming. Not a second opinion: both read ``RealtimeUiState/elevationBand``, and both name it
  /// through the journal's formatter.
  ///
  /// It used to be the only place this reading appeared, on the argument that a stratum is about
  /// *aim* and so belongs on the thing being aimed. That held while the aim came from the phone's
  /// own attitude. It no longer does: the reading now follows the wearer's head whenever the
  /// glasses have the session, which makes it a fact about the watcher — true whether or not a
  /// viewfinder is open, and so owed a place in the foot beside the pin and the compass.
  ///
  /// A word, not an angle: `Canopy` is where a bird would be, where `+37°` is a fact about a
  /// sensor. See ``gazeBand(_:)``.
  ///
  /// Its own dark capsule rather than the gradient the foot uses. A band across the top of a
  /// viewfinder would darken the sky, which is the half of the frame a watcher is usually reading;
  /// a capsule carries the same legibility over a bright ground in the width of the word itself.
  ///
  /// Absent rather than quiet, unlike its twin in the foot: over a picture there is no row for a
  /// gap to unbalance, so a stratum that cannot be read is simply not drawn.
  private func gazeChip(_ band: GazeContext) -> some View {
    // The journal's formatter, not a local one: the chip and the saved entry name a stratum the
    // same way or they are two vocabularies for one reading.
    let label = JournalFormatting.gazeLabel(band)
    return HStack(spacing: theme.space.snug) {
      Image(glyph: theme.glyphs.gaze)
        .foregroundStyle(theme.colors.textPrimary)
      PlateLabel(text: label, color: theme.colors.textPrimary)
    }
    .padding(.horizontal, theme.space.snug)
    .padding(.vertical, theme.space.tight)
    .background(theme.colors.ink.opacity(gazeChipOpacity), in: .capsule)
    .accessibilityElement()
    .accessibilityLabel("Aimed at the \(label)")
  }

  /// The pinch. `magnification` counts from where the fingers started, so it multiplies the zoom
  /// the gesture began at rather than the one it has reached — otherwise every frame of the
  /// gesture would compound the last and a slow pinch would run away to the stop.
  ///
  /// A gesture that reported the *step* rather than the total would call
  /// ``RealtimeViewModel/zoomBy(_:)`` instead of ``RealtimeViewModel/setZoom(_:)``. The view
  /// model carries both, so the difference stops at the screen.
  private var magnify: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        model.setZoom(zoomAnchor * value.magnification)
      }
      .onEnded { _ in
        zoomAnchor = model.zoom
      }
  }

  /// Leave without a photo on the left, take one in the middle, the flash on the right — the
  /// panel's own foot.
  ///
  /// Over the picture rather than under it, so the panel stays one shape however tall the frame
  /// turns out to be. The gradient is what keeps a white glyph legible over a bright sky.
  ///
  /// **The flash is there only if this camera has one.** Built from
  /// ``RealtimeUiState/cameraControls`` rather than from the source's kind, so the day the frames
  /// come off a pair of glasses the foot quietly loses a flash the glasses do not have — with no
  /// line here mentioning glasses. Absent, not disabled: a greyed-out control invites someone to
  /// wonder what they broke.
  private var panelControls: some View {
    ZStack {
      Button {
        model.closeCamera()
      } label: {
        Image(glyph: theme.glyphs.close)
          .foregroundStyle(theme.colors.textPrimary)
          .frame(width: closeControlSize, height: closeControlSize)
      }
      .accessibilityLabel("Close the camera")
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        model.capturePhoto()
      } label: {
        Image(glyph: theme.glyphs.shutter)
          .resizable()
          .frame(width: shutterSize, height: shutterSize)
          .foregroundStyle(theme.colors.textPrimary)
          .frame(width: shutterTargetSize, height: shutterTargetSize)
          .contentShape(.rect)
      }
      // Held through an armed flash's settle as well as through a missing frame: the panel
      // deliberately stays open across ``flashSettle`` so the light is seen coming on, and
      // a shutter left live across those milliseconds is a second capture waiting to
      // happen — see ``RealtimeUiState/isCapturing``.
      .disabled(model.frame == nil || model.uiState.isCapturing)
      .accessibilityLabel("Take a photo")

      if model.uiState.cameraControls.contains(.flash) {
        Button {
          model.toggleFlash()
        } label: {
          Image(
            glyph: model.uiState.isFlashOn
              ? theme.glyphs.flash
              : theme.glyphs.flashOff
          )
          // Armed in gilt: the app's one warm ink, doing the job a yellow flash badge
          // does everywhere else. Off is the struck-through bolt in the ordinary ink —
          // two drawings, so the state is legible without comparing brightnesses.
          .foregroundStyle(
            model.uiState.isFlashOn
              ? theme.colors.gilt
              : theme.colors.textPrimary
          )
          .frame(width: closeControlSize, height: closeControlSize)
        }
        .accessibilityLabel(model.uiState.isFlashOn ? "Flash on" : "Flash off")
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .padding(.horizontal, theme.space.related)
    // One step tighter than the control it grew out of, and that is what keeps the shutter
    // still: the panel's own bottom edge already sits an inset above where the control's did,
    // so the same gutter here would lift the shutter by exactly that inset — the one thing
    // under the thumb, jumping, in the middle of an animation whose whole claim is that the
    // button *became* this.
    .padding(.bottom, theme.space.related)
    .background(
      LinearGradient(
        colors: [theme.colors.ink.opacity(0), theme.colors.ink.opacity(0.6)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  /// Why the session has no sound, and what to do about it.
  private var failureNotice: some View {
    VStack(spacing: theme.space.related) {
      PlateLabel(text: "Session", color: theme.colors.gilt)
      Text(model.uiState.failureMessage ?? "")
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, theme.space.gutter)
  }
}

/// The chrome controls' tap target — the wizard's size, so the feature's controls all match.
/// Named around SwiftUI's own `controlSize`, which a plain `controlSize` here would collide with.
private let closeControlSize: CGFloat = 48

/// Room for the widest of the eight points, so a turn from `N` to `NW` moves nothing but letters.
private let bearingPlateWidth: CGFloat = 28

/// The device silhouette in the source pill. Set to the plate's own cap height rather than the
/// glyph set's 24, so the icon and the word read as one line of type instead of a picture with a
/// caption beside it.
private let sourceGlyphSize: CGFloat = 16

/// The air between the switch's track and the side sitting in it. One step under the scale's
/// smallest gap on purpose — this is a hairline of ground showing around a chip, not a gap between
/// two things, and at `tight` the track reads as a second, larger pill around the first.
private let switchTrackInset: CGFloat = 2

/// How long the switch takes to throw. Short: the selection moves on the press, and this is only
/// the ink catching up with a decision the watcher has already made.
private let switchThrow: Double = 0.18

/// How dark the gaze chip's capsule is. The same value the foot's gradient ends on, so the two
/// pieces of chrome laid over the picture are laid over it to the same depth.
private let gazeChipOpacity: Double = 0.6

/// The shutter is drawn larger than the other controls on purpose: it is the one thing on the
/// screen a thumb goes looking for without aiming.
private let shutterSize: CGFloat = 64

/// Its tap target, a little wider than the drawing, so the ring never sits flush against its edge.
private let shutterTargetSize: CGFloat = 72

/// How much of the screen the camera panel takes. A fraction rather than a height, because what
/// has to hold across every phone is what stays *uncovered*: the whole strip, and the top of the
/// log under it.
private let cameraPanelHeight: CGFloat = 0.62

/// How far the session dims behind the panel. Enough to say the panel is in front, not so much
/// that the strip stops being readable — it is still recording, and still worth watching.
private let scrimOpacity: Double = 0.55

/// The camera's morph. A spring rather than a curve: the panel is meant to read as the control
/// growing, and something that grows to exactly its final size and stops reads as a cross-fade.
private let cameraMorph = Animation.spring(response: 0.38, dampingFraction: 0.82)

/// How the panel leaves: a short ease, not the spring it arrived on.
///
/// A spring is right for arriving because it is a thing *becoming* — it should overshoot slightly
/// and settle. Leaving has nothing to settle into, and a spring's tail keeps a live camera frame
/// being resized and recomposited long after the panel stopped being interesting, which is what the
/// jank was. Two hundred milliseconds of `easeOut` covers the same distance and stops dead.
private let cameraDismiss = Animation.easeOut(duration: 0.2)

/// How far the review travels on its way in. A `separate`'s worth — enough that it reads as
/// arriving rather than appearing, and short enough that nothing on it is legible mid-flight and
/// then moves.
private let reviewRise: CGFloat = 16

/// How the session leaves when the stop lands: a short fade, no travel.
private let reviewDeparture = Animation.easeOut(duration: 0.22)

/// How the review arrives, held back until the session has all but gone — the second beat.
///
/// The delay is the whole effect. Without it the two screens cross-fade and the eye has two
/// things to read at once; with it there is a moment where the session is over and nothing has
/// replaced it yet, which is exactly what has happened.
private let reviewArrival = Animation.easeOut(duration: 0.34).delay(0.18)

/// The coordinate space the camera control's frame and the panel's are both measured in. Without a
/// named space the two would be reported against different ancestors and the panel would grow out
/// of the wrong point.
private let sessionSpace = "session"

#Preview("Listening") {
  RealtimeScreen(model: previewRealtimeViewModel())
    .birdSpotterTheme()
}

#Preview("Microphone denied") {
  RealtimeScreen(model: previewRealtimeViewModel(audioSource: PreviewAudioSource(failure: .accessDenied)))
    .birdSpotterTheme()
}

/// A session over the preview stand-ins — what both this cover's previews and the Identify
/// screen's are built on.
@MainActor
func previewRealtimeViewModel(
  audioSource: any AudioCaptureSource = PreviewAudioSource()
) -> RealtimeViewModel {
  RealtimeViewModel(
    audioSource: audioSource,
    previewSource: PreviewCameraSource(),
    detector: PreviewDetector(),
    director: PreviewDemoDirector(),
    birdCatalog: PreviewBirdCatalog(),
    journal: PreviewJournal(),
    glassesSession: PreviewGlassesSession(),
    glassesCamera: PreviewGlassesCamera(),
    glassesInput: PreviewGlassesInput(),
    glassesSpeech: PreviewGlassesSpeech(),
    glassesDisplay: PreviewGlassesDisplay(),
    spokenOutput: PreviewSpokenOutput(),
    locationProvider: PreviewLocationProvider(),
    headingProvider: PreviewHeadingProvider(),
    gazeProvider: PreviewGazeProvider()
  )
}
