/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  RealtimeViewModel.swift
//  birdspotter
//

import Foundation
import UIKit

/// Where a session is: waiting for the microphone, listening, or stopped.
nonisolated enum SessionStatus: Sendable {
  case opening
  case listening
  case failed
}

/// Which device the session is running on, as the source pill says it.
///
/// **One enum rather than four booleans read at the pill.** The screen used to assemble the pill's
/// word out of `isSourceLinking` and `sourceKind` inline, which left the two genuinely different
/// kinds of *not the glasses yet* — reaching for a pair, and a pair that has gone quiet — spelled
/// identically as the phone. They are separate states here because they want separate drawings: one
/// is working, the other is waiting on the wearer.
///
/// The honesty rule is unchanged and lives in ``RealtimeUiState/sourceState``: `glasses` is claimed
/// only once audio has actually arrived from a pair, never on the promise of one.
nonisolated enum SourceState: Sendable {

  /// The phone's own microphone and camera — the session's ground state.
  case onDevice

  /// A pair has been asked for and has not answered yet. The one state that works visibly.
  case linking

  /// The glasses have the session: their audio is what the strip is being drawn from.
  case glasses

  /// A glasses run is still in flight, but the device is not giving us anything — a doff, a
  /// temple tap, a hinge. Not a failure and not the phone: the run is there to be resumed by
  /// the wearer, or hung up on with the pill.
  case glassesPaused

  /// A scripted feed, running on the device.
  case simulated
}

/// How long into the session something landed, as a stopwatch reads: `0:14`, `1:07`.
///
/// Minutes and seconds and nothing else. A session is minutes long by design — a demo that needs
/// an hours column has stopped being a demo — and a leading `00:` on every screenshot is noise.
///
/// Named for what it labels, a stamp on a log row, rather than for the ``SessionClock`` it is read
/// off. There is no clock drawn on this screen; there are stamps against the things that happened.
nonisolated func sessionStamp(_ seconds: Double) -> String {
  let whole = max(0, Int(seconds))
  return "\(whole / 60):\(String(format: "%02d", whole % 60))"
}

/// How much of the session the strip shows at once. Eight seconds is about 500 columns — wide
/// enough that a whole phrase of song fits, narrow enough that a single call is more than a tick.
nonisolated let timelineWindowSeconds = 8.0

/// How long the light is on before the frame is taken.
///
/// Long enough for auto-exposure and auto-white-balance to answer the torch — under that, a lit
/// photo is the unlit one with a hotspot in it — and short enough that the shutter still feels like
/// a shutter. There is no capture API here to hand a flash mode to; this is what a flash *is* when
/// the photograph is a viewfinder frame.
nonisolated let flashSettle = Duration.milliseconds(320)

/// What kept a stopped session out of the journal.
nonisolated enum SessionSaveError: Sendable {
  case noLocationFix
  case writeFailed
}

/// A stopped session, being decided about.
///
/// The stop answers *is the microphone still open*; this answers *is this worth keeping*, and
/// they are two different questions asked a few seconds apart — see the confirmation contract.
/// Nothing here has touched the journal yet: the events are still the session's, the notes are
/// still unsaved, and Discard walks away from all of it.
///
/// ``droppedBirds`` holds the stamps of detections the watcher has dropped — a saved outing's
/// sightings are the birds a watcher *confirmed*, not the ones a detector offered, and dropping
/// a bad one here is the whole reason a confirmation exists rather than an autosave.
nonisolated struct SessionReview: Sendable {
  /// The stop-clock reading, which becomes the outing's `durationMs` at save.
  var durationSeconds: Double
  var notes: String = ""
  var droppedBirds: Set<Double> = []
  var isSaving = false
  var saveError: SessionSaveError?
  /// Set once the journal has the outing — what tells the screen the cover can fall.
  var savedOutingId: String?

  /// The line under the save controls, or `nil` while there is nothing wrong.
  var saveErrorMessage: String? {
    switch saveError {
    case .none: nil
    case .noLocationFix:
      "Couldn't get your location, and an outing needs one. Try again in a moment."
    case .writeFailed:
      "Couldn't save this outing. Nothing was written — try again."
    }
  }
}

/// What the real-time screen renders around the strip.
///
/// The strip's own data is **not** here: columns arrive 62 times a second and this changes perhaps
/// twice a run, so folding them together would rebuild the header, the chips and the controls on
/// every column. The buffer lives on the view model and the strip reads it directly, told that the
/// window has moved by a plain elapsed reading.
nonisolated struct RealtimeUiState: Sendable {
  var sourceKind: CaptureSourceKind = .phone
  var status: SessionStatus = .opening
  var failure: AudioCaptureError?
  /// Whether a run is in flight — from the moment ``RealtimeViewModel/start(onGlasses:)`` opens
  /// one until the microphone stream ends, by a stop, a failure or a cancel. What anything
  /// that has to hold the process open for the session reads.
  var isRunning = false
  var session = RealtimeSession(startedAt: 0)
  var isCameraOpen = false

  /// What the camera behind this session can be asked to do — see ``CameraControl``. Read off the
  /// source once, because it describes hardware rather than anything that changes mid-run, and
  /// carried here so the panel builds its controls from a capability instead of from a `kind`.
  var cameraControls: Set<CameraControl> = []

  /// Whether the next photo will be taken with the light on.
  ///
  /// **Armed, not lit.** This is a flash the way a camera means one — a setting that decides what
  /// happens when the shutter fires — rather than a torch the watcher has to remember to put out.
  /// It survives the panel closing, because arming a flash costs nothing while the camera is shut
  /// and a photographer who set it once should not have to set it again.
  var isFlashOn = false

  /// Whether the pill is also a switch: the app is registered with Meta AI and a pair is
  /// reachable. The session may still fail to start — this is the invitation, not the
  /// promise.
  var isGlassesAvailable = false

  /// The crossing: from asking for the glasses until their audio actually arrives.
  ///
  /// **It ends at the ears, not at the session.** It used to be cleared when the DAT session
  /// reported `started`, which is one beat too early — the glasses' audio still has to come
  /// up after that, and the pill only flips on a chunk. In the gap the state was *not linking,
  /// not glasses*, so the pill fell back to `On device` for a fraction of a second between
  /// `Linking` and `Glasses`: phone, glasses, phone, glasses. Ending it on arrival closes the gap
  /// by construction rather than by papering over it in ``sourceState``.
  ///
  /// Arrival semantics either way, which is the rule the audio failover contract sets: never
  /// claim a source on the promise of one. Saying *still getting there* for the whole
  /// crossing is not a claim.
  var isSourceLinking = false

  /// A capture is in flight. The shutter holds still rather than firing a second one into it.
  ///
  /// **One flag for both devices, because it guards one mistake.** A photograph mid-crossing
  /// from the glasses must not queue a second ask onto a Bluetooth link already carrying one;
  /// a photograph mid-``flashSettle`` on the phone must not start a second settle that fights
  /// the first for the torch. Two names for *the shutter is busy* would be two chances to
  /// check the wrong one.
  ///
  /// **The guard is the whole capture rather than a fixed window.** The client spec asks for
  /// a 500 ms debounce; holding until the capture actually finishes is stricter than that and
  /// needs no number — a BTC crossing can take well over half a second, and a timer that
  /// expired mid-flight would re-arm the shutter exactly when pressing it is worst.
  ///
  /// It says nothing about *where the picture is* — that is the timeline's job now, on the
  /// photo's own row. See ``RealtimeViewModel/captureThroughGlasses()``.
  var isCapturing = false

  /// Whether the glasses can actually be photographed through right now: a DAT session whose
  /// camera stream has reached `streaming`.
  ///
  /// Kept apart from ``sourceKind`` because the two answer different questions and can
  /// honestly disagree. The pill says whose *ears* these are, which follows the audio that
  /// arrived; this says whose *eyes* the shutter will use. During the beat after a pause they
  /// differ, and the screen is right both times.
  var isGlassesSessionLive = false

  /// Whether a glasses run is in flight at all — from the tap that asked for one until it
  /// ends, across every pause and resume in between.
  ///
  /// What makes the pill tappable while the session is *paused*: the run is still there to
  /// hang up on, even though nothing is live and the glasses may be out of reach.
  var isGlassesRequested = false

  /// What the reachable pair has left, 0–100 — or `nil` for every way of not knowing: no pair
  /// in range, or a link that has not said yet.
  ///
  /// **A glance, not the settings screen's row.** That row is a status panel a watcher goes
  /// looking for; this is the one number that changes what they do next, on the screen they are
  /// already on. A session runs the glasses' camera, microphone and sensors at once, so *how much
  /// longer can I do this* is a question the session itself should answer.
  ///
  /// Tri-state to `nil` the whole way down, and the data layer has already mapped the link's
  /// `0` — its unknown-or-empty — to nothing, so a number that reaches here is a real reading.
  /// See ``GlassesDeviceInfo/batteryLevel``.
  var glassesBattery: Int?

  /// Whether the pair is on a face, when the pair says. **A connected pair and a *worn* pair
  /// are different facts about the session**, and only the second one means the camera is
  /// pointing where the wearer is looking — so the switch draws them differently. `nil` while
  /// nothing is reachable, and while a reachable pair has not reported yet.
  var isGlassesWorn: Bool?

  /// Whether a reachable pair has a panel to draw on — what makes an identified bird on the
  /// timeline a **thing to press**.
  ///
  /// **The automatic send is deliberately not gated on this, and this is deliberately not
  /// gated on a running session.** An identification pushes itself up the moment it lands and
  /// asks nobody first, because a send with nowhere to land lands nowhere and waiting on an
  /// answer would make every identification pause for a question whose answer changes nothing
  /// (see ``GlassesDisplayRepository``). An *offer* is the other way round: a row that invites
  /// a tap it cannot honour is the screen inventing a control, which is exactly what
  /// ``canToggleSource`` refuses to do for the source switch.
  ///
  /// Gated on the pair being reachable, like the charge and the wear beside it — a display on
  /// a pair that has left the room is a panel nothing can reach.
  var isDisplayAvailable = false

  /// The bird whose card is open on the phone, or `nil` — the usual state.
  ///
  /// **The fallback half of the log's tap, and only the fallback.** A pair with glass gets the
  /// card where the wearer is already looking and this stays nil; everything else gets it here,
  /// laid out the way the glasses would have laid it out. It is deliberately *not* set when the
  /// card went up on the display: two copies of one card, one of them on a phone the watcher
  /// put in their pocket, is the app answering a question twice.
  ///
  /// Session state rather than screen state because the row that opened it is session state:
  /// the same stop that ends the run is what should take the card down with it.
  var cardOnPhone: SpeciesWithMedia?

  /// One line about the source, when something needs saying — a missing camera grant, a
  /// crossing that failed. Cleared on the next toggle; `nil` is the usual, quiet state.
  var sourceNotice: String?

  /// Where the session is happening: the one fix taken as it opened, or `nil` while that is
  /// still being asked for — or for good, if it never came.
  ///
  /// Asked for the instant the session starts rather than when a sighting is finally logged,
  /// because *where* is a fact about the moment the watcher started watching, and by the time
  /// they have a name for the bird they may be a field away. ``LocationProvider`` answers `nil`
  /// for every way of not knowing, so there is no error to carry beside this.
  var coordinate: Coordinate?

  /// Which way the watcher is facing, in degrees clockwise from north — or `nil` before the
  /// compass has said, or on a phone that has none.
  var heading: Double?

  /// How high the watcher is aiming, in degrees above the horizon — or `nil` before the phone has
  /// said, or on one that cannot.
  ///
  /// Kept beside ``heading`` rather than folded into it because the two arrive from different
  /// instruments at different moments — see ``GazeProvider``. Together they are a full aim: which
  /// way on the ground, and how far up from it.
  var elevation: Double?

  /// The stopped session being decided about, or `nil` while one is still running.
  var review: SessionReview?

  /// Whether the session is over and the confirmation is what the cover shows.
  var isReviewing: Bool { review != nil }

  /// Which device the pill is answering for — see ``SourceState``.
  ///
  /// **The order of the branches is the honesty contract.** ``SourceState/glasses`` is reached
  /// only through ``sourceKind``, which follows the chunks that actually arrived, so a run that
  /// has been asked for and has not delivered audio can never draw the pill as the glasses'. A
  /// run in flight with nothing live is the pause; everything else falls back to the device in
  /// the hand.
  var sourceState: SourceState {
    if isSourceLinking { return .linking }
    if sourceKind == .glasses { return .glasses }
    if isGlassesRequested && !isGlassesSessionLive { return .glassesPaused }
    if sourceKind == .simulated { return .simulated }
    return .onDevice
  }

  /// What the source pill reads.
  ///
  /// **`On device` rather than `Phone`.** The pill's question is *whose ears and eyes are these*,
  /// and the useful half of the answer is that they are not the glasses' — said of the thing the
  /// watcher is holding, which is also what the phone glyph beside it draws. `Phone` was a
  /// hardware name where the sentence wanted a place.
  ///
  /// The ears stay the phone's either way — the SDK ships no audio stream of its own; what
  /// the toggle moves today is the camera the shutter fires, so the pill answers for the
  /// session's device.
  var sourceLabel: String {
    switch sourceState {
    case .onDevice: "On device"
    case .linking: "Linking"
    case .glasses: "Glasses"
    case .glassesPaused: "Waiting"
    case .simulated: "Simulated"
    }
  }

  /// Whether the source control is a **switch** rather than a label: a registered pair in reach,
  /// or a run to hang up on.
  ///
  /// This is also what decides which of the two drawings the header carries. With nothing to
  /// switch to there is one device in the story, and a two-sided control offering a side that does
  /// not exist would be the screen inventing an option — so it stays the single pill it always
  /// was. The moment a pair is reachable the control becomes a segmented chip with both sides on
  /// it, because *now* there is a choice, and a choice should look like one before it is made.
  var canToggleSource: Bool {
    isGlassesAvailable || isGlassesRequested
  }

  /// Whether the switch's glasses side is the chosen one.
  ///
  /// True through the whole crossing, not just once it lands: a tap moves the selection at once
  /// and the *ink* is what stays honest about how far along it is — see ``glassesSourceLabel``. A
  /// switch whose selection waited for the ears would sit under the watcher's thumb doing nothing
  /// visible for as long as the glasses' audio takes, which is exactly how a control gets pressed twice.
  ///
  /// **And it stays true through a pause, which is the case worth arguing.** When the glasses drop
  /// out the phone picks the recording back up, so it is tempting to throw the switch back to the
  /// left — and that would be wrong twice over. The run is still in flight and still assigned to
  /// the glasses, waiting on the wearer; and because only the *unlit* side takes a tap, a
  /// selection on the left would make the glasses side the live one — where a tap calls
  /// ``RealtimeViewModel/toggleSource()``, which while paused **hangs the run up**. A control
  /// labelled `Glasses` that ends the glasses session. The selection says where the session is
  /// assigned; ``isDeviceCarrying`` says who is doing the work meanwhile.
  /// Whether a card the watcher asked for should go up on the glasses rather than open here.
  ///
  /// **Routed on the session, not on the pill and not on the pairing** — the same rule the
  /// shutter follows (see ``capturePhoto()``). A pair can be reachable, and even have glass in
  /// it, while the run is deliberately on the phone: that is what the switch's *On device* side
  /// means, and a card that flew to a pair sitting on the table would be the app answering
  /// somewhere nobody is looking. So a run on the phone gets the phone's card even with a
  /// Display pair in the room, and only a live glasses session sends it up.
  var cardGoesToGlasses: Bool {
    isDisplayAvailable && isGlassesSessionLive
  }

  var isGlassesSelected: Bool {
    switch sourceState {
    case .linking, .glasses, .glassesPaused: true
    // **A live run keeps the selection even when the phone has the ears.** The pill reads the
    // microphone, and the microphone is not the whole session: with a run in flight the
    // shutter still fires through the glasses and the button on the temple still works, so a
    // switch thrown back to the phone would say the session had moved when only its ears had.
    // See ``withoutGlassesEars()``.
    case .onDevice, .simulated: isGlassesRequested && isGlassesSessionLive
    }
  }

  /// Whether the phone is doing the recording while the switch is thrown somewhere else — the one
  /// state where the selected side and the working side are different devices.
  ///
  /// It is what stops a paused run reading as a stopped session. The glasses side says the session
  /// is waiting on them; this lifts the phone side out of the idle ink to say *and this is
  /// carrying it in the meantime*, which is the sentence the notice underneath spells out in
  /// words. Without it the switch shows one lit side that is not listening and one dim side that
  /// is, next to a sonogram visibly still scrolling.
  var isDeviceCarrying: Bool {
    switch sourceState {
    case .glassesPaused: true
    // A run whose ears went back to the phone, which is the same sentence as the pause — the
    // switch is on the glasses, and this is what is doing the listening meanwhile. Not
    // `linking`, where the handover has closed one microphone and not yet opened the other and
    // nothing is carrying anything.
    case .onDevice: isGlassesSelected
    case .linking, .glasses, .simulated: false
    }
  }

  /// The switch's left side: the device in the hand, named for what it actually is. A simulated
  /// feed is still *on the device*, and saying so is worth more than the symmetry.
  var deviceSourceLabel: String {
    sourceKind == .simulated ? "Simulated" : "On device"
  }

  /// The switch's right side. **It carries the live state, and the left side never does** — every
  /// word this control has to say beyond the two device names is about the glasses: reaching for
  /// them, or having lost them. The phone is only ever the phone.
  ///
  /// **`Waiting`, not `Paused`.** The SDK's state is `paused` and the notice underneath still says
  /// the glasses paused the session, because that is what happened to *them*. On a chip with no
  /// subject the word attaches to the nearest noun the watcher has in mind, which is the session —
  /// and the session did not pause: the strip is still scrolling and the phone is still recording.
  /// `Waiting` can only be read about the thing it is printed on, and it is the truth: the switch
  /// is thrown to the glasses and waiting for the wearer to pick them back up.
  /// **The charge rides here, on the word it is about.** It used to hang off the trailing edge
  /// of the bar as a plate of its own, which put a number about the glasses at the far side of
  /// the header from the control naming them — two readings about one device, in two places, and
  /// the bar's only other occupant. On the side that already says *Glasses*, under the glyph that
  /// already means them, it cannot be read as the phone's.
  ///
  /// **Only on the settled word.** `Linking` and `Waiting` are about reaching for a pair, and a
  /// charge printed beside either is a fact about a device the chip is in the middle of saying it
  /// does not have yet. It appears when the state does, and the number's arrival is not something
  /// the watcher has to be told about twice.
  var glassesSourceLabel: String {
    switch sourceState {
    case .linking: "Linking"
    case .glassesPaused: "Waiting"
    default: glassesBattery.map { "Glasses \($0)%" } ?? "Glasses"
    }
  }

  /// True once the fix has landed — what the location dot is lit by.
  var isLocated: Bool { coordinate != nil }

  /// The bearing as one of eight compass points, or `nil` while there is nothing to read.
  var headingPoint: String? { heading.map(compassPoint) }

  /// The elevation as one of five strata, or `nil` while there is nothing to read. The same type
  /// the journal stores against a moment, so the chip and the entry agree by construction.
  var elevationBand: GazeContext? { elevation.map(gazeBand) }

  /// What the log says while there is nothing on it yet.
  ///
  /// **The half-second before the first sample is real, and it is not listening.** Activating an
  /// `AVAudioSession` tears down and rebuilds the audio route, which is not something an app
  /// can hurry. It happens off the main thread
  /// so nothing is frozen, but a screen that said `LISTENING` over a microphone that had not
  /// opened yet would be the one dishonest line on it. So it says what it is doing instead, and
  /// the word changes the moment the first sample lands.
  var emptyLogLabel: String {
    status == .listening ? "Listening" : "Opening the microphone"
  }

  /// The line shown in place of the strip, or `nil` while there is nothing wrong.
  var failureMessage: String? {
    switch failure {
    case .none: nil
    case .accessDenied:
      "Microphone access is off. Turn it back on in Settings to start a session."
    case .unavailable:
      "There's no microphone to listen with."
    case .interrupted:
      "Another app took the microphone. Close the session and start it again."
    }
  }

  /// The first samples have landed and the session is under way.
  func listening() -> RealtimeUiState {
    var next = self
    next.status = .listening
    next.failure = nil
    return next
  }

  /// A chunk of audio has actually arrived, from `source` — **the only place the pill's claim
  /// becomes true.**
  ///
  /// A tap on the pill is a request; the DAT session reporting `started` is that request being
  /// accepted; this is the ears arriving, which is the one thing the pill is allowed to be read
  /// off. It is also what closes ``isSourceLinking``: the crossing is over when there is audio to
  /// show for it, and not before — see that property for the flicker this shape exists to
  /// prevent.
  ///
  /// The phone's own chunks close nothing, deliberately. While a glasses run is in flight the
  /// phone is still recording underneath — the failover never closes a working microphone on the
  /// promise of a better one — so a phone chunk mid-crossing means *the crossing has not happened
  /// yet*, which is the state we are already in.
  func hearing(_ source: CaptureSourceKind) -> RealtimeUiState {
    var next = self
    if next.sourceKind != source { next.sourceKind = source }
    if source == .glasses && next.isSourceLinking { next.isSourceLinking = false }
    return next.status != .listening ? next.listening() : next
  }

  /// The glasses' ears were asked for and could not be had — the phone keeps the microphone, and
  /// the run goes on without it.
  ///
  /// **`Linking` is a promise, and this is the only thing that can withdraw it.** The word is
  /// closed by glasses audio arriving (``hearing(_:)``) and by the session ending
  /// (``applying(_:)``, ``ending(crossingLost:parting:)``) — and a microphone that never opens is
  /// neither of those: the session is up, the shutter works, the temple button works, and the one
  /// thing that was asked for is not coming. Without this the pill sits on `Linking` for the
  /// whole run, reaching for a pair it has already stopped reaching for.
  ///
  /// **The run is not ended over it.** A glasses session with the phone's ears is most of what
  /// the glasses were for — the photograph, the button, the wearer's own aim — so this changes
  /// what the screen *says* and nothing about what the session *is*. The notice carries the half
  /// that survived, because a watcher told only that the microphone failed will reasonably
  /// conclude the glasses are done.
  ///
  /// A no-op when no run is in flight: the signal outlives the request by a beat, and a sentence
  /// about glasses on a screen that has gone back to the phone is worse than no sentence.
  func withoutGlassesEars() -> RealtimeUiState {
    guard isGlassesRequested else { return self }
    var next = self
    next.isSourceLinking = false
    next.sourceNotice = "The glasses' microphone didn't answer — the phone is listening. Photos and the button still come from the glasses."
    return next
  }

  /// The spine gave up, which ends the session — a screen that promises it is listening and is
  /// not would be the one dishonest thing here. Anything that is not one of ours is reported as
  /// ``AudioCaptureError/unavailable``, for the same reason the camera does it.
  func failed(_ error: any Error) -> RealtimeUiState {
    var next = self
    next.status = .failed
    next.failure = error as? AudioCaptureError ?? .unavailable
    return next
  }

  /// What the glasses session's own state does to the screen.
  ///
  /// **This decides what the glasses are *asked* to do; it does not move the pill.** The pill
  /// follows ``AudioChunk/source`` — audio that actually arrived — so that a session which
  /// starts but whose microphone never opens cannot leave the screen claiming the glasses.
  /// What this does own is ``isGlassesSessionLive``, which is what the shutter routes on:
  /// `started` here means the camera stream reached `streaming`, so a photograph can really
  /// be taken.
  ///
  /// The pause is narrated rather than diagnosed: a transition arrives carrying no reason,
  /// so the notice says what happened and not why. A later `started` clears it — the
  /// device resumed, and there is nothing left to explain.
  func applying(_ sessionState: GlassesSessionState) -> RealtimeUiState {
    var next = self
    switch sessionState {
    // **`started` opens the crossing rather than closing it.** The session being up is when
    // the glasses' ears are *asked* for — see the `usePreferred` call beside this — and the
    // first buffer of audio takes a beat to arrive. Holding the linking state across that beat is what
    // stops the pill dropping back to the phone between `Linking` and `Glasses`. A resume
    // after a pause goes through here too, and wants exactly the same beat; a session that
    // is already being heard through does not, hence the guard.
    case .started:
      next.isGlassesSessionLive = true
      next.isSourceLinking = sourceKind != .glasses
      next.sourceNotice = nil
    case .paused:
      next.isGlassesSessionLive = false
      next.isSourceLinking = false
      next.sourceNotice = "The glasses paused the session — the phone has it until they resume. Tap the side of the glasses to pick it back up."
    case .stopping, .stopped:
      next.isGlassesSessionLive = false
      next.isSourceLinking = false
    case .starting:
      // Already the linking beat the toggle set up.
      break
    }
    return next
  }

  /// What the screen is left with when a glasses run ends, however it ended: the switch back on
  /// the phone, and at most one line about why.
  ///
  /// **One writer for that line, because there used to be two.** A photograph still crossing when
  /// the run ended failed on its own and wrote *the photo didn't make it from the glasses*, while
  /// the run's own teardown wrote its parting line over the top — and whichever won, the row the
  /// picture would have landed on had already left the timeline. The teardown now waits for the
  /// crossing to settle and composes the sentence here, so exactly one lands.
  ///
  /// **The crossing's line wins, because it is the one with a consequence on screen.** A watcher
  /// who just saw a row disappear is owed that sentence more than they are owed *the glasses
  /// didn't answer* — which the switch, already back on the phone, has said in its own way.
  ///
  /// It says *the session ended* rather than naming who ended it: a long press on the temple and
  /// a tap on the switch arrive here identically, and what is worth saying is why the photograph
  /// is not there.
  func ending(crossingLost: Bool, parting: String?) -> RealtimeUiState {
    var next = self
    next.isGlassesRequested = false
    next.isGlassesSessionLive = false
    next.isSourceLinking = false
    next.isCapturing = false
    next.sourceNotice =
      crossingLost
      ? "The session ended before the photo arrived."
      : parting
    return next
  }
}

/// Drives the real-time session: holds the microphone open for as long as the screen is up, turns
/// what it hears into sonogram columns, and collects everything that lands on the timeline.
///
/// **The session's clock is its own thing** — see ``SessionClock``. Elapsed seconds are a
/// monotonic count from the moment the session opened, and the sonogram is aligned to it rather
/// than being it, so a microphone that stops does not stop time. Every event is stamped here, at
/// the moment it arrives, rather than by whatever produced it: a detector's wall clock starts when
/// the detector does, and the session's starts when the session does.
///
/// It also asks, once, *where*. The fix runs beside the microphone rather than in front of it —
/// see ``stampLocation()``.
///
/// ``observeSession()`` and ``observeCamera()`` are async functions the screen calls from `.task`,
/// not something `init` starts. The session's life is the screen's life and the camera's life is
/// the camera mode's — two cold streams, two cancellations, no `stop()` to forget on either
/// platform.
@MainActor
@Observable
final class RealtimeViewModel {

  private let audioSource: any AudioCaptureSource
  /// The same object as ``audioSource`` when the app is wired for real, kept separately so the
  /// session can ask for the glasses' ears without the rest of the code learning that failover
  /// exists. Nil in previews and tests, where the microphone never changes.
  private let audioFailover: FailoverAudioSource?
  /// The aim readings' failovers, on the same terms as ``audioFailover`` and for the same
  /// reason: the session asks for the wearer's own head without anything above learning that
  /// there are two instruments behind each of these. Nil wherever the providers do not change.
  private let headingFailover: FailoverHeadingProvider?
  private let gazeFailover: FailoverGazeProvider?
  private let previewSource: any CameraPreviewSource
  private let detector: any SessionDetector
  /// The Director's cue-answering half. Kept beside ``detector`` rather than folded into it —
  /// the detector seam is the one a real classifier implements without the session changing,
  /// and the cues (a photo's scripted response, a tapped question) are the demo's own surface.
  /// In the app the two are one object; in a test they need not be.
  private let director: any DemoDirector
  /// For the one thing a cue-landed answer needs that the preset deliberately does not
  /// carry: the bird's name. The catalog is the one source of bird names, and a row whose
  /// id it cannot resolve lands nothing — the same silence the Director keeps.
  private let birdCatalog: any BirdCatalogRepository
  /// Where Save writes the outing. Nothing here touches it until the watcher says so.
  private let journal: any JournalRepository
  private let glassesSession: any GlassesSessionRepository
  private let glassesCamera: any GlassesCameraRepository
  private let glassesInput: any GlassesInputRepository
  /// What the watcher says out loud, for as long as this run has the glasses to hear it with.
  ///
  /// **The one sense with no failover**, and the one feature a phone-only run simply does not
  /// have: recognition happens on the glasses, and there is no second instrument to fall back
  /// on (see ``GlassesSpeechRepository``). A run on the phone subscribes to this and hears
  /// nothing, which is the honest shape of the bargain rather than an error to report.
  private let glassesSpeech: any GlassesSpeechRepository
  /// Where an identification goes when the wearer has somewhere to see it — the bird's
  /// photographs, paged on the glasses themselves. Fire-and-forget from here: a run
  /// with no display simply shows nothing, and the timeline never learns either way.
  private let glassesDisplay: any GlassesDisplayRepository
  /// Where an identification goes when the wearer has somewhere to *hear* it — the row's own
  /// authored line, said into the ear the session is already talking to. Fire-and-forget on
  /// the same terms as ``glassesDisplay``, and quiet on the same terms too: a run with nothing
  /// to speak into says nothing, and the timeline never learns either way. See ``SpokenOutput``.
  private let spokenOutput: any SpokenOutput
  private let locationProvider: any LocationProvider
  private let headingProvider: any HeadingProvider
  private let gazeProvider: any GazeProvider
  private let clock: any SessionClock

  /// The session second past which a transcript can be trusted to be the wearer rather than the
  /// app's own voice coming back — see ``stopListening()``. Zero until the app first speaks,
  /// which is right: nothing has been said yet, so nothing can be echoing.
  private var deafUntil: Double = 0

  /// What the app has said lately, in the words it said them, newest last — see
  /// ``soundsLikeSomethingJustSaid(_:)``. Bounded because only the last few lines can still be
  /// in the air, and stamped because a phrase stops being suspicious once enough time has
  /// passed for the wearer to have chosen it themselves.
  private var recentlySaid: [SpokenLine] = []

  private let analyzer = SonogramAnalyzer()

  /// What the session heard, kept for Save — the strip's twin with a longer memory: same
  /// chunks, same clock, same gap rule, but segments for the journal instead of pixels for
  /// the screen. See ``SessionRecorder``.
  private let recorder = SessionRecorder()

  /// The session's strip. A stable reference the timeline reads directly.
  let sonogram = SonogramBuffer()

  private(set) var uiState: RealtimeUiState

  /// How far into the session the strip is drawing — the window's right edge, and the one thing
  /// here that changes at frame rate. Kept apart from ``uiState`` so that it redraws the strip
  /// and nothing else.
  ///
  /// Published from the clock on a tick rather than from arriving audio. During a gap there is no
  /// audio to publish from, and a strip that stopped scrolling because the microphone dropped is
  /// precisely the bug this replaced.
  private(set) var elapsed: Double = 0

  private(set) var frame: PreviewFrame?

  /// The newest frame, held for the shutter rather than shown.
  ///
  /// A plain property SwiftUI never observes, deliberately: while the layer is drawing the
  /// picture, frames arrive only so a press of the shutter has something to take, and publishing
  /// each one into ``frame`` re-rendered the whole panel thirty times a second to draw nothing.
  /// So ``frame`` carries exactly three things — the first frame (which enables the shutter and
  /// covers the moment before the layer arrives), every frame when there is no layer (previews,
  /// simulated feeds), and the last frame at close (the still the panel dismisses over). This
  /// carries all the rest.
  @ObservationIgnored private var latestFrame: PreviewFrame?

  /// The hardware-path picture, when the source has one — see ``CameraViewfinder``. The panel
  /// draws this when it is here and falls back to ``frame`` when it is not, which is what keeps
  /// SwiftUI previews and simulated feeds drawing without a camera.
  private(set) var viewfinder: CameraViewfinder?

  /// How far the viewfinder is magnified. Apart from ``uiState`` for the same reason ``elapsed``
  /// is: a pinch moves it sixty times a second, and folding that into the state would rebuild
  /// the header, the bearing row and every row of the log along with it.
  private(set) var zoom: Double = 1

  /// How far this camera will go, for the gesture to clamp against.
  var zoomRange: ClosedRange<Double> { previewSource.zoomRange }

  /// The run itself — ``observeSession()``, held here rather than by whichever screen is
  /// showing it. **The session belongs to the app, not to the cover**: a run started by a
  /// voice launch with the phone locked in a pocket has no screen to hold it, and a cover
  /// that closes must not take a session in progress down with it. ``start(onGlasses:)``
  /// opens it; ``stopSession()`` cancels it. Nothing else does.
  @ObservationIgnored private var runTask: Task<Void, Never>?

  /// The one glasses run, when the watcher has asked for it. A task handle rather than a
  /// flag, because cancellation *is* the handle — toggled off, the run
  /// is cancelled mid-flight and ``runGlassesSession()`` resets the pill on its way out.
  /// Dies with the session: ``observeSession()`` cancels it beside the other children.
  @ObservationIgnored private var glassesRun: Task<Void, Never>?

  /// A standing ask from ``startOnGlasses()`` that no session has honoured yet.
  ///
  /// The ask can arrive before the session opens — a voice launch lands while the cover
  /// is still rising — and ``observeSession()``'s reset would cancel a bare run out from
  /// under it. So the ask is latched here and the reset *honours* it instead: whichever
  /// of the two runs first, the session opens reaching for the glasses. Spent the moment
  /// a run starts, so it never outlives the launch that made it.
  @ObservationIgnored private var startOnGlassesRequested = false

  /// Whether ``observeSession()`` currently holds the session open — what
  /// ``startOnGlasses()`` routes on: an ask made against an open session starts its run
  /// now, one made before the open is latched for the open to honour.
  @ObservationIgnored private var isSessionOpen = false

  /// The photograph currently crossing from the glasses, when one is.
  ///
  /// Held for one reason: so the run's teardown can **wait** for it rather than race it — see
  /// ``RealtimeUiState/ending(crossingLost:parting:)``. Nothing cancels it, because a crossing
  /// is ended by the link going down under it, not by dropping the handle.
  @ObservationIgnored private var captureRun: Task<Void, Never>?

  /// The two readings availability is computed from, held so either stream's update can
  /// re-answer the other's half of the question.
  @ObservationIgnored private var latestRegistration: GlassesRegistrationState = .unavailable
  @ObservationIgnored private var latestDevice: GlassesDeviceInfo?

  /// How many photos this session has taken — the index the Director's photo section is
  /// keyed on. The caller owns the count by contract (``DemoDirector/response(toPhotoAt:)``),
  /// and it resets when a session starts, which is also the whole of how a fumbled take
  /// is recovered.
  @ObservationIgnored private var photoIndex = 0

  init(
    audioSource: any AudioCaptureSource,
    previewSource: any CameraPreviewSource,
    detector: any SessionDetector,
    director: any DemoDirector,
    birdCatalog: any BirdCatalogRepository,
    journal: any JournalRepository,
    glassesSession: any GlassesSessionRepository,
    glassesCamera: any GlassesCameraRepository,
    glassesInput: any GlassesInputRepository,
    glassesSpeech: any GlassesSpeechRepository,
    glassesDisplay: any GlassesDisplayRepository,
    spokenOutput: any SpokenOutput,
    locationProvider: any LocationProvider,
    headingProvider: any HeadingProvider,
    gazeProvider: any GazeProvider,
    // Defaulted to nil and resolved in the body rather than defaulted to the clock itself:
    // a default argument is evaluated in a nonisolated context, and building a main-actor
    // clock there is the one thing Swift will not do.
    clock: (any SessionClock)? = nil
  ) {
    self.audioSource = audioSource
    self.audioFailover = audioSource as? FailoverAudioSource
    self.headingFailover = headingProvider as? FailoverHeadingProvider
    self.gazeFailover = gazeProvider as? FailoverGazeProvider
    self.previewSource = previewSource
    self.detector = detector
    self.director = director
    self.birdCatalog = birdCatalog
    self.journal = journal
    self.glassesSession = glassesSession
    self.glassesCamera = glassesCamera
    self.glassesInput = glassesInput
    self.glassesSpeech = glassesSpeech
    self.glassesDisplay = glassesDisplay
    self.spokenOutput = spokenOutput
    self.locationProvider = locationProvider
    self.headingProvider = headingProvider
    self.gazeProvider = gazeProvider
    self.clock = clock ?? MonotonicSessionClock()
    uiState = RealtimeUiState(
      sourceKind: audioSource.kind,
      cameraControls: previewSource.controls
    )
  }

  /// Opens a run, or joins the one in flight.
  ///
  /// **Idempotent while a run is in flight**, which is what lets the cover call it on every
  /// appearance and the shell call it on every voice launch without either knowing about the
  /// other: a launch that lands before the cover is up starts the run, and the cover then
  /// shows the session already going; a launch that lands mid-run only adds the ask for the
  /// glasses. A fresh run clears whatever review the last one left behind.
  ///
  /// `onGlasses` is the voice launch's request — the wearer spoke from the glasses, so the
  /// session should arrive already reaching for them (see ``startOnGlasses()``). Latched
  /// straight onto the fresh run rather than routed through ``startOnGlasses()``, whose
  /// guards are about a session that is already open.
  func start(onGlasses: Bool = false) {
    if isSessionOpen && !uiState.isReviewing {
      if onGlasses { startOnGlasses() }
      return
    }
    runTask?.cancel()
    uiState.review = nil
    startOnGlassesRequested = onGlasses
    runTask = Task { await observeSession() }
  }

  /// Runs the session: the microphone, and whatever is reporting findings alongside it.
  ///
  /// Re-entrant — a second visit is a new session, on a clean strip, rather than the tail of the
  /// last one. The findings are a child of the audio: when the spine stops, for any reason, the
  /// script stops with it.
  ///
  /// Reachable to the tests, which drive a run directly; the app goes through
  /// ``start(onGlasses:)``, which owns the task this runs in.
  func observeSession() async {
    analyzer.reset()
    sonogram.reset()
    recorder.reset()
    // The app's own voice belongs to the run that said it. The clock restarts here, so a line
    // carried across would read as having been said moments from now, for ever.
    recentlySaid.removeAll()
    deafUntil = 0
    clock.start()
    elapsed = 0
    frame = nil
    latestFrame = nil
    viewfinder = nil
    zoom = 1
    glassesRun?.cancel()
    glassesRun = nil
    photoIndex = 0
    uiState = RealtimeUiState(
      sourceKind: audioSource.kind,
      isRunning: true,
      session: RealtimeSession(startedAt: Int64(Date().timeIntervalSince1970 * 1000)),
      cameraControls: previewSource.controls
    )

    isSessionOpen = true

    // A standing ask is honoured the moment the session opens — latched rather than
    // run early, so the reset above cannot cancel it out from under the launch that
    // made it. See ``startOnGlassesRequested``.
    if startOnGlassesRequested {
      startOnGlassesRequested = false
      glassesRun = Task {
        await runGlassesSession()
        glassesRun = nil
      }
    }

    BirdLog.info(.session, "session started — listening on \(audioSource.kind)")

    let findings = Task { await observeFindings() }
    let fix = Task { await stampLocation() }
    let bearing = Task { await observeHeading() }
    let aim = Task { await observeGaze() }
    let ticking = Task { await observeClock() }
    let glasses = Task { await observeGlasses() }

    do {
      for try await chunk in audioSource.audioStream() {
        place(chunk)
        // **The pill follows the audio that arrived**, not the audio that was asked for —
        // see ``AudioChunk/source`` and ``RealtimeUiState/hearing(_:)``.
        uiState = uiState.hearing(chunk.source)
      }
    } catch {
      BirdLog.error(.session, "session ended on a failed microphone", error)
      uiState = uiState.failed(error)
    }

    findings.cancel()
    fix.cancel()
    bearing.cancel()
    aim.cancel()
    ticking.cancel()
    glasses.cancel()
    glassesRun?.cancel()
    glassesRun = nil
    isSessionOpen = false
    uiState.isRunning = false
  }

  /// Draws a chunk onto the strip at the column the session was at when it was heard.
  ///
  /// Only a real gap moves the write head — see ``placement(clockColumn:written:)`` — and when
  /// one does, the silence lands on the strip at the second it actually happened rather than
  /// being closed up as though the session had been shorter.
  private func place(_ chunk: AudioChunk) {
    // **The write head moves first, and it moves even while the app is talking.** Everything
    // below this line is skipped for the length of an announcement; this is not, because the
    // head is what says where *now* is. Left where it was, the strip's newest column would be
    // the last one before the app started speaking — so the live trace would go on drawing
    // that column's shape, holding a picture of the last bird for as long as the sentence
    // lasts. Advancing writes cleared columns instead: the trace falls flat, which is what
    // the wearer's own microphone actually had in it.
    sonogram.advance(to: placement(clockColumn: clock.column, written: sonogram.count))
    // **The session stops listening while the app is talking.** A spoken line comes back down
    // whichever microphone is open — the glasses' speakers sit beside their microphones, and a
    // phone speaker sits inches from a phone microphone — so analysing through an announcement
    // would put the app's own voice on the strip and record it into the outing. Dropping the
    // chunks leaves a hole exactly as long as the line, which is what the announcement was: not
    // birdsong. See ``SpokenOutput``.
    guard !spokenOutput.isSpeaking else { return }
    for column in analyzer.analyze(chunk) { sonogram.append(column) }
    // The recorder hears everything the strip draws — but nothing after the stop: a chunk
    // still crossing when the review opens belongs to the closing microphone, not the
    // outing, whose duration the stop already read off the clock.
    if !uiState.isReviewing { recorder.record(chunk, atSeconds: clock.elapsed) }
  }

  /// Tells the strip that now has moved, about once a frame.
  ///
  /// A redraw rather than a measurement: nothing is stamped from this, and what it publishes is
  /// the clock's own reading taken fresh. It exists because during a gap in the audio there is
  /// nothing else to say the window has scrolled.
  private func observeClock() async {
    while !Task.isCancelled {
      elapsed = clock.elapsed
      try? await Task.sleep(for: timelineTick)
    }
  }

  /// Runs the camera, for as long as the camera mode is open. Called from the screen alongside
  /// ``observeSession()``, never instead of it — a session does not stop listening to take a
  /// picture.
  func observeCamera() async {
    // The picture, riding beside the frames. A child rather than a sibling call from the
    // screen, so the two cannot outlive each other — cancelled below when the frames end.
    let picture = Task {
      for await viewfinder in previewSource.viewfinderStream() {
        self.viewfinder = viewfinder
      }
    }

    do {
      for try await frame in previewSource.previewStream() {
        latestFrame = frame
        // Published only while the UI is actually drawing frames — see ``latestFrame``.
        if viewfinder == nil || self.frame == nil { self.frame = frame }
      }
    } catch {
      // A camera that will not open closes the mode rather than ending the session. The
      // viewfinder is the optional half; losing it is not losing the run.
      closeCamera()
    }

    picture.cancel()
  }

  func openCamera() {
    // Cleared here rather than on the way out: while the panel is closing it is still on screen,
    // and a viewfinder that blanked to its placeholder mid-animation was the jank. By the time
    // this runs the old picture has been gone for as long as the panel has.
    frame = nil
    latestFrame = nil
    uiState.isCameraOpen = true
  }

  func closeCamera() {
    uiState.isCameraOpen = false

    // The light is never left on — it is only ever on for the moment a photo is being taken,
    // and if a capture is cut short this is what puts it out.
    previewSource.setTorch(false)

    // A viewfinder that reopened at 5× would look broken. The *flash* setting is not reset with
    // it: that is a preference, not a running light.
    if zoom != 1 {
      zoom = 1
      previewSource.setZoom(1)
    }

    // The last picture, stamped into state *before* the layer goes: the panel falls back to
    // drawing ``frame`` the instant ``viewfinder`` empties, and without this it would fall back
    // to whatever the state last carried — the stale first frame, from a camera whose layer has
    // been the picture ever since. With it, the panel dismisses over the still it just showed.
    if let latestFrame { frame = latestFrame }

    // The layer itself dies with the camera — the source finishes its stream the moment the
    // frames stop, so keeping the handle would be keeping a dead one.
    viewfinder = nil
  }

  /// Arm the flash, or disarm it. Nothing lights up until the shutter fires.
  func toggleFlash() {
    uiState.isFlashOn.toggle()
  }

  /// Magnify, clamped to what this camera will actually do.
  func setZoom(_ factor: Double) {
    let range = previewSource.zoomRange
    zoom = min(max(factor, range.lowerBound), range.upperBound)
    previewSource.setZoom(zoom)
  }

  /// Magnify by a step — what a pinch that reports *change* rather than *total* hands over.
  ///
  /// The multiplication happens here rather than at the gesture, and that is not a style
  /// preference: a screen that computed `zoom * step` from its own observed copy of `zoom` would
  /// be multiplying against whatever the last recomposition saw, so several gesture events inside
  /// one frame would all start from the same stale number. The zoom then advances once per redraw
  /// instead of once per event, which is exactly what a pinch moving in steps looks like.
  func zoomBy(_ step: Double) {
    setZoom(zoom * step)
  }

  /// The pill's tap. Phone → glasses is a request — the session must *arrive* before the
  /// pill flips; glasses → phone is immediate — hanging up needs nobody's permission. The
  /// phone's camera panel closes on the way over: the panel is the phone's viewfinder,
  /// and the glasses have none.
  func toggleSource() {
    // **Hanging up is the pill's only power over a running session.** A paused session is
    // the device's to resume — the SDK is explicit that an app must not restart one — so
    // while paused this ends the run rather than pretending to revive it. Tapping the side
    // of the glasses is what picks it back up.
    if glassesRun != nil || uiState.sourceKind == .glasses {
      glassesRun?.cancel()
      glassesRun = nil
      return
    }
    guard uiState.isGlassesAvailable else { return }
    if uiState.isCameraOpen { closeCamera() }
    uiState.sourceNotice = nil
    glassesRun = Task {
      await runGlassesSession()
      glassesRun = nil
    }
  }

  /// Reaches for the glasses without a tap on the pill — the voice launch's half of
  /// ``toggleSource()``. "Hey Meta, open BirdSpotter" is spoken *from* the glasses, so
  /// the session it opens should arrive already asking for them.
  ///
  /// **It only ever asks; it never hangs up.** A repeat — the launch replayed, the wearer
  /// asking again mid-run — finds the ask already made and changes nothing, which is the
  /// difference from the pill: a control under a thumb needs an off, a spoken open does
  /// not.
  ///
  /// **And it deliberately skips the pill's ``RealtimeUiState/isGlassesAvailable``
  /// gate.** A voice launch lands moments after the app does, before the registration and
  /// device streams have said anything, and a request gated on them would lose the race
  /// it exists to win. ``runGlassesSession()`` holds the honest gates — the grant, and a
  /// pair that answers — and its notices explain a launch the glasses could not carry.
  ///
  /// Safe to call before the session opens: the ask is latched and ``observeSession()``
  /// honours it on the way in — see ``startOnGlassesRequested``.
  func startOnGlasses() {
    if glassesRun != nil || startOnGlassesRequested || uiState.sourceKind == .glasses {
      return
    }
    if uiState.isCameraOpen { closeCamera() }
    uiState.sourceNotice = nil
    guard isSessionOpen else {
      startOnGlassesRequested = true
      return
    }
    glassesRun = Task {
      await runGlassesSession()
      glassesRun = nil
    }
  }

  /// Puts a photograph onto the timeline, at this moment in the session — the shutter's
  /// whole job, on either device.
  ///
  /// On the phone that is the frame currently on screen, and nothing happens without one:
  /// a shutter pressed before the camera has answered should do nothing rather than drop
  /// a hole in the timeline. On the glasses it is ``captureThroughGlasses()`` — an ask
  /// and an arrival, no frame of ours involved.
  func capturePhoto() {
    // **One press at a time, on either device** — see ``RealtimeUiState/isCapturing``. The
    // guard is here rather than in the two paths below so that neither can forget it, and
    // so a shutter pressed twice is one photograph on both of them.
    guard !uiState.isCapturing else { return }

    // Routed on the *session*, not the pill: the eyes and the ears can honestly differ for
    // a beat, and a photograph should go through the glasses whenever they can take one.
    if uiState.isGlassesSessionLive {
      captureThroughGlasses()
      return
    }
    guard latestFrame != nil else { return }
    guard uiState.isFlashOn else {
      commitCapture()
      return
    }
    Task { await captureLit() }
  }

  /// The shutter, when the session is riding the glasses: ask, and the photograph arrives
  /// a moment later.
  ///
  /// **The row is stamped at the press; only the picture waits.** The Bluetooth crossing is a
  /// real beat — about a second, sometimes several — and the feature brief is explicit that
  /// it should be designed rather than hidden. It used to be shown as the shutter dimming and
  /// nothing else, which left the log perfectly still for the whole crossing: the one moment
  /// the watcher most wants an answer about, and the screen's answer was to grey out the
  /// control they just pressed. A dimmed button reads as *broken*, not as *working*.
  ///
  /// So the capture lands on the timeline immediately, as a row with no picture in it yet, and
  /// the crossing is drawn where the crossing is happening — on the photograph's own row, in
  /// the same place its identification will appear a moment later. The press has a visible
  /// consequence at the instant it happens, which is the whole of what was missing.
  ///
  /// Stamped at the press rather than at the arrival for the same reason, and it is the more
  /// honest number besides: the photograph is of the second the shutter fired, not of the
  /// second Bluetooth finished. It also means the row never moves — a row inserted at press
  /// time and re-stamped on arrival would jump down the log past anything the microphone heard
  /// in between.
  ///
  /// The Director is asked only once the picture is real — see ``askDirector(aboutPhotoAt:)``.
  private func captureThroughGlasses() {
    uiState.isCapturing = true

    // The index is claimed now, because the row that carries it exists now. The Director's
    // photo section is keyed on it either way, and claiming it at the press is what lets the
    // arrival find its way back to this row.
    let index = photoIndex
    photoIndex += 1

    // The moment rides only a phone photo — the aim must come from the same device as the
    // capture, and the glasses report no gaze to aim by.
    record(
      .photo(
        at: clock.elapsed,
        index: index,
        image: nil,
        source: .glasses,
        gazeContext: nil,
        bearingDeg: nil,
        identification: nil
      )
    )

    captureRun = Task {
      defer { uiState.isCapturing = false }
      do {
        let photo = try await glassesCamera.capturePhoto(format: .jpeg)
        if let image = uprightImage(from: photo.imageData) {
          landPhoto(image, at: index)
        } else {
          discardPhoto(at: index)
          uiState.sourceNotice = "The photo arrived unreadable."
        }
      } catch {
        discardPhoto(at: index)
        uiState.sourceNotice = "The photo didn't make it from the glasses."
      }
    }
  }

  /// The picture, arriving into the row that has been waiting for it — and only then the
  /// question of what is in it.
  ///
  /// **The Director is asked here rather than at the press**, so that a scripted answer with a
  /// short delay cannot overtake the photograph it is about. A response composed during the
  /// crossing would land on a row that is still an empty tile, which reads as the app naming a
  /// bird in a picture nobody has seen.
  private func landPhoto(_ image: CGImage, at index: Int) {
    // A stopped timeline takes nothing more, not even a picture it was already carrying a
    // row for — the review shows what the session held when it ended, and ``stopSession()``
    // has already taken the empty row away.
    guard !uiState.isReviewing else { return }
    uiState.session = uiState.session.resolvingPhoto(index: index, toImage: image)
    askDirector(aboutPhotoAt: index)
  }

  /// A crossing that failed, taking its row with it. See
  /// ``RealtimeSession/discardingPhoto(index:)`` for why the row leaves rather than staying.
  private func discardPhoto(at index: Int) {
    guard !uiState.isReviewing else { return }
    uiState.session = uiState.session.discardingPhoto(index: index)
  }

  /// The glasses' bytes, decoded into the upright buffer the rest of the app assumes.
  ///
  /// **The rotation is in the EXIF, and `.cgImage` is where it gets lost.** A photograph off
  /// the glasses arrives in sensor order with an `Orientation` tag describing the turn;
  /// `UIImage(data:)` reads that tag into `imageOrientation`, but `.cgImage` hands back the
  /// raw buffer underneath it, and every drawing site in this app renders a `CGImage` as
  /// `.up` (``SessionTimeline``, ``SessionReviewScreen``). Taking the `CGImage` straight off
  /// the decode is therefore a photograph shown on its side.
  ///
  /// Redrawing bakes the turn into the pixels, which is the same bargain the phone makes one
  /// layer lower — ``PhoneCameraPreviewSource`` asks its capture connection for 90° so frames
  /// arrive upright rather than carrying an angle downstream. Each source normalises at its
  /// own edge; this is the glasses' edge.
  ///
  /// Needed because the capability hands this side the encoded bytes with their EXIF
  /// orientation still unapplied. Where an SDK returns an already-turned bitmap there is
  /// nothing to bake, and the asymmetry is the SDK's rather than the app's.
  private func uprightImage(from data: Data) -> CGImage? {
    guard let image = UIImage(data: data) else { return nil }
    // Nothing to bake in, and a redraw would only cost a copy.
    guard image.imageOrientation != .up else { return image.cgImage }

    // `size` is already the turned size — a sideways capture reports the swapped edges —
    // so drawing at the origin lands the whole frame. Scale 1 keeps the sensor's pixels
    // rather than stretching them to the screen's.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in image.draw(at: .zero) }.cgImage
  }

  /// A photo taken with the light on.
  ///
  /// **The wait is the whole thing.** Lighting the torch and grabbing the very next frame gets a
  /// picture of the scene as it was a moment *before* the light — auto-exposure and auto-white
  /// balance both need a beat to answer it, and without one the flash shows up as a brighter
  /// version of the same underexposed frame. ``flashSettle`` is that beat.
  ///
  /// The panel stays open across it on purpose: what the watcher sees is the light coming on, the
  /// picture brightening, and *then* the panel leaving — which is the sequence that says a flash
  /// fired rather than one that says the app hesitated.
  /// The settle is held under ``RealtimeUiState/isCapturing`` for the same reason the crossing
  /// is: two presses inside it would light the torch twice, race the two settles against each
  /// other for when to put it out, and land two photographs of one moment.
  private func captureLit() async {
    uiState.isCapturing = true
    defer { uiState.isCapturing = false }
    previewSource.setTorch(true)
    try? await Task.sleep(for: flashSettle)
    commitCapture()
    previewSource.setTorch(false)
  }

  private func commitCapture() {
    guard let image = latestFrame?.image else { return }
    recordPhoto(image)
    closeCamera()
  }

  /// A photograph landing on the timeline whole — the phone's shutter, which has its frame
  /// already and so has no crossing to wait through.
  ///
  /// The glasses' two halves are ``captureThroughGlasses()`` and ``landPhoto(_:at:)``; both
  /// end at ``askDirector(aboutPhotoAt:)``, which is the one place a capture becomes a cue.
  ///
  /// The moment rides the photo, and only a phone photo has one: the aim must come from
  /// the same device as the capture, and the glasses report no gaze to aim by — a phone
  /// hanging in a lowered hand knows nothing about where the wearer was looking. Which is
  /// why this takes no `source`: it is the phone's, and the aim it stamps is unconditional
  /// because of it.
  private func recordPhoto(_ image: CGImage) {
    let state = uiState

    // The Nth capture gets the Nth response — see ``DemoDirector/response(toPhotoAt:)``.
    // The count advances whether or not anything is armed: arming a preset mid-session
    // should not make the next photo replay a row an unarmed capture already spent.
    let index = photoIndex
    photoIndex += 1

    record(
      .photo(
        at: clock.elapsed,
        index: index,
        image: image,
        source: .phone,
        gazeContext: state.elevationBand,
        bearingDeg: state.heading,
        identification: nil
      )
    )
    askDirector(aboutPhotoAt: index)
  }

  /// What the Director makes of the `index`th capture, asked at the moment the photograph is
  /// real — the cue its photo section answers to.
  ///
  /// The wait is only shown when something is genuinely on its way. A capture with no scripted
  /// answer is a photograph and nothing more, and a row that spun forever beside one would be
  /// the screen promising an answer nobody is composing.
  private func askDirector(aboutPhotoAt index: Int) {
    guard let response = director.response(toPhotoAt: index) else { return }
    resolvePhoto(index, to: .pending)
    let sessionKey = uiState.session.startedAt
    Task { await deliverPhotoResponse(response, sessionKey: sessionKey, photoIndex: index) }
  }

  /// The landing half of the STT lane: the preset's line, after its composing delay, with
  /// the linked bird — when the row carries one — riding alongside it as a real
  /// identification. One event, because they are one moment of the app speaking; the bird
  /// has **no confidence**, deliberately: the app did not guess, the watcher described it.
  ///
  /// Fired by ``listenForQuestions()`` when the glasses hear an utterance that matches an
  /// authored prompt. There is deliberately no tap-to-fire stand-in: a scripted exchange the
  /// presenter triggered by touch would fake the *input* too, and the Director only ever
  /// fakes answers.
  ///
  /// `heard` is what the watcher actually said, when anything did — which is what the journal
  /// keeps rather than the authored prompt that happened to match it. Nil where nothing was
  /// heard, and then the prompt stands in.
  ///
  /// Kept internal so the mirrored tests can pin the landing — and the QA exchange it
  /// becomes at Save — the same seam ``deliverPhotoResponse(_:sessionKey:)`` keeps.
  func deliverAnswer(
    _ question: DemoQuestion,
    sessionKey: Int64,
    heard: String? = nil
  ) async {
    try? await Task.sleep(for: .milliseconds(question.delayMillis))
    guard isSameRun(sessionKey) else { return }
    // A linked id the catalog cannot resolve falls back to a words-only reply — the
    // same silence the Director keeps, and better than a card naming nobody.
    var name: String?
    if let speciesId = question.speciesId {
      name = await commonName(speciesId)
    }
    record(
      .answer(
        at: clock.elapsed,
        text: question.answer,
        question: heard ?? question.prompts.first,
        speciesId: name != nil ? question.speciesId : nil,
        commonName: name
      )
    )
    if name != nil, let speciesId = question.speciesId {
      showOnGlassesDisplay(speciesId)
    }
    // The answer is the one line the app says or shows, so the exchange the watcher started
    // out loud is finished out loud — there is no second field to author for a question, and
    // a reply that only appeared on a phone in a pocket would not be a reply.
    announce(question.answer)
  }

  /// The scripted response to a photo, after its authored delay — landing **on the photo it
  /// answers**, at `photoIndex`, rather than as a row of its own further down the log.
  ///
  /// A species lands as the bird itself; *no identification* lands as the row's caption — the one
  /// answer where the words are the whole of what the app has to say; an ambiguity lands as the
  /// question it is, for the STT section to settle. A species the catalog cannot resolve resolves
  /// to **nothing** — the same silence the Director's ambient path keeps, except that here the
  /// silence has to be delivered: the photo is sitting on the log with its dots running, and
  /// clearing them is how it stops waiting for a row that is never coming.
  func deliverPhotoResponse(
    _ response: DemoPhotoResponse,
    sessionKey: Int64,
    photoIndex: Int
  ) async {
    try? await Task.sleep(for: .milliseconds(response.delayMillis))
    guard isSameRun(sessionKey) else { return }
    var identification: PhotoIdentification?
    switch response.result {
    case let .species(speciesId, confidence):
      if let name = await commonName(speciesId) {
        identification = .bird(
          speciesId: speciesId,
          commonName: name,
          confidence: Float(confidence)
        )
      }

    case let .ambiguous(candidateIds):
      var names: [String] = []
      for id in candidateIds {
        guard let name = await commonName(id) else {
          names = []
          break
        }
        names.append(name)
      }
      if !names.isEmpty {
        identification = .words(names.joined(separator: " or ") + "?")
      }

    case .noIdentification:
      let caption = response.caption
      if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        identification = .words(caption)
      }
    }
    resolvePhoto(photoIndex, to: identification)
    // Only a named bird goes up: an ambiguity is a question, and a question on a
    // surface with no way to answer it is just a bird the app refuses to commit to.
    if case let .bird(speciesId, _, _)? = identification {
      showOnGlassesDisplay(speciesId)
    }
    // The spoken line is the row's, not the result's: it is said whatever the capture came
    // back with, including nothing. "Not enough to go on" is worth hearing by a watcher who
    // is still holding the shutter, and the row that runs off the end of the script authors
    // no line at all — which is how it stays silent.
    announce(response.spokenLine)
  }

  /// Fills a waiting photo's answer in, or clears its wait. The session's own guard again: a
  /// timeline that has stopped takes nothing more, not even the resolution of something it was
  /// already carrying — the review shows what the session held when it ended.
  private func resolvePhoto(_ photoIndex: Int, to identification: PhotoIdentification?) {
    guard !uiState.isReviewing else { return }
    uiState.session = uiState.session.resolvingPhoto(index: photoIndex, to: identification)
  }

  /// Whether a delayed cue still belongs to the session on screen: same run, still
  /// recording. A response composed across a stop, or across a fresh session, lands
  /// nowhere — a stopped timeline takes nothing more.
  private func isSameRun(_ sessionKey: Int64) -> Bool {
    !uiState.isReviewing && uiState.session.startedAt == sessionKey
  }

  private func commonName(_ speciesId: String) async -> String? {
    guard let found = try? await birdCatalog.findById(speciesId) else { return nil }
    return found.species.commonName
  }

  /// The identified bird, put where the wearer is already looking — its catalog
  /// photographs, paged on the glasses. Every identification lands here, whatever asked
  /// the question: the microphone, a photograph, the wearer's own description.
  ///
  /// Fire-and-forget, deliberately. The timeline is the record and it is already written;
  /// the display is a courtesy, and neither a pair with no display nor a slug the catalog
  /// cannot resolve is worth holding anything up for — both simply show nothing.
  private func showOnGlassesDisplay(_ speciesId: String) {
    Task { [birdCatalog, glassesDisplay] in
      guard let bird = try? await birdCatalog.findById(speciesId) else {
        // The one silent way a push could end before it began — worth a line, because
        // from the screen it is indistinguishable from a send that fell off the link.
        BirdLog.warning(
          .glasses,
          "display — \(speciesId) is not in the catalog, so there is no card to send"
        )
        return
      }
      // docs:display-gallery:begin
      await glassesDisplay.showGallery(for: bird)
      // docs:display-gallery:end
    }
  }

  /// A bird already on the timeline, put back on the display — the log's own tap.
  ///
  /// **What it is for is the second look.** A card is replaced by the next identification and
  /// cleared by the stop, and neither of those asks the wearer whether they were finished
  /// reading. Three birds in a minute is three cards, of which the wearer saw the last one; the
  /// timeline is the record of the other two, and this is what makes that record reach the
  /// glass again. It sends the same card the arrival sent — the identification is not re-made,
  /// it is re-shown.
  ///
  /// **A control is a promise, so this one is never refused.** ``showOnGlassesDisplay(_:)``
  /// fires at every identification and asks nobody, because a send with nowhere to land costs
  /// nothing — an automatic push may land nowhere and the wearer is none the wiser. A press is
  /// different: the watcher asked, and *nothing happened* is the one answer a row must not
  /// give. So where there is glass the card goes up there, and where there is not it opens on
  /// the phone in the same layout — see ``RealtimeUiState/cardOnPhone``. Most pairs have no
  /// display and most demos have no pair; a tap that only worked on the best hardware in the
  /// room would be a control that works when the demo is already going well.
  ///
  /// ``RealtimeUiState/cardGoesToGlasses`` is re-read here rather than trusted from the draw,
  /// so a pair that left the room between the two lands its card on the phone.
  func showCard(_ speciesId: String) {
    if uiState.cardGoesToGlasses {
      BirdLog.debug(.glasses, "card — tap for \(speciesId), routed to the glasses")
      showOnGlassesDisplay(speciesId)
      return
    }
    // The gates behind the route, spelled out: which one said no is the whole diagnosis
    // when a card the watcher expected on the glass opens down here instead.
    BirdLog.debug(
      .glasses,
      "card — tap for \(speciesId), routed to the phone"
        + " (display available: \(uiState.isDisplayAvailable),"
        + " glasses session live: \(uiState.isGlassesSessionLive))"
    )
    // No glass to draw on — so the card is drawn here instead, in the layout it would have
    // had up there. A row that only answered on some pairs would be a control that works
    // when the demo is going well.
    Task { [birdCatalog] in
      guard let bird = try? await birdCatalog.findById(speciesId) else { return }
      uiState.cardOnPhone = bird
    }
  }

  /// Puts the phone's card away. The glasses' card has no equivalent — see
  /// ``RealtimeUiState/cardOnPhone``.
  func dismissCard() {
    uiState.cardOnPhone = nil
  }

  /// The row's own words, said where the wearer will hear them — the display's twin for the
  /// ear, and the other half of *the phone stamps the identification and the glasses answer*.
  ///
  /// **A line is authored, never composed.** What is said is what the preset's row was given to
  /// say, so an operator who wants the app to speak writes the sentence and an operator who
  /// does not leaves the field empty — the same bargain the Director makes everywhere else.
  /// There is no "speak: on/off" switch, because *whether* is not the app's decision either: a
  /// line is always handed over and lands nowhere when there is no ear in reach.
  ///
  /// Fire-and-forget for the same reason the display is. The timeline is the record and it is
  /// already written; this is a courtesy, and a session must not wait on one.
  private func announce(_ words: String?) {
    guard let words,
      !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    // **Deaf from the moment the line is handed over**, not from the moment the synthesiser
    // gets around to it: the gap between the two is a window the app can hear itself through,
    // and one utterance through it is enough to start the loop over. See ``stopListening()``.
    stopListening(words)
    // docs:spoken-line:begin
    Task { [spokenOutput, weak self] in
      await spokenOutput.speak(words)
      // And again on the way out, because the transcript of what was just said has not
      // arrived yet — the recogniser is still waiting for the silence that ends it. The
      // line itself is already remembered; only the window is pushed back.
      self?.stopListening()
    }
    // docs:spoken-line:end
  }

  /// Shuts the question lane for as long as the app's own voice could still come back through
  /// it.
  ///
  /// **The app talks to the wearer through the same pair of glasses it listens to them with**,
  /// and the on-device recogniser cannot tell the two voices apart. Left alone that is not a
  /// glitch but a *loop*: a line goes out, comes back as an utterance, matches nothing, and
  /// earns the "didn't catch that" line — which goes out, comes back, and matches nothing. It
  /// sustains itself indefinitely and it fills the log while it does.
  ///
  /// Two things close the window, because neither is enough alone. ``SpokenOutput/isSpeaking``
  /// covers the line while it is in the air, and this stamp covers the tail after it: the
  /// recogniser does not deliver a final until the utterance has been quiet for a beat, so the
  /// echo of a line lands *after* the line has finished playing.
  ///
  /// The cost is that a wearer who answers the instant the app stops talking is not heard,
  /// which is the right side of the trade: a question can be asked again, and a loop cannot be
  /// talked over.
  private func stopListening(_ line: String? = nil) {
    deafUntil = clock.elapsed + echoTailSeconds
    guard let line else { return }
    let words = Self.spokenWords(in: line)
    guard !words.isEmpty else { return }
    recentlySaid.append(SpokenLine(words: words, at: clock.elapsed))
    if recentlySaid.count > recentlySaidLimit {
      recentlySaid.removeFirst(recentlySaid.count - recentlySaidLimit)
    }
  }

  /// Whether a transcript arriving now is the app's own voice rather than the wearer's.
  ///
  /// **Three questions, because the window alone was not enough.** The first run with the guard
  /// still looped: the app answered, the tail expired, and the echo arrived a second later — a
  /// recogniser holds an utterance open until it has heard silence and only then delivers, so
  /// how late an echo lands is a property of the room rather than a number this app can pick.
  ///
  /// The third question is the one that does not depend on timing at all: **the app knows
  /// exactly what it just said.** A transcript that is mostly the words of a line the app spoke
  /// moments ago is that line coming back, whenever it happens to arrive — which is how
  /// *"That's likely a green day."* is recognised as *"That's likely a Green Jay."* despite the
  /// recogniser having misheard a word of it.
  private func isHearingItself(_ transcript: String) -> Bool {
    spokenOutput.isSpeaking
      || clock.elapsed < deafUntil
      || soundsLikeSomethingJustSaid(transcript)
  }

  /// Whether these words are mostly a line the app has just spoken.
  ///
  /// **Most of the words, not all of them, because an echo is misheard on its way back.** The
  /// recogniser is listening to a synthesiser through a Bluetooth microphone, and it gets a
  /// word wrong — *jay* for *day* — which is exactly enough to defeat comparing the two
  /// strings. Counting how much of what was heard was also in what was said survives that.
  ///
  /// **The line is drawn at length, and that is the honest cost of this check.** An utterance
  /// made only of words the app just said is genuinely ambiguous — the wearer picking the
  /// bird's name back up is the same string as the echo of it. Under ``echoMinimumWords`` is
  /// let through and answered; a longer verbatim repeat is taken for the echo it usually is.
  /// That trades a rare lost question for a loop, which is the right way round.
  private func soundsLikeSomethingJustSaid(_ transcript: String) -> Bool {
    let heard = Self.spokenWords(in: transcript)
    guard heard.count >= echoMinimumWords else { return false }
    let now = clock.elapsed
    return recentlySaid.contains { said in
      let age = now - said.at
      guard age >= 0, age <= echoMemorySeconds else { return false }
      let shared = heard.count { said.words.contains($0) }
      return Double(shared) / Double(heard.count) >= echoWordOverlap
    }
  }

  /// A line as the words it is made of, punctuation and casing dropped — so a transcript and
  /// the sentence it echoes are comparable word for word.
  private static func spokenWords(in line: String) -> [String] {
    let kept = line.lowercased().map { character -> Character in
      character.isASCII && (character.isLetter || character.isNumber) ? character : " "
    }
    return String(kept).split(separator: " ").map(String.init)
  }

  private func observeFindings() async {
    do {
      for try await finding in detector.findingStream() {
        record(finding.at(clock.elapsed))
        if case let .bird(speciesId, commonName, confidence, spokenLine) = finding {
          showOnGlassesDisplay(speciesId)
          // The one lane whose words are composed rather than authored, unless the
          // finding brought its own — see ``heardAloud(commonName:confidence:)``.
          // Hands-free is the whole premise of the ambient path, and a watcher with
          // their eyes on a hedge is exactly the person who should not have to look at
          // a phone to find out what just called.
          announce(spokenLine ?? heardAloud(commonName: commonName, confidence: confidence))
        }
      }
    } catch {
      // A script that cannot run leaves a session that still listens. There is nothing to
      // say to the user about a fake that stopped faking.
    }
  }

  /// Asks the GPS once, for where the session is being run.
  ///
  /// Alongside the microphone rather than before it: a first fix can take seconds and a session
  /// that would not start listening until the sky had been found would miss the bird it was
  /// opened for. Nothing downstream waits on this — a session with no fix is a session that
  /// simply carries no coordinates.
  private func stampLocation() async {
    let fix = await locationProvider.currentCoordinate()
    guard !Task.isCancelled else { return }
    uiState.coordinate = fix
  }

  /// Follows the compass for as long as the session runs.
  ///
  /// A stream rather than the single fix ``stampLocation()`` takes, because a heading is only
  /// true while the watcher is standing that way. Nothing is recorded onto the timeline from it:
  /// this says where they are looking *now*, and a bearing from four minutes ago is not a fact
  /// worth keeping.
  private func observeHeading() async {
    for await bearing in headingProvider.headingStream() {
      uiState.heading = bearing
    }
  }

  /// Follows the tilt for as long as the session runs, the way ``observeHeading()`` follows the
  /// turn.
  ///
  /// Live for the same reason, and recorded for the same reason — which is to say not at all.
  /// Where someone was aiming is a fact about the second they were aiming there; a stratum from
  /// four minutes ago says nothing about the bird now in front of them.
  private func observeGaze() async {
    for await elevation in gazeProvider.gazeStream() {
      uiState.elevation = elevation
    }
  }

  /// The glasses side of the session: watches whether a pair could take it, and holds
  /// the availability the pill reads. The run itself is ``glassesRun`` — started by the
  /// toggle, cancelled by it, and cancelled with the session like every other child.
  /// Reachable to its tests, the way ``observeCamera()`` and ``routeGlassesInput()`` are: what
  /// this observer decides — whether the pill may be thrown, and what the battery glance says —
  /// is only observable by driving it.
  func observeGlasses() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await state in self.glassesSession.registrationStateStream() {
          await self.setRegistration(state)
        }
      }
      group.addTask {
        for await device in self.glassesSession.deviceInfoStream() {
          await self.setNearbyDevice(device)
        }
      }
    }
  }

  private func setRegistration(_ state: GlassesRegistrationState) {
    latestRegistration = state
    refreshGlassesAvailability()
  }

  private func setNearbyDevice(_ device: GlassesDeviceInfo?) {
    latestDevice = device
    refreshGlassesAvailability()
  }

  private func refreshGlassesAvailability() {
    let isReachable = latestRegistration == .registered && latestDevice?.isAvailable == true
    uiState.isGlassesAvailable = isReachable
    // **Every reading below is gated on the pair being reachable**, rather than read straight
    // off the snapshot, so the glance goes quiet with the pair instead of leaving the last
    // thing it saw on screen. A charge from before the glasses went out of range is the one
    // reading worth nothing.
    let reading = isReachable ? latestDevice : nil
    uiState.glassesBattery = reading?.batteryLevel
    // The same gate and the same reason: *worn* read off a pair that has gone out of range
    // is a claim about somebody's face from before they left the room.
    uiState.isGlassesWorn = reading?.isWorn
    // And again: a display nothing can reach must stop offering the send it was offering a
    // moment ago.
    uiState.isDisplayAvailable = reading?.hasDisplay == true
  }

  /// One glasses session, from toggle to hang-up.
  ///
  /// Each state the device reports is applied by ``RealtimeUiState/applying(_:)``, which
  /// holds the rule about what the pill may claim. Every way out — toggle back, doff,
  /// hinge, failure — funnels through the reset at the bottom, which puts the session
  /// back on the phone and leaves behind at most one line about why.
  private func runGlassesSession() async {
    // The pill goes to `Linking` now, before anything is asked of the pair, because the
    // first thing asked of it may be waiting — see below.
    uiState.isGlassesRequested = true
    uiState.isSourceLinking = true
    uiState.sourceNotice = nil

    // **The pair is waited for before it is asked anything.** A voice launch lands
    // moments after the app does, while the pair is still listed as disconnected; its
    // link comes up a few seconds later, and until it does the grant below is unreadable
    // and a session cannot be opened on it. Asked at once, every launch from a cold start
    // ended on the phone with a notice about glasses that were on the wearer's face. So
    // the run holds on `Linking` until the snapshot says the pair is reachable, and a pair
    // that never arrives is the same answer as one that does not respond.
    guard await awaitGlassesReachable() else {
      // A reach that was cancelled rather than refused says nothing.
      giveUpReaching(
        Task.isCancelled
          ? nil
          : "Your glasses aren't answering — unfold them and check they're in range."
      )
      return
    }

    // Two ways to fail this gate, and they send the wearer to different places. A
    // denial is a trip to Settings; an *unreadable* grant means DAT could not reach a
    // pair to ask, and Settings has nothing to offer — the glasses do.
    switch await glassesSession.access(.camera) {
    case .granted:
      break
    case .denied:
      giveUpReaching("Allow camera access in Settings → Meta AI Glasses first.")
      return
    case .unknown:
      giveUpReaching("Your glasses aren't answering — unfold them and check they're in range.")
      return
    }

    // The shutter on the temple, for as long as this run holds the glasses. Its own child
    // rather than a branch of the loop below, because the session stream speaks only when
    // the session's *state* changes — and a press is not a state.
    let inputRun = Task { [weak self] in await self?.routeGlassesInput() }
    defer { inputRun.cancel() }

    // And the answer to the one thing this run asks for that nothing else reports on: whether
    // the glasses' microphone was actually to be had. Scoped to the run, so a loss arriving
    // after the hang-up finds nobody listening.
    let earsRun = Task { [weak self] in await self?.watchGlassesEars() }
    defer { earsRun.cancel() }

    // And the watcher's own voice, on the same terms as the shutter: its own child, because
    // an utterance is not a session state either, and scoped to the run because a question
    // asked of a session that has ended has nobody left to answer it.
    let questionsRun = Task { [weak self] in await self?.listenForQuestions() }
    defer { questionsRun.cancel() }

    // What is left on screen once this is over. Assigned at the end rather than in the
    // `catch`, so a session that paused and then stopped does not keep explaining the
    // pause it already recovered from.
    var parting: String?
    do {
      // docs:glasses-session-state:begin
      for try await state in glassesSession.sessionStream() {
        uiState = uiState.applying(state)
        // The ears follow the session: asked for on `started`, handed back on any
        // pause or stop. The wrapper only *offers* the glasses — the pill does not
        // move until a chunk actually arrives from them.
        audioFailover?.usePreferred(uiState.isGlassesSessionLive)
        // The senses move together: a session live enough to photograph through is one
        // whose wearer's head is the thing aimed at the bird, so the compass and the
        // attitude cross with the ears rather than on a rule of their own.
        headingFailover?.usePreferred(uiState.isGlassesSessionLive)
        gazeFailover?.usePreferred(uiState.isGlassesSessionLive)
      }
      // docs:glasses-session-state:end
    } catch {
      // Hanging up deliberately is not a failure and says nothing.
      if !Task.isCancelled {
        parting = Self.parting(for: error)
      }
    }
    audioFailover?.usePreferred(false)
    headingFailover?.usePreferred(false)
    gazeFailover?.usePreferred(false)

    // A photograph still crossing when the run ends dies with it, and the two of them must not
    // both speak — see ``RealtimeUiState/ending(crossingLost:parting:)``. The flag is read
    // *before* the wait, because the capture clears it on its way out.
    //
    // The wait is short by construction: ``DatGlassesSessionRepository`` fails a crossing the
    // moment its stream goes down, so the only thing still on ``photoTransferTimeout`` is a
    // photograph crossing a link that is up — which is not a run that is ending.
    let crossingLost = uiState.isCapturing
    if crossingLost { await captureRun?.value }
    uiState = uiState.ending(crossingLost: crossingLost, parting: parting)
  }

  /// Holds until the pair is reachable — registered, and its link up — or until
  /// ``glassesArrivalPatience`` runs out. Answers whether it is. Read off the snapshot the
  /// session already keeps (see ``refreshGlassesAvailability()``), so the answer is the one
  /// the pill's own switch is gated on.
  private func awaitGlassesReachable() async -> Bool {
    let deadline = ContinuousClock.now + glassesArrivalPatience
    while !uiState.isGlassesAvailable, !Task.isCancelled, ContinuousClock.now < deadline {
      try? await Task.sleep(for: glassesArrivalPoll)
    }
    return uiState.isGlassesAvailable
  }

  /// Takes the reach for the glasses back before a run ever opened, leaving `parting` — or
  /// nothing, for a reach that was cancelled rather than refused.
  private func giveUpReaching(_ parting: String?) {
    uiState.isGlassesRequested = false
    uiState.isSourceLinking = false
    uiState.sourceNotice = parting
  }

  /// The one line a failed session leaves on screen.
  ///
  /// **The version mismatch gets its own sentence because it is the failure that lies.** From
  /// the outside it is indistinguishable from a dead link — and it is not one: the glasses are
  /// on, in range, and the settings screen two taps away is showing their battery and whether
  /// they are being worn. Told "the glasses didn't answer", somebody goes looking for a
  /// Bluetooth fault that does not exist, and every reading in the app quietly disagrees with
  /// them while they look. Naming the update turns a half-hour into a minute.
  ///
  /// Internal so the mirrored tests can pin both answers without standing a session up.
  static func parting(for error: any Error) -> String {
    switch error as? GlassesError {
    case .glassesUpdateRequired:
      "Your glasses need a Meta update before they can run a session — open the Meta AI app."
    default:
      "The glasses didn't answer. Try the pill again."
    }
  }

  /// The wearer's hands on the glasses, routed to the same places the controls on screen go.
  ///
  /// **It calls ``capturePhoto()`` rather than reaching for the glasses path directly**, and
  /// that is the whole design: a press and a tap become the same act, so the choice of which
  /// device photographs — and the rule that only one photograph may be in flight — are
  /// decided once, for both.
  ///
  /// **Which is also where the debounce comes from.** Two presses in quick succession are one
  /// photograph, because the second arrives while ``RealtimeUiState/isCapturing`` is still
  /// set and is turned away there. That guard is a better answer than a timer: it lasts
  /// exactly as long as the crossing it protects, where a fixed window is either too short to
  /// catch a fumbled double press or long enough to eat a second photograph the watcher
  /// genuinely meant to take. Nothing else here needs to know about press types — a hold and
  /// a double press never reach the domain (see ``GlassesInputEvent``).
  ///
  /// Every press lands on the main actor, the same as a tap, so the guard is read and set in
  /// one place with no interleaving to reason about.
  ///
  /// **Back lands on ``stopSession()``, which is the whole reason the gesture is taken from
  /// the system at all.** Left alone it would end the run by ending the app on the glasses,
  /// which is a stop with no review, no saved outing and nothing on screen to explain itself.
  /// Answering it here makes the wearer's swipe the same act as the vermilion stop they would
  /// otherwise have reached for the phone to press. A swipe once the review is already up
  /// changes nothing — ``stopSession()`` turns the second one away, the way it turns away a
  /// second tap.
  func routeGlassesInput() async {
    // docs:input-events:begin
    for await event in glassesInput.inputEventStream() {
      switch event {
      case .shutter:
        capturePhoto()
      case .back:
        stopSession()
      }
    }
    // docs:input-events:end
  }

  /// Listens for the glasses' microphone turning out not to be available, and takes the screen's
  /// promise back when it does — see ``RealtimeUiState/withoutGlassesEars()``.
  ///
  /// **Nothing else can tell.** The failover reopens the phone and the chunks keep coming, which
  /// is exactly what it is for and exactly why the loss is invisible from the stream: the pill's
  /// `Linking` is closed by glasses audio arriving, and that is the one thing that is never going
  /// to happen now.
  ///
  /// Internal so the mirrored tests can drive it without standing a session up.
  func watchGlassesEars() async {
    guard let audioFailover else { return }
    for await _ in audioFailover.preferredLost() {
      uiState = uiState.withoutGlassesEars()
    }
  }

  /// The watcher's own voice, routed to the Director — the third way a session gets an answer,
  /// beside the ambient lane and the shutter.
  ///
  /// **The utterance is the question.** The recogniser says when somebody has finished
  /// speaking, and that boundary is what the app treats as an ask: no button frames it, no wake
  /// word opens it. A run with the glasses is listening for the whole of its length, which is
  /// the shape the hardware actually offers — recognition happens up there, so nothing on the
  /// phone is being borrowed to do it.
  ///
  /// **Partials are carried past.** The same sentence lands several times as it develops, and
  /// matching on one of those would fire an answer to half a question — "is that a green"
  /// before the jay was said.
  ///
  /// Internal so the mirrored tests can drive it without standing a session up.
  func listenForQuestions() async {
    for await heard in glassesSpeech.transcriptionStream() where heard.isFinal {
      await answerAloud(heard.text)
    }
  }

  /// One finished utterance, answered.
  ///
  /// The words land on the log first and immediately — before the Director has been asked, and
  /// whatever it says. **That is the honest half of the exchange**: what the glasses heard is a
  /// fact about the run, and a session that only ever showed the app's replies would be hiding
  /// the input those replies were made of. It is also the feedback that makes the demo readable
  /// — the sentence appears as it is said, and the answer arrives on its authored beat after it.
  ///
  /// Then one of two things. A match lands the authored answer through
  /// ``deliverAnswer(_:sessionKey:heard:)``. A miss lands the preset's own "didn't catch that"
  /// line, which is the row every preset carries for exactly this and is the reason a miss is
  /// not silence: the app heard something, could not place it, and says so rather than leaving
  /// the watcher wondering whether it was listening.
  ///
  /// **A run with nothing armed says nothing at all.** There is no preset, so there is no line
  /// to say — the words still land on the log, which is all a session with identification
  /// switched off has ever done.
  ///
  /// Internal on the same terms as ``deliverAnswer(_:sessionKey:heard:)``, and for the same
  /// reason.
  func answerAloud(_ transcript: String) async {
    let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !words.isEmpty else { return }
    // **Before anything is written down**, because an echo is not something the wearer said
    // and has no business on the log, let alone in front of the Director. See
    // ``stopListening()`` for what this is protecting against.
    guard !isHearingItself(words) else {
      BirdLog.debug(.glasses, "speech — \"\(words)\" was the app's own voice")
      return
    }
    let sessionKey = uiState.session.startedAt
    guard isSameRun(sessionKey) else { return }
    record(.speech(at: clock.elapsed, text: words))

    if let question = director.answer(to: words) {
      await deliverAnswer(question, sessionKey: sessionKey, heard: words)
      return
    }
    // **Blank is the off switch, and it is the only one.** A run listening for its whole
    // length hears the presenter talking to the room as well as to the app, and every one of
    // those sentences is a miss — so an operator who does not want the app answering them
    // clears the preset's line and gets silence, with the words still on the log. There is no
    // separate toggle for the same reason there is no speak-on/off: the authored field
    // already says whether there is anything to say.
    let line =
      director.armed?.unmatchedQuestion
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !line.isEmpty else { return }
    // A beat, so the miss reads as the app having listened rather than as a reflex. Fixed
    // rather than authored: the preset gives the words, and how long *not* understanding
    // takes is not a thing anybody should be tuning per row.
    try? await Task.sleep(for: unmatchedDelay)
    guard isSameRun(sessionKey) else { return }
    record(
      .answer(
        at: clock.elapsed,
        text: line,
        question: words,
        speciesId: nil,
        commonName: nil
      )
    )
    announce(line)
  }

  // ── Stopping, and the confirmation ─────────────────────────────────────

  /// The vermilion stop: ends the recording and lands on the review. Writes nothing —
  /// the journal hears nothing until the watcher saves there.
  ///
  /// Setting the review says the session is over; cancelling the run at the end is what
  /// actually closes the microphone. Reachable from the screen, from the glasses (a swipe
  /// back) and from wherever a pocketed session is stopped — the run is the app's, so every
  /// stop is this one. The clock is read here, once — the reading Save stores as the duration.
  func stopSession() {
    guard !uiState.isReviewing else { return }
    if uiState.isCameraOpen { closeCamera() }

    // A photograph still crossing when the stop came never arrives: ``landPhoto(_:at:)``
    // is guarded on the review the way every other late cue is, so its row would sit on
    // the confirmation as an empty tile for good. The picture is not coming, so neither
    // is the row — dropped here rather than left for Save to skip, because what the
    // watcher is deciding about should be what the session actually holds.
    for event in uiState.session.events {
      guard case let .photo(_, index, image, _, _, _, _) = event, image == nil else { continue }
      uiState.session = uiState.session.discardingPhoto(index: index)
    }

    BirdLog.info(
      .session,
      """
      session stopped after \(Int(clock.elapsed))s — \
      \(uiState.session.events.count) events on the timeline
      """
    )
    uiState.review = SessionReview(durationSeconds: clock.elapsed)
    // The phone's card goes down with the glasses' one, and for the same reason.
    uiState.cardOnPhone = nil

    // The gallery goes down with the recording — a session under review is not a bird
    // in front of the wearer. A line still being said, or queued behind one, goes with it
    // for the same reason: the run it was answering is over.
    spokenOutput.silence()
    Task { await glassesDisplay.clear() }

    // Last, so everything above sees the run as it was: cancelling is what actually closes
    // the microphone, and ``observeSession()`` tears the rest down on its way out.
    runTask?.cancel()
    runTask = nil
  }

  func setReviewNotes(_ notes: String) {
    updateReview { $0.notes = notes }
  }

  /// Keep a detection in the journal, or put it back out. The toggle answers per event —
  /// the same robin heard twice is two rows here — and what Save writes as sightings is
  /// the kept birds, one per species.
  func toggleBirdKept(at stamp: Double) {
    updateReview { review in
      if review.droppedBirds.contains(stamp) {
        review.droppedBirds.remove(stamp)
      } else {
        review.droppedBirds.insert(stamp)
      }
    }
  }

  func saveOuting() {
    Task { await performSave() }
  }

  /// Save: the whole session as one `LIVE` ``OutingDraft``, written in a single call.
  ///
  /// The location rule is the wizard's: the fix was asked for as the session opened; if it
  /// never landed, ask once more and then decline rather than logging a walk nowhere.
  /// Declining leaves the buttons live and says why.
  ///
  /// Internal for the same test-seam reason as the cue deliveries.
  func performSave() async {
    guard let review = uiState.review,
      !review.isSaving,
      review.savedOutingId == nil
    else { return }
    updateReview {
      $0.isSaving = true
      $0.saveError = nil
    }
    do {
      var fix = uiState.coordinate
      if fix == nil { fix = await locationProvider.currentCoordinate() }
      guard let fix else { throw JournalError.noLocationFix }
      let outingId = try await journal.saveOuting(
        draft(
          session: uiState.session,
          review: review,
          location: CaptureLocation(latitude: fix.latitude, longitude: fix.longitude)
        )
      )
      BirdLog.info(.journal, "outing saved — \(outingId)")
      updateReview {
        $0.isSaving = false
        $0.savedOutingId = outingId
      }
    } catch JournalError.noLocationFix {
      BirdLog.warning(.journal, "outing not saved — no location fix")
      updateReview {
        $0.isSaving = false
        $0.saveError = .noLocationFix
      }
    } catch is CancellationError {
      updateReview { $0.isSaving = false }
    } catch {
      BirdLog.error(.journal, "outing could not be written", error)
      updateReview {
        $0.isSaving = false
        $0.saveError = .writeFailed
      }
    }
  }

  /// The session's events as the journal's shapes, in one pass over the timeline:
  ///
  /// - a photo becomes a media row carrying its own moment — and, when the app named a bird
  ///   in it, a `DETECTION` event **pointing at that media row**: `seen` rather than `heard`,
  ///   because the photo is the evidence and the journal has a column for saying so;
  /// - a bird the microphone found becomes a `heard` `DETECTION`, kept or dropped alike,
  ///   because the timeline records what happened and the sightings record what the watcher
  ///   confirmed;
  /// - an answer that answered a question becomes the `QA` exchange, whole;
  /// - a kept bird becomes a sighting, one per species — confirming its detection where it
  ///   was one, and confirming nothing where the watcher's own words reached it, exactly
  ///   as the wizard's sightings do.
  ///
  /// What writes nothing: the watcher's speech (its exchange is written from the answer
  /// that paired it) and a caption the app declined with (the journal has no row for an
  /// answer that names nobody, by design) — a photo's words-only identification included.
  private func draft(
    session: RealtimeSession,
    review: SessionReview,
    location: CaptureLocation
  ) -> OutingDraft {
    var media: [PendingMedia] = []
    var events: [PendingEvent] = []
    var detectionByStamp: [Double: PendingEvent] = [:]

    for event in session.events {
      switch event {
      case let .photo(at, _, image, source, gazeContext, bearingDeg, identification):
        guard
          let pending = pendingPhoto(
            at: at,
            image: image,
            source: source,
            gazeContext: gazeContext,
            bearingDeg: bearingDeg
          )
        else { break }
        media.append(pending)
        if case let .bird(speciesId, _, confidence) = identification {
          let seen = PendingEvent.seen(
            speciesId: speciesId,
            confidence: Double(confidence),
            inPhoto: pending
          )
          events.append(seen)
          detectionByStamp[at] = seen
        }

      case let .bird(at, speciesId, _, confidence):
        let heard = PendingEvent.heard(
          speciesId: speciesId,
          confidence: Double(confidence),
          offsetMs: Int64(at * 1000)
        )
        events.append(heard)
        detectionByStamp[at] = heard

      case let .answer(at, text, question, _, _):
        if let question {
          events.append(
            PendingEvent.exchange(
              question: question,
              answer: text,
              offsetMs: Int64(at * 1000)
            )
          )
        }

      case .speech:
        break
      }
    }

    // What the session heard, one media row per unbroken stretch — the edit decision
    // list the journal plays back and draws. Encoded at Save, like the photos: a
    // discarded session should never have paid for a file.
    for segment in recorder.segments() where !segment.samples.isEmpty {
      media.append(
        PendingMedia(
          type: .audio,
          // The journal's enum has no SIMULATED: nothing simulated reaches the
          // audio spine today, and if Mock Device Kit audio ever does, the schema
          // grows the honest value rather than this mapping quietly lying.
          source: segment.source == .glasses ? .glasses : .phone,
          bytes: WavCodec.encode(segment.samples),
          fileExtension: "wav",
          offsetMs: segment.offsetMs,
          durationMs: segment.durationMs
        )
      )
    }

    // What can enter the life list: a detection the watcher kept, a bird an answer surfaced
    // that they kept, or a bird the app named in a photo they kept. One sighting per species,
    // first mention wins.
    var sightings: [PendingSighting] = []
    var confirmedSpecies: Set<String> = []
    for event in session.events where !review.droppedBirds.contains(event.at) {
      switch event {
      case let .bird(at, speciesId, _, _):
        if confirmedSpecies.insert(speciesId).inserted {
          sightings.append(
            PendingSighting(speciesId: speciesId, confirming: detectionByStamp[at])
          )
        }
      case let .answer(_, _, _, speciesId, _):
        if let speciesId, confirmedSpecies.insert(speciesId).inserted {
          sightings.append(PendingSighting(speciesId: speciesId, confirming: nil))
        }
      case let .photo(at, _, _, _, _, _, identification):
        if case let .bird(speciesId, _, _) = identification,
          confirmedSpecies.insert(speciesId).inserted
        {
          sightings.append(
            PendingSighting(speciesId: speciesId, confirming: detectionByStamp[at])
          )
        }
      default:
        break
      }
    }

    let notes = review.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return OutingDraft(
      kind: .live,
      startedAt: session.startedAt,
      durationMs: Int64(review.durationSeconds * 1000),
      location: location,
      notes: notes.isEmpty ? nil : notes,
      media: media,
      events: events,
      sightings: sightings,
      // The strip the watcher just watched, kept rather than measured again. Every column
      // of it was computed once already, as the audio arrived — the journal page used to
      // throw that away and run the whole walk back through the analyzer on open.
      sonogram: sonogram.encoded()
    )
  }

  /// The photo as the journal will hold it. Encoded at save rather than at capture — a
  /// discarded session should never have paid for compression — and to JPEG, the format
  /// every capture on this screen already is underneath.
  private func pendingPhoto(
    at: Double,
    image: CGImage?,
    source: CaptureSource,
    gazeContext: GazeContext?,
    bearingDeg: Double?
  ) -> PendingMedia? {
    // A row whose picture never crossed writes nothing. ``stopSession()`` already takes
    // those away, so this is the belt to that braces — but a media row with no bytes is
    // not a thing the journal should ever be asked to hold.
    guard let image,
      let bytes = UIImage(cgImage: image).jpegData(compressionQuality: photoJpegQuality)
    else {
      return nil
    }
    return PendingMedia(
      type: .photo,
      source: source,
      bytes: bytes,
      fileExtension: "jpg",
      offsetMs: Int64(at * 1000),
      width: image.width,
      height: image.height,
      moment: MomentContext(gazeContext: gazeContext, bearingDeg: bearingDeg)
    )
  }

  private func updateReview(_ transform: (inout SessionReview) -> Void) {
    guard var review = uiState.review else { return }
    transform(&review)
    uiState.review = review
  }

  private func record(_ event: SessionEvent) {
    // A stopped timeline takes nothing more: a photograph still crossing from the
    // glasses, or a cue composed across the stop, lands nowhere.
    guard !uiState.isReviewing else { return }
    uiState.session = uiState.session.adding(event)
  }
}

/// What the photos are re-encoded at for the journal. High, because the capture is the frame
/// the watcher already judged on screen; the cost is paid once, at Save.
private let photoJpegQuality: CGFloat = 0.9

/// How long a run reaching for the glasses waits for the pair to become reachable before it gives
/// up — see ``RealtimeViewModel/awaitGlassesReachable()``. Long enough to cover a cold start's link
/// coming up behind a voice launch, short enough that a pair left in a drawer is answered within
/// the demo's patience.
private let glassesArrivalPatience = Duration.seconds(20)

/// How often that wait looks again.
private let glassesArrivalPoll = Duration.milliseconds(100)

/// How long the "didn't catch that" line waits before it lands — see
/// ``RealtimeViewModel/answerAloud(_:)``. Long enough to read as the app having considered the
/// question, short enough that nobody wonders whether it heard at all.
private let unmatchedDelay = Duration.milliseconds(600)

/// How long after the app stops talking the question lane stays shut — see
/// ``RealtimeViewModel/stopListening()``.
///
/// **Measured against the recogniser's endpoint, not against the audio.** A final does not arrive
/// when a line stops playing; it arrives once the recogniser has heard enough silence to call the
/// utterance over, which is a beat later again. Two seconds covers that with room to spare, and
/// costs a wearer who answers instantly one repeat.
private let echoTailSeconds: Double = 4

/// How many words an utterance needs before it can be dismissed as an echo — see
/// ``RealtimeViewModel/soundsLikeSomethingJustSaid(_:)``.
private let echoMinimumWords = 3

/// How much of an utterance has to be the app's own words for it to be its own voice.
private let echoWordOverlap = 0.6

/// How long a spoken line stays suspicious. Generous against the recogniser's own lateness, and
/// short enough that a phrase the wearer chooses for themselves a while later is heard.
private let echoMemorySeconds: Double = 20

/// How many spoken lines are kept — only the last few can still be in the air.
private let recentlySaidLimit = 4

/// One line the app said out loud, kept so it can be recognised coming back — see
/// ``RealtimeViewModel/soundsLikeSomethingJustSaid(_:)``.
private struct SpokenLine {
  let words: [String]
  let at: Double
}
