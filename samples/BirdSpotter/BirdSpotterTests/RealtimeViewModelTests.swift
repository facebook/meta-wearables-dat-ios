/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  RealtimeViewModelTests.swift
//  birdspotterTests
//

import CoreGraphics
import Foundation
import Testing
@testable import birdspotter

/// The real-time session's policy: what it calls its source, what it tells the user when the
/// microphone will not open, how the clock reads, and how events land on the timeline in order.
///
/// Most of it is pure — `RealtimeUiState`, `RealtimeSession` and `sessionStamp` need no view model
/// and no microphone, the same shape `ExploreViewModelTests` takes. What does drive
/// `RealtimeViewModel` needs a clock the test winds by hand, and — for the photo lane — a
/// one-pixel `CGImage`, which needs no device and no test harness.
///
/// Scenario names are fixed by the testing-parity rule.
@MainActor
@Suite("RealtimeViewModel")
struct RealtimeViewModelTests {

  // MARK: - The source pill

  @Test func sourceLabel_namesTheDeviceInTheHand() {
    // Not "Phone": the pill's question is whose ears and eyes these are, and the useful
    // half of the answer is that they are not the glasses'.
    let state = RealtimeUiState(sourceKind: .phone)

    #expect(state.sourceState == .onDevice)
    #expect(state.sourceLabel == "On device")
  }

  @Test func sourceLabel_namesTheGlasses() {
    let state = RealtimeUiState(sourceKind: .glasses)

    #expect(state.sourceState == .glasses)
    #expect(state.sourceLabel == "Glasses")
  }

  @Test func sourceLabel_namesASimulatedFeed() {
    let state = RealtimeUiState(sourceKind: .simulated)

    #expect(state.sourceState == .simulated)
    #expect(state.sourceLabel == "Simulated")
  }

  @Test func sourceLabel_readsLinkingWhileTheGlassesArrive() {
    var state = RealtimeUiState(sourceKind: .phone)
    state.isSourceLinking = true

    #expect(state.sourceState == .linking)
    #expect(state.sourceLabel == "Linking")
  }

  @Test func sourceState_readsPausedWhileARunIsInFlightWithNothingLive() {
    // A doff or a temple tap: the run is still there to be resumed or hung up on, which is
    // neither the glasses answering nor the session being back on the phone.
    var state = RealtimeUiState(sourceKind: .phone)
    state.isGlassesRequested = true
    state.isGlassesSessionLive = false

    #expect(state.sourceState == .glassesPaused)
    // `Waiting`, not `Paused` — see ``RealtimeUiState/glassesSourceLabel``. The session did not
    // pause; the glasses did, and the phone is still recording.
    #expect(state.sourceLabel == "Waiting")
  }

  @Test func canToggleSource_needsRegisteredGlassesInReach() {
    // Also what decides the control's shape: a label with nothing to switch to, a two-sided
    // switch the moment there is.
    var state = RealtimeUiState()
    #expect(!state.canToggleSource)

    state.isGlassesAvailable = true
    #expect(state.canToggleSource)
  }

  @Test func theSwitchNamesBothSidesAtOnce() {
    var state = RealtimeUiState()
    state.isGlassesAvailable = true

    #expect(state.deviceSourceLabel == "On device")
    #expect(state.glassesSourceLabel == "Glasses")
    #expect(!state.isGlassesSelected)
  }

  @Test func theSwitchSaysASimulatedFeedIsStillOnTheDevice() {
    // The honesty line outranks the symmetry: a scripted feed is running on the thing in
    // the hand, and the left side is where that gets said.
    var state = RealtimeUiState(sourceKind: .simulated)
    state.isGlassesAvailable = true

    #expect(state.deviceSourceLabel == "Simulated")
    #expect(!state.isGlassesSelected)
  }

  @Test func theSwitchThrowsOnTheTapRatherThanOnTheEars() {
    // The crossing is the *ink's* business — a selection that waited for the audio would sit
    // under the thumb doing nothing, which is how a control gets pressed twice.
    var linking = RealtimeUiState()
    linking.isGlassesRequested = true
    linking.isSourceLinking = true

    #expect(linking.isGlassesSelected)
    #expect(linking.glassesSourceLabel == "Linking")
    #expect(linking.deviceSourceLabel == "On device")
  }

  @Test func theGlassesSideCarriesEveryStateTheSessionCanBeIn() {
    // Every word this control has beyond the two device names is about the glasses; the
    // phone is only ever the phone.
    var paused = RealtimeUiState()
    paused.isGlassesRequested = true
    paused.isGlassesSessionLive = false

    #expect(paused.glassesSourceLabel == "Waiting")
    #expect(paused.isGlassesSelected)
    #expect(paused.deviceSourceLabel == "On device")
  }

  @Test func aPausedRunStaysSelectedOnTheGlassesWithThePhoneCarryingIt() {
    // The switch says where the session is *assigned*; the carrying flag says who is doing
    // the work. Throwing the selection back to the phone would make the glasses side the
    // tappable one — and that tap hangs the run up.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    let paused =
      state
      .applying(.started)
      .hearing(.glasses)
      .applying(.paused)
      .hearing(.phone)

    #expect(paused.sourceState == .glassesPaused)
    #expect(paused.isGlassesSelected)
    #expect(paused.isDeviceCarrying)
  }

  @Test func onlyAPausedRunHasThePhoneCarryingSomeoneElsesSession() {
    // Every other state has the lit side and the working side on the same device.
    var linking = RealtimeUiState()
    linking.isSourceLinking = true

    #expect(!RealtimeUiState().isDeviceCarrying)
    #expect(!linking.isDeviceCarrying)
    #expect(!RealtimeUiState(sourceKind: .glasses).isDeviceCarrying)
  }

  // MARK: - A run whose microphone the glasses could not give

  @Test func withoutGlassesEars_endsTheCrossingItCanNoLongerHonour() {
    // `Linking` is closed by glasses audio arriving — which, once the microphone has been
    // refused, is never. Left alone the pill promises the whole run a crossing that has
    // already been abandoned.
    let state = requestedRun().applying(.started).withoutGlassesEars()

    #expect(!state.isSourceLinking)
    #expect(state.sourceState == .onDevice)
  }

  @Test func withoutGlassesEars_saysWhichHalfOfTheGlassesSurvived() {
    let state = requestedRun().applying(.started).withoutGlassesEars()

    // Told only that the microphone failed, a watcher reasonably concludes the glasses are
    // done — and the shutter and the button on the temple are still theirs.
    #expect(state.sourceNotice?.contains("Photos") == true)
  }

  @Test func withoutGlassesEars_leavesTheSessionItselfAlone() {
    // The ears are not the session: a run with the phone's microphone still photographs
    // through the glasses, so nothing here may end it.
    let state = requestedRun().applying(.started).withoutGlassesEars()

    #expect(state.isGlassesSessionLive)
    #expect(state.isGlassesRequested)
  }

  @Test func aRunWithoutGlassesEarsStaysSelectedOnTheGlassesWithThePhoneCarryingIt() {
    // The same sentence the pause tells: the switch says where the session is assigned, the
    // carrying flag says who is listening meanwhile.
    let state = requestedRun()
      .applying(.started)
      .withoutGlassesEars()
      .hearing(.phone)

    #expect(state.isGlassesSelected)
    #expect(state.isDeviceCarrying)
  }

  @Test func withoutGlassesEars_withNoRunInFlight_saysNothing() {
    // The signal outlives the request by a beat, and a sentence about glasses on a screen
    // that has gone back to the phone is worse than no sentence.
    #expect(RealtimeUiState().withoutGlassesEars().sourceNotice == nil)
  }

  /// A screen that has asked for the glasses and is waiting on the crossing.
  private func requestedRun() -> RealtimeUiState {
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true
    return state
  }

  @Test func toggleSource_withoutGlassesInReach_staysOnPhone() {
    let model = viewModel(audio: FakeAudioSource())

    model.toggleSource()

    #expect(model.uiState.sourceKind == .phone)
  }

  // MARK: - What the session's state does to the pill

  @Test func applying_started_makesTheGlassesTheOnesToPhotographThrough() {
    var state = RealtimeUiState()
    state.isSourceLinking = true

    let next = state.applying(.started)

    #expect(next.isGlassesSessionLive)
  }

  @Test func applying_started_holdsTheLinkingBeatUntilTheEarsArrive() {
    // The session being up is the ears being *asked* for; the glasses' audio arrives a beat
    // later. Clearing the crossing here dropped the pill back to `On device` for a frame
    // between `Linking` and `Glasses`.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true

    let next = state.applying(.started)

    #expect(next.isSourceLinking)
    #expect(next.sourceState == .linking)
  }

  @Test func hearing_theGlasses_endsTheCrossing() {
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true

    let next = state.applying(.started).hearing(.glasses)

    #expect(!next.isSourceLinking)
    #expect(next.sourceState == .glasses)
  }

  @Test func hearing_thePhoneMidCrossing_leavesTheCrossingOpen() {
    // The phone keeps recording underneath while the glasses warm up — the failover never
    // closes a working microphone on the promise of a better one. Its chunks say nothing
    // about whether the crossing has happened.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true

    let next = state.applying(.started).hearing(.phone)

    #expect(next.isSourceLinking)
    #expect(next.sourceState == .linking)
  }

  @Test func theCrossingNeverShowsThePhoneOnTheWayToTheGlasses() {
    // The whole tap-to-glasses sequence, in order: nothing in it may read `On device`.
    var seen: [SourceState] = []
    var state = RealtimeUiState(sourceKind: .phone)
    seen.append(state.sourceState)

    state.isGlassesRequested = true
    state.isSourceLinking = true
    seen.append(state.sourceState)

    state = state.applying(.started)
    seen.append(state.sourceState)

    state = state.hearing(.glasses)
    seen.append(state.sourceState)

    #expect(seen == [.onDevice, .linking, .linking, .glasses])
  }

  @Test func aResumeAfterAPauseCrossesBackThroughLinking() {
    // A doff and a pick-up: `Paused`, then the same crossing beat again rather than a
    // flash of `On device` on the way back.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true
    let paused =
      state
      .applying(.started)
      .hearing(.glasses)
      .applying(.paused)
      .hearing(.phone)
    #expect(paused.sourceState == .glassesPaused)

    let resuming = paused.applying(.started)
    #expect(resuming.sourceState == .linking)

    #expect(resuming.hearing(.glasses).sourceState == .glasses)
  }

  @Test func applying_started_doesNotMoveThePillOnItsOwn() {
    // The pill follows audio that actually arrived — a session whose microphone never
    // opens must not leave the screen claiming the glasses.
    let state = RealtimeUiState().applying(.started)

    // The claim is what must not move — the pill may say it is still getting there, and
    // does, but it may not say `Glasses` until a chunk has come out of them.
    #expect(state.sourceKind == .phone)
    #expect(state.sourceState != .glasses)
  }

  @Test func aChunkFromTheGlassesIsWhatMovesThePill() {
    var state = RealtimeUiState()
    state.sourceKind = .glasses

    #expect(state.sourceLabel == "Glasses")
  }

  @Test func applying_starting_staysOnTheLinkingBeat() {
    var state = RealtimeUiState()
    state.isSourceLinking = true

    let next = state.applying(.starting)

    #expect(!next.isGlassesSessionLive)
    #expect(next.isSourceLinking)
    #expect(next.sourceLabel == "Linking")
  }

  @Test func applying_paused_handsThePhotographBackToThePhone() {
    // A doff, or a tap on the temple. The shutter must stop routing to glasses that are
    // no longer running the session.
    let state = RealtimeUiState().applying(.started).applying(.paused)

    #expect(!state.isGlassesSessionLive)
    #expect(state.sourceNotice != nil)
  }

  @Test func applying_startedAfterPaused_clearsTheNotice() {
    let state = RealtimeUiState()
      .applying(.started)
      .applying(.paused)
      .applying(.started)

    #expect(state.isGlassesSessionLive)
    #expect(state.sourceNotice == nil)
  }

  @Test func applying_stopping_handsThePhotographBackQuietly() {
    let state = RealtimeUiState().applying(.started).applying(.stopping)

    #expect(!state.isGlassesSessionLive)
    #expect(state.sourceNotice == nil)
  }

  @Test func ending_midCrossing_saysTheSessionEndedRatherThanBlamingThePhoto() {
    // A long press on the temple ends the session under a photograph that is still crossing.
    // The row it would have landed on leaves the timeline, and the capture and the run's own
    // teardown both used to reach for the notice — so which sentence survived was a race, and
    // one of the two outcomes explained nothing at all.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isGlassesSessionLive = true
    state.isCapturing = true

    let ended = state.ending(
      crossingLost: true,
      parting: "The glasses didn't answer. Try the pill again."
    )

    #expect(ended.sourceNotice == "The session ended before the photo arrived.")
    // And the switch is a switch again, with the phone on it.
    #expect(ended.sourceState == .onDevice)
    #expect(!ended.isCapturing)
    #expect(!ended.isGlassesRequested)
  }

  @Test func ending_withNothingCrossing_carriesThePartingLine() {
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.isSourceLinking = true

    let ended = state.ending(crossingLost: false, parting: "The glasses didn't answer.")

    #expect(ended.sourceNotice == "The glasses didn't answer.")
    #expect(!ended.isSourceLinking)
  }

  @Test func parting_forGlassesBehindOnTheirUpdate_namesTheUpdateRatherThanTheLink() {
    // The failure that lies: the glasses are on, in range, and the settings screen is
    // showing their battery — none of which needs anything from them but a connection,
    // where a session needs their software. "Didn't answer" sends somebody hunting a
    // Bluetooth fault that is not there.
    let line = RealtimeViewModel.parting(for: GlassesError.glassesUpdateRequired)

    #expect(line.contains("Meta AI app"))
    #expect(!line.contains("didn't answer"))
  }

  @Test func parting_forEveryOtherFailure_staysTheOneAnswerTheScreenCanGive() {
    // Nothing eligible, heat, power, a session already running — all of them are a link
    // that will not hold, and none of them is a sentence a wearer can act on differently.
    #expect(
      RealtimeViewModel.parting(for: GlassesError.notConnected)
        == "The glasses didn't answer. Try the pill again."
    )
    #expect(
      RealtimeViewModel.parting(for: GlassesError.transferFailed)
        == "The glasses didn't answer. Try the pill again."
    )
  }

  @Test func ending_afterADeliberateHangUp_saysNothing() {
    // Hanging up is not a failure, and a run that ended with nothing in flight has nothing to
    // explain — including a pause it already recovered from.
    var state = RealtimeUiState()
    state.isGlassesRequested = true
    state.sourceNotice = "The glasses paused the session — the phone has it until they resume."

    #expect(state.ending(crossingLost: false, parting: nil).sourceNotice == nil)
  }

  @Test func observeGlasses_aReachablePair_putsItsChargeOnTheGlance() async {
    // The reading the session screen owes a wearer running the glasses' camera, microphone
    // and sensors at once: how much longer they can keep doing it.
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(audio: FakeAudioSource(), glassesSession: glasses)

    let observing = Task { await model.observeGlasses() }
    defer { observing.cancel() }
    await Self.settle(until: glasses.isListening)

    glasses.report(GlassesDeviceInfo(name: "Ray-Ban", isAvailable: true, batteryLevel: 82))

    await Self.settle(until: model.uiState.glassesBattery != nil)
    #expect(model.uiState.glassesBattery == 82)
  }

  @Test func observeGlasses_aPairThatGoesOutOfReach_takesItsChargeWithIt() async {
    // **The one rule this glance has.** A charge from before the glasses left the room is the
    // reading worth nothing, and a number that stays on screen after the link drops is a
    // sentence about a pair that is not there — so the glance goes quiet with the pair rather
    // than keeping the last thing it heard.
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(audio: FakeAudioSource(), glassesSession: glasses)

    let observing = Task { await model.observeGlasses() }
    defer { observing.cancel() }
    await Self.settle(until: glasses.isListening)

    glasses.report(GlassesDeviceInfo(name: "Ray-Ban", isAvailable: true, batteryLevel: 82))
    await Self.settle(until: model.uiState.glassesBattery != nil)

    // Same charge, same pair — only the link has gone.
    glasses.report(GlassesDeviceInfo(name: "Ray-Ban", isAvailable: false, batteryLevel: 82))

    await Self.settle(until: model.uiState.glassesBattery == nil)
    #expect(model.uiState.glassesBattery == nil)
    #expect(!model.uiState.isGlassesAvailable)
  }

  @Test func aPausedSessionCanStillBeHungUpOn() {
    // The device owns resume; the pill's only power over a paused session is to end it —
    // so it stays tappable even with the glasses out of reach.
    var state = RealtimeUiState()
    state.isGlassesAvailable = false
    state.isGlassesRequested = true

    #expect(state.applying(.paused).canToggleSource)
  }

  @Test func startOnGlasses_beforeTheSessionOpens_reachesForTheGlassesTheMomentItDoes() async {
    // The voice launch lands while the cover is still rising, so the ask comes before
    // the session's own opening reset — and must survive it. A launch spoken from the
    // glasses that opened a session on the phone would be the app ignoring the words
    // that started it.
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(500)),
      glassesSession: FakeGrantedGlassesSession()
    )

    model.startOnGlasses()
    let session = Task { await model.observeSession() }

    await Self.settle(until: model.uiState.isGlassesRequested)
    session.cancel()

    #expect(model.uiState.isGlassesRequested)
  }

  @Test func startOnGlasses_waitsForThePairToArrive() async {
    // A voice launch lands while the pair is still listed as out of reach — its link comes
    // up a beat later. The run must hold on Linking rather than refuse, and go on to the
    // gates the moment the pair is reachable.
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .seconds(5)),
      glassesSession: glasses
    )

    model.startOnGlasses()
    let session = Task { await model.observeSession() }
    await Self.settle(until: glasses.isListening)
    await Self.settle(until: model.uiState.isSourceLinking)

    // Still reaching, not refused.
    #expect(model.uiState.sourceNotice == nil)
    #expect(model.uiState.sourceState == .linking)

    // The pair arrives; this fake then refuses the grant, which is how the test sees that
    // the run moved on past the wait.
    glasses.report(GlassesDeviceInfo(name: "Ray-Ban", isAvailable: true))
    await Self.settle(until: model.uiState.sourceNotice != nil, within: .seconds(2))
    session.cancel()

    #expect(model.uiState.sourceNotice?.contains("aren't answering") == true)
    #expect(!model.uiState.isSourceLinking)
  }

  @Test func startOnGlasses_withTheCameraOpen_closesThePanelOnTheWayOver() {
    // The panel is the phone's viewfinder and the glasses have none — the same trade
    // the pill makes on the way over.
    let model = viewModel(audio: FakeAudioSource())

    model.openCamera()
    model.startOnGlasses()

    #expect(!model.uiState.isCameraOpen)
  }

  @Test func startOnGlasses_whileAGlassesRunIsInFlight_leavesTheRunAlone() {
    // A spoken open only ever asks; a repeat finds the ask already made and changes
    // nothing — the difference from the pill, whose second tap is a hang-up. The camera
    // left open is the proof: a fresh ask would have closed it on the way over.
    let model = viewModel(audio: FakeAudioSource())

    model.startOnGlasses()
    model.openCamera()
    model.startOnGlasses()

    #expect(model.uiState.isCameraOpen)
  }

  // MARK: - Status

  @Test func initially_isOpening() {
    let state = RealtimeUiState()

    #expect(state.status == .opening)
    #expect(state.failure == nil)
    #expect(state.failureMessage == nil)
  }

  @Test func listening_marksTheSessionListening() {
    let state = RealtimeUiState().listening()

    #expect(state.status == .listening)
    #expect(state.failure == nil)
  }

  // MARK: - Where the session is

  @Test func initially_hasNoFix() {
    #expect(!RealtimeUiState().isLocated)
  }

  @Test func aFixMakesTheSessionLocated() {
    let state = RealtimeUiState(coordinate: Coordinate(latitude: 39.142, longitude: -84.506))

    #expect(state.isLocated)
  }

  // MARK: - Which way it is facing

  @Test func compassPoint_namesTheEightPoints() {
    #expect(compassPoint(0) == "N")
    #expect(compassPoint(45) == "NE")
    #expect(compassPoint(90) == "E")
    #expect(compassPoint(135) == "SE")
    #expect(compassPoint(180) == "S")
    #expect(compassPoint(225) == "SW")
    #expect(compassPoint(270) == "W")
    #expect(compassPoint(315) == "NW")
  }

  @Test func compassPoint_takesTheNearestPoint() {
    // Each point owns the 45° centred on it, so the boundary between two sits at 22.5.
    #expect(compassPoint(22.4) == "N")
    #expect(compassPoint(22.6) == "NE")
    #expect(compassPoint(337.6) == "N")
  }

  @Test func compassPoint_wrapsPastAFullTurn() {
    // A magnetometer reports whatever it last computed; wrapping is this function's job.
    #expect(compassPoint(360) == "N")
    #expect(compassPoint(405) == "NE")
    #expect(compassPoint(-45) == "NW")
  }

  @Test func initially_hasNoBearing() {
    #expect(RealtimeUiState().headingPoint == nil)
  }

  @Test func aHeadingReadsAsACompassPoint() {
    #expect(RealtimeUiState(heading: 210).headingPoint == "SW")
  }

  // MARK: - How high it is aiming

  @Test func gazeBand_namesTheFiveStrata() {
    #expect(gazeBand(80) == .overhead)
    #expect(gazeBand(40) == .canopy)
    #expect(gazeBand(0) == .horizon)
    #expect(gazeBand(-30) == .understory)
    #expect(gazeBand(-80) == .ground)
  }

  @Test func gazeBand_isSymmetricAboutLevel() {
    // **The thresholds are the geometry, not one device's grip.** Looking 30° up and 30° down
    // are the same distance from level whatever is doing the looking, so the bands either side
    // of `Horizon` are mirror images. An instrument that reads below where it is actually
    // aimed — a phone tipped back to be read — corrects itself before it gets here, which is
    // why that correction is not visible in these numbers.
    #expect(gazeBand(-17) == .horizon)
    #expect(gazeBand(-18) == .understory)
    #expect(gazeBand(17) == .horizon)
    #expect(gazeBand(18) == .canopy)

    // Mirrored elevations land in mirrored strata, which is the property the name claims.
    #expect(gazeBand(30) == .canopy)
    #expect(gazeBand(-30) == .understory)
    #expect(gazeBand(60) == .overhead)
    #expect(gazeBand(-60) == .ground)
  }

  @Test func gazeBand_survivesPastThePoles() {
    // A fused sensor reading arrives as whatever it last computed; clamping is not the caller's
    // job.
    #expect(gazeBand(120) == .overhead)
    #expect(gazeBand(-120) == .ground)
  }

  @Test func initially_hasNoBand() {
    #expect(RealtimeUiState().elevationBand == nil)
  }

  @Test func anElevationReadsAsAStratum() {
    #expect(RealtimeUiState(elevation: 30).elevationBand == .canopy)
  }

  // MARK: - Failure

  @Test func failed_withAccessDenied_pointsAtSettings() {
    let state = RealtimeUiState().failed(AudioCaptureError.accessDenied)

    #expect(state.status == .failed)
    #expect(
      state.failureMessage
        == "Microphone access is off. Turn it back on in Settings to start a session."
    )
  }

  @Test func failed_withInterrupted_saysAnotherAppTookTheMicrophone() {
    let state = RealtimeUiState().failed(AudioCaptureError.interrupted)

    #expect(
      state.failureMessage
        == "Another app took the microphone. Close the session and start it again."
    )
  }

  @Test func failed_withAnUnknownError_reportsUnavailable() {
    struct SomethingElseEntirely: Error {}

    let state = RealtimeUiState().failed(SomethingElseEntirely())

    #expect(state.failure == .unavailable)
    #expect(state.failureMessage == "There's no microphone to listen with.")
  }

  // MARK: - The clock

  @Test func sessionStamp_readsAsAStopwatch() {
    #expect(sessionStamp(0) == "0:00")
    #expect(sessionStamp(9.8) == "0:09")
    #expect(sessionStamp(67) == "1:07")
    #expect(sessionStamp(720) == "12:00")
  }

  @Test func sessionStamp_neverGoesBackwardsPastZero() {
    // The strip clamps its window rather than the clock, so a negative can reach here.
    #expect(sessionStamp(-3) == "0:00")
  }

  // MARK: - The timeline

  @Test func adding_keepsEventsInTimeOrder() {
    let session = RealtimeSession(startedAt: 0)
      .adding(.speech(at: 9, text: "green with a yellow belly"))
      .adding(.bird(at: 4, speciesId: "american-robin", commonName: "American Robin", confidence: 0.87))

    // A photo is stamped when the shutter fires and a detection when the detector speaks;
    // nothing guarantees they arrive in the order they happened.
    #expect(session.events.map(\.at) == [4, 9])
  }

  @Test func eventsBetween_takesTheWindowInclusive() {
    let session = RealtimeSession(startedAt: 0)
      .adding(.speech(at: 2, text: "before"))
      .adding(.speech(at: 4, text: "on the edge"))
      .adding(.speech(at: 9, text: "after"))

    let visible = session.eventsBetween(from: 4, to: 8)

    #expect(visible.count == 1)
    if case let .speech(_, text) = visible[0] {
      #expect(text == "on the edge")
    } else {
      Issue.record("expected the spoken marker on the window's edge")
    }
  }

  @Test func finding_at_stampsItIntoAnEvent() {
    let finding = SessionFinding.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.91)

    let event = finding.at(18.5)

    #expect(event.at == 18.5)
    if case let .bird(_, speciesId, commonName, confidence) = event {
      #expect(speciesId == "green-jay")
      #expect(commonName == "Green Jay")
      #expect(confidence == 0.91)
    } else {
      Issue.record("a bird finding should stamp into a bird event")
    }
  }

  @Test func finding_at_stampsAnAnswer() {
    let finding = SessionFinding.answer(text: "Green Jay or Blue Jay?")

    let event = finding.at(9.0)

    #expect(event.at == 9.0)
    if case let .answer(_, text, question, speciesId, _) = event {
      #expect(text == "Green Jay or Blue Jay?")
      #expect(question == nil)
      #expect(speciesId == nil)
    } else {
      Issue.record("an answer finding should stamp into an answer event")
    }
  }

  @Test func resolvingPhoto_fillsInTheAnswerWithoutMovingTheRow() {
    // Found by capture index rather than by stamp: the stamp is an identity the collision
    // nudge is free to move, and the index is the number the answer was asked for under.
    let session = RealtimeSession(startedAt: 0)
      .adding(Self.photoEvent(at: 4, index: 0))
      .adding(.speech(at: 6, text: "after"))
      .adding(Self.photoEvent(at: 9, index: 1))

    let resolved = session.resolvingPhoto(
      index: 1,
      to: .bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.92)
    )

    #expect(resolved.events.map(\.at) == [4, 6, 9])
    if case let .photo(_, _, _, _, _, _, identification) = resolved.events[0] {
      #expect(identification == .pending)
    } else {
      Issue.record("the first capture should be untouched")
    }
    if case let .photo(_, _, _, _, _, _, identification) = resolved.events[2] {
      #expect(identification == .bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.92))
    } else {
      Issue.record("the second capture should carry the answer")
    }
  }

  @Test func resolvingPhoto_forACaptureThatIsGone_changesNothing() {
    let session = RealtimeSession(startedAt: 0).adding(Self.photoEvent(at: 4, index: 0))

    let resolved = session.resolvingPhoto(index: 7, to: nil)

    if case let .photo(_, _, _, _, _, _, identification) = resolved.events[0] {
      #expect(identification == .pending)
    } else {
      Issue.record("the capture should be untouched")
    }
  }

  @Test func resolvingPhoto_fillsThePictureIntoTheRowThatWasWaitingForIt() {
    // The glasses' crossing: the row is stamped at the press with no picture in it, and
    // the photograph drops into that row rather than arriving as one of its own.
    let session = RealtimeSession(startedAt: 0)
      .adding(Self.crossingPhotoEvent(at: 4, index: 0))
      .adding(.speech(at: 6, text: "after"))

    let landed = session.resolvingPhoto(index: 0, toImage: Self.frame().image)

    #expect(landed.events.map(\.at) == [4, 6])
    if case let .photo(_, _, image, _, _, _, _) = landed.events[0] {
      #expect(image != nil)
    } else {
      Issue.record("the waiting capture should have taken the picture")
    }
  }

  @Test func discardingPhoto_takesAwayTheRowOfACrossingThatFailed() {
    // A photograph that never arrived is not a thing that happened during the session.
    let session = RealtimeSession(startedAt: 0)
      .adding(Self.photoEvent(at: 2, index: 0))
      .adding(Self.crossingPhotoEvent(at: 4, index: 1))
      .adding(.speech(at: 6, text: "after"))

    let dropped = session.discardingPhoto(index: 1)

    #expect(dropped.events.map(\.at) == [2, 6])
  }

  @Test func discardingPhoto_forACaptureThatIsGone_changesNothing() {
    let session = RealtimeSession(startedAt: 0).adding(Self.photoEvent(at: 4, index: 0))

    let dropped = session.discardingPhoto(index: 7)

    #expect(dropped.events.map(\.at) == [4])
  }

  @Test func adding_nudgesAnExactStampCollisionForward() {
    // Stamps double as the log's row identities, so two events cannot share one — a
    // photo and its zero-delay scripted response land inside the same millisecond.
    let session = RealtimeSession(startedAt: 0)
      .adding(.speech(at: 4.0, text: "first"))
      .adding(.speech(at: 4.0, text: "second"))

    #expect(session.events.map(\.at) == [4.0, 4.001])
  }

  // MARK: - The view model

  @Test func viewModel_takesItsSourceKindFromTheAudioSource() {
    let model = viewModel(audio: FakeAudioSource(kind: .glasses))

    #expect(model.uiState.sourceKind == .glasses)
  }

  @Test func observeSession_whenTheMicrophoneFails_reportsTheFailure() async {
    let model = viewModel(audio: FakeAudioSource(failure: .interrupted))

    await model.observeSession()

    #expect(model.uiState.status == .failed)
    #expect(model.uiState.failure == .interrupted)
    #expect(model.sonogram.count == 0)
  }

  @Test func observeSession_stampsTheSessionWhereItStarted() async {
    let here = Coordinate(latitude: 39.142, longitude: -84.506)
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), fix: here)

    await model.observeSession()

    #expect(model.uiState.coordinate == here)
    #expect(model.uiState.isLocated)
  }

  @Test func observeSession_withNoFix_leavesTheSessionUnlocated() async {
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), fix: nil)

    await model.observeSession()

    #expect(model.uiState.coordinate == nil)
    #expect(!model.uiState.isLocated)
  }

  @Test func observeSession_followsTheCompass() async {
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), bearings: [110])

    await model.observeSession()

    #expect(model.uiState.heading == 110)
    #expect(model.uiState.headingPoint == "E")
  }

  @Test func observeSession_withNoCompass_leavesTheBearingUnread() async {
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), bearings: [])

    await model.observeSession()

    #expect(model.uiState.headingPoint == nil)
  }

  @Test func observeSession_followsTheTilt() async {
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), elevations: [40])

    await model.observeSession()

    #expect(model.uiState.elevation == 40)
    #expect(model.uiState.elevationBand == .canopy)
  }

  @Test func observeSession_withNoTilt_leavesTheBandUnread() async {
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), elevations: [])

    await model.observeSession()

    #expect(model.uiState.elevationBand == nil)
  }

  // MARK: - The session clock

  @Test func placement_leavesOrdinaryJitterAlone() {
    // A microphone handing a buffer over a beat late is not a gap, and closing up a column or
    // two would cost more than it bought.
    #expect(placement(clockColumn: 500, written: 495) == 495)
    #expect(placement(clockColumn: 500, written: 484) == 484)
  }

  @Test func placement_skipsForwardAfterAGap() {
    // Far enough behind and the microphone genuinely stopped: the silence belongs on the strip
    // at the second it happened.
    #expect(placement(clockColumn: 500, written: 100) == 500)
  }

  @Test func placement_neverMovesTheWriteHeadBack() {
    // Audio running ahead of the clock is the harmless direction, and a written column is a
    // column that happened.
    #expect(placement(clockColumn: 400, written: 500) == 500)
  }

  @Test func observeSession_startsTheClockOver() async {
    let clock = FakeSessionClock()
    clock.advance(by: 40)
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(30)), clock: clock)

    await model.observeSession()

    // A second visit is a new session, not the tail of the last one.
    #expect(clock.starts == 1)
  }

  @Test func observeSession_withNoAudioAtAll_stillMovesTheTimeline() async {
    // The regression the clock exists for. While elapsed was `columns / 62.5`, a session that
    // heard nothing had a strip frozen at second zero — and so did one whose microphone
    // dropped for four seconds mid-run, which is what failover will do routinely.
    let clock = FakeSessionClock()
    clock.advance(by: 12.5)
    let model = viewModel(audio: FakeAudioSource(openFor: .milliseconds(60)), clock: clock)

    await model.observeSession()

    #expect(model.sonogram.count == 0)
    #expect(model.elapsed == 12.5)
  }

  @Test func observeSession_stampsAFindingFromTheClock() async {
    // Not from the sonogram: with no audio the column count is zero, and a bird stamped at
    // 0:00 four seconds into a dropout is the timeline lying about when it heard something.
    let clock = FakeSessionClock()
    clock.advance(by: 18.5)
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.91)],
      clock: clock
    )

    await model.observeSession()

    #expect(model.uiState.session.events.map(\.at) == [18.5])
  }

  // The armed preset used to be read into the ui state for a line under the header, and
  // both went: what the Director is playing is read on its own page. The cues it fires are
  // covered by the lanes below — a preset that is armed proves it by answering.

  // MARK: - A photo, and the answer that lands on it

  @Test func capturePhoto_landsThePhotoWaitingForItsAnswer() async {
    // The wait is set at the shutter, not when the answer arrives: the row has to be
    // showing that something is coming from the moment the picture is on the log.
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.waitingPhotoPreset,
      frames: [Self.frame()]
    )
    await model.observeCamera()

    model.capturePhoto()

    guard case let .photo(_, index, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the shutter should put a photo on the timeline")
      return
    }
    #expect(index == 0)
    #expect(identification == .pending)
  }

  @Test func capturePhoto_pressedAgainDuringTheFlashSettle_takesOnePhotograph() async {
    // The armed flash holds the panel open across ``flashSettle`` so the light is seen coming
    // on, which used to leave the shutter live across those milliseconds: two presses lit the
    // torch twice, raced for when to put it out, and landed two photographs of one moment.
    // The guard is the capture itself, not a timer.
    let camera = FakeCameraSource(frames: [Self.frame()])
    let model = viewModel(audio: FakeAudioSource(), camera: camera)
    await model.observeCamera()
    model.toggleFlash()

    model.capturePhoto()

    // The settle runs in a child task, so it has not started when the press returns.
    // Yield until it has — bounded, so a broken guard fails
    // the expectation below rather than hanging the suite.
    for _ in 0..<100 where !model.uiState.isCapturing {
      await Task.yield()
    }
    #expect(model.uiState.isCapturing)

    // The second press, inside the settle, is dropped rather than queued: the light is asked
    // for once, and only the one settle is running to put it out again.
    model.capturePhoto()

    #expect(camera.torchOns == 1)
  }

  @Test func routeGlassesInput_aPressOnTheGlasses_takesTheSamePhotographTheShutterDoes() async {
    // The button on the temple and the button on screen are one act: the press is routed
    // through `capturePhoto()` rather than at the glasses directly, so the choice of which
    // device photographs — and the one-at-a-time guard — are decided once, for both.
    let input = FakeGlassesInput()
    let model = viewModel(audio: FakeAudioSource(), frames: [Self.frame()], glassesInput: input)
    await model.observeCamera()

    let routing = Task { await model.routeGlassesInput() }
    defer { routing.cancel() }

    // The subscription is made inside that child task, so it has not happened yet when the
    // task is created — and a press with nobody listening is dropped by design. Yield until
    // it has subscribed, bounded, so a press that never routes fails the expectation below
    // rather than hanging the suite.
    for _ in 0..<100 where !input.isListening {
      await Task.yield()
    }

    input.press()

    for _ in 0..<100 where model.uiState.session.events.isEmpty {
      await Task.yield()
    }
    guard case let .photo(_, index, _, source, _, _, _) = model.uiState.session.events.first
    else {
      Issue.record("a press on the glasses should put a photo on the timeline")
      return
    }
    #expect(index == 0)
    // The phone took it, because no glasses session is running — which is the routing under
    // test. A press is a request for *a* photograph, not for a photograph from the glasses.
    #expect(source == .phone)
  }

  @Test func routeGlassesInput_aBackOnTheGlasses_endsTheRunTheStopOnScreenWouldHaveEnded() async {
    // Back is taken out of the system's hands so that a swipe stops ending the run by ending
    // the app on the glasses — a stop with no review and nothing on screen to explain it.
    // Taking it leaves the gesture owing the wearer an answer, and the answer is the stop
    // they would otherwise have picked the phone up to press.
    let clock = FakeSessionClock()
    clock.advance(by: 42)
    let input = FakeGlassesInput()
    let model = viewModel(audio: FakeAudioSource(), clock: clock, glassesInput: input)

    let routing = Task { await model.routeGlassesInput() }
    defer { routing.cancel() }

    // The subscription is made inside that child task, so it has not happened yet when the
    // task is created — and a gesture with nobody listening is dropped by design.
    await Self.settle(until: input.isListening)

    input.swipeBack()

    await Self.settle(until: model.uiState.isReviewing)
    #expect(model.uiState.isReviewing)
    // The same landing the vermilion stop makes, clock reading and all — not a shortcut that
    // happens to leave the screen looking similar.
    #expect(model.uiState.review?.durationSeconds == 42)
  }

  @Test func capturePhoto_withNothingScripted_leavesThePhotoWaitingForNothing() async {
    // Nothing armed, nothing composing. A row that spun forever beside this photograph
    // would be the screen promising an answer nobody is writing.
    let model = viewModel(audio: FakeAudioSource(), frames: [Self.frame()])
    await model.observeCamera()

    model.capturePhoto()

    guard case let .photo(_, _, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the shutter should put a photo on the timeline")
      return
    }
    #expect(identification == nil)
  }

  @Test func deliverPhotoResponse_landsTheScriptedBirdOnItsPhoto() async {
    let clock = FakeSessionClock()
    clock.advance(by: 10)
    let model = viewModel(audio: FakeAudioSource(), frames: [Self.frame()], clock: clock)
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      DemoPhotoResponse(
        id: "photo-1",
        result: .species(speciesId: "green-jay", confidence: 0.92),
        caption: "Green Jay",
        spokenLine: nil,
        delayMillis: 0
      ),
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    // One row, not two: the answer is on the capture that produced it.
    #expect(model.uiState.session.events.count == 1)
    guard case let .photo(at, _, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the answer should land on the photo")
      return
    }
    #expect(at == 10)
    #expect(identification == .bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.92))
  }

  @Test func deliverPhotoResponse_pastTheEnd_answersOnThePhotoWithTheFixedCaption() async {
    let model = viewModel(audio: FakeAudioSource(), frames: [Self.frame()])
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      .pastTheEnd,
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    guard case let .photo(_, _, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the answer should land on the photo")
      return
    }
    #expect(identification == .words(DemoPhotoResponse.pastTheEnd.caption))
  }

  @Test func deliverPhotoResponse_dropsABirdTheCatalogCannotName() async {
    // The same silence the Director's ambient path keeps — except that here it has to be
    // delivered: the photo is on the log with its dots running, and this is what stops them.
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.waitingPhotoPreset,
      frames: [Self.frame()]
    )
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      DemoPhotoResponse(
        id: "ghost",
        result: .species(speciesId: "no-such-bird", confidence: 0.9),
        caption: "",
        spokenLine: nil,
        delayMillis: 0
      ),
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    guard case let .photo(_, _, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the photo should still be on the timeline")
      return
    }
    #expect(identification == nil)
  }

  @Test func deliverPhotoResponse_afterTheStop_landsNothing() async {
    // A response composed across the stop lands nowhere: the review shows what the
    // session held when it ended, not what a delay was still carrying.
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.waitingPhotoPreset,
      frames: [Self.frame()]
    )
    await model.observeCamera()
    model.capturePhoto()
    let sessionKey = model.uiState.session.startedAt
    model.stopSession()

    await model.deliverPhotoResponse(.pastTheEnd, sessionKey: sessionKey, photoIndex: 0)

    guard case let .photo(_, _, _, _, _, _, identification) = model.uiState.session.events.first else {
      Issue.record("the photo should still be on the timeline")
      return
    }
    #expect(identification == .pending)
  }

  @Test func deliverAnswer_landsTheAnswerWithItsBird() async {
    let clock = FakeSessionClock()
    clock.advance(by: 12)
    let model = viewModel(audio: FakeAudioSource(), clock: clock)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)

    guard case let .answer(_, text, question, speciesId, commonName) = model.uiState.session.events.first else {
      Issue.record("a question should land as an answer")
      return
    }
    #expect(text == "That's likely a Green Jay.")
    #expect(question == "it's green with a yellow belly")
    #expect(speciesId == "green-jay")
    #expect(commonName == "Green Jay")
  }

  // MARK: - The display on the glasses

  @Test func observeSession_aBirdFinding_putsItsGalleryOnTheDisplay() async {
    let display = FakeGlassesDisplay()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.91)],
      glassesDisplay: display
    )

    await model.observeSession()

    await Self.settle(until: !display.shown.isEmpty)
    #expect(display.shown == ["green-jay"])
  }

  @Test func deliverPhotoResponse_putsTheScriptedBirdsGalleryOnTheDisplay() async {
    let display = FakeGlassesDisplay()
    let model = viewModel(
      audio: FakeAudioSource(),
      frames: [Self.frame()],
      glassesDisplay: display
    )
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      DemoPhotoResponse(
        id: "photo-1",
        result: .species(speciesId: "green-jay", confidence: 0.92),
        caption: "Green Jay",
        spokenLine: nil,
        delayMillis: 0
      ),
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    await Self.settle(until: !display.shown.isEmpty)
    #expect(display.shown == ["green-jay"])
  }

  @Test func deliverPhotoResponse_wordsLeaveTheDisplayAlone() async {
    // Words are the whole of what the app has to say — there is no bird to page through,
    // and a gallery for nobody would replace whatever the wearer was already shown.
    let display = FakeGlassesDisplay()
    let model = viewModel(
      audio: FakeAudioSource(),
      frames: [Self.frame()],
      glassesDisplay: display
    )
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      .pastTheEnd,
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    await Self.settle(until: model.uiState.session.events.count == 1)
    #expect(display.shown.isEmpty)
  }

  // ── The watcher's own voice ────────────────────────────────────────────

  @Test func answerAloud_whenTheUtteranceMatchesAPrompt_landsTheAnswer() async {
    // The whole exchange: the glasses hear a description, the words land on the log, and the
    // authored reply follows them.
    let clock = FakeSessionClock()
    clock.advance(by: 12)
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset, clock: clock)

    await model.answerAloud("It's green with a yellow belly")

    let events = model.uiState.session.events
    guard case let .speech(_, heard) = events.first else {
      Issue.record("the watcher's words did not land")
      return
    }
    #expect(heard == "It's green with a yellow belly")
    guard case let .answer(_, text, question, speciesId, _) = events.last else {
      Issue.record("the answer did not land")
      return
    }
    #expect(text == "That's likely a Green Jay.")
    // The watcher's own words, not the authored prompt that happened to match them.
    #expect(question == "It's green with a yellow belly")
    #expect(speciesId == "green-jay")
  }

  @Test func answerAloud_whenNothingMatches_landsTheUnmatchedLine() async {
    // The other half of the bargain. A miss is not silence: the app heard something, could
    // not place it, and says the preset's own line about it.
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset)

    await model.answerAloud("what a lovely afternoon")

    let events = model.uiState.session.events
    guard case let .speech(_, heard) = events.first else {
      Issue.record("the watcher's words did not land")
      return
    }
    #expect(heard == "what a lovely afternoon")
    guard case let .answer(_, text, question, speciesId, _) = events.last else {
      Issue.record("the unmatched line did not land")
      return
    }
    #expect(text == "Sorry — didn't catch that.")
    #expect(question == "what a lovely afternoon")
    #expect(speciesId == nil)
  }

  @Test func answerAloud_whenTheUnmatchedLineIsBlank_saysNothing() async {
    // The operator's off switch. A run listens for its whole length and hears the presenter
    // talking to the room too — clearing the line is how those sentences stop being answered,
    // and the words still land on the log.
    var quiet = Self.greenJayPreset
    quiet.unmatchedQuestion = "   "
    let model = viewModel(audio: FakeAudioSource(), armed: quiet)

    await model.answerAloud("what a lovely afternoon")

    #expect(model.uiState.session.events.count == 1)
    guard case let .speech(_, heard) = model.uiState.session.events.first else {
      Issue.record("the watcher's words did not land")
      return
    }
    #expect(heard == "what a lovely afternoon")
  }

  @Test func answerAloud_whenNothingIsArmed_logsTheWordsAndSaysNothing() async {
    // Identification switched off is a legal, intended state — the session listens and the
    // app never speaks. There is no preset, so there is no "didn't catch that" line either.
    let model = viewModel(audio: FakeAudioSource())

    await model.answerAloud("it's green with a yellow belly")

    #expect(model.uiState.session.events.count == 1)
    guard case let .speech(_, heard) = model.uiState.session.events.first else {
      Issue.record("the watcher's words did not land")
      return
    }
    #expect(heard == "it's green with a yellow belly")
  }

  @Test func answerAloud_whileTheAppIsTalking_landsNothing() async {
    // **The loop this exists to stop.** The app answers through the glasses speaker, the
    // glasses microphone hears it, and the recogniser cannot tell the two voices apart — so
    // an unguarded lane earns its own "didn't catch that" line an answer at a time, for ever.
    let voice = FakeSpokenOutput(isSpeaking: true)
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.greenJayPreset,
      spokenOutput: voice
    )

    await model.answerAloud("Sorry, didn't catch that.")

    #expect(model.uiState.session.events.isEmpty)
    #expect(voice.said.isEmpty)
  }

  @Test func answerAloud_inTheBeatAfterTheAppStopsTalking_landsNothing() async {
    // The tail, which is the half a plain `isSpeaking` check misses: the recogniser holds an
    // utterance open until it has heard silence, so the echo of a line lands *after* the line
    // has finished playing and the voice already reads as quiet.
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.greenJayPreset,
      spokenOutput: voice
    )

    // What every answered question does on its way out.
    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)
    let afterTheAnswer = model.uiState.session.events.count
    await model.answerAloud("That's likely a Green Jay.")

    #expect(model.uiState.session.events.count == afterTheAnswer)
  }

  @Test func answerAloud_onceTheEchoHasPassed_isHeardAgain() async {
    // And the lane opens again, or the guard would be a mute switch rather than a window.
    let clock = FakeSessionClock()
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.greenJayPreset,
      clock: clock,
      spokenOutput: voice
    )

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)
    clock.advance(by: 5)
    await model.answerAloud("green bird yellow belly")

    let heard = model.uiState.session.events.compactMap { event -> String? in
      guard case let .speech(_, text) = event else { return nil }
      return text
    }
    #expect(heard == ["green bird yellow belly"])
  }

  @Test func answerAloud_anEchoArrivingLate_isStillRecognisedAsTheAppsOwnVoice() async {
    // **The loop that survived the timing window.** The app answered, the tail expired, and
    // the echo landed five seconds later — a recogniser holds an utterance open until it has
    // heard silence, so how late an echo arrives is not something a number can cover.
    // Recorded exactly as the glasses misheard it: "Green Jay" came back as "green day".
    let clock = FakeSessionClock()
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset, clock: clock)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)
    let afterTheAnswer = model.uiState.session.events.count
    clock.advance(by: 5)
    await model.answerAloud("That's likely a green day.")

    #expect(model.uiState.session.events.count == afterTheAnswer)
  }

  @Test func answerAloud_aTwoWordRepeatOfTheAppsWords_isHeard() async {
    // **Where the check stops, and it is a real cost.** An utterance made only of words the
    // app just said is genuinely ambiguous — the wearer picking the bird's name back up is
    // the same string as the echo of it — so the line is drawn at length. Under three words
    // is let through and answered; a longer verbatim repeat is taken for the echo it usually
    // is. That trades a rare lost question for a loop, which is the right way round.
    let clock = FakeSessionClock()
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset, clock: clock)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)
    clock.advance(by: 5)
    await model.answerAloud("green jay")

    let heard = model.uiState.session.events.compactMap { event -> String? in
      guard case let .speech(_, text) = event else { return nil }
      return text
    }
    #expect(heard == ["green jay"])
  }

  @Test func answerAloud_longAfterTheAppSpoke_isHeardAgain() async {
    // A phrase stops being suspicious once enough time has passed for the wearer to have
    // chosen it themselves, or the guard would be a permanent ban on the app's own
    // vocabulary.
    let clock = FakeSessionClock()
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset, clock: clock)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)
    clock.advance(by: 30)
    await model.answerAloud("That's likely a green day.")

    let heard = model.uiState.session.events.compactMap { event -> String? in
      guard case let .speech(_, text) = event else { return nil }
      return text
    }
    #expect(heard == ["That's likely a green day."])
  }

  @Test func answerAloud_whenNothingWasSaid_landsNothing() async {
    // A recogniser that commits to an empty utterance is not the watcher asking anything,
    // and answering it would put "didn't catch that" on the log for silence.
    let model = viewModel(audio: FakeAudioSource(), armed: Self.greenJayPreset)

    await model.answerAloud("   ")

    #expect(model.uiState.session.events.isEmpty)
  }

  @Test func listenForQuestions_aPartialUtterance_isNotAnswered() async {
    // The same sentence lands several times as it develops, and matching on one of those
    // would fire an answer to half a question.
    let speech = FakeGlassesSpeech()
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.greenJayPreset,
      glassesSpeech: speech
    )

    let listening = Task { await model.listenForQuestions() }
    await Self.settle(until: speech.isListening)
    speech.say("It's green with a yellow belly", isFinal: false)
    await Self.settle(until: false)

    #expect(model.uiState.session.events.isEmpty)
    listening.cancel()
  }

  @Test func listenForQuestions_aFinalUtterance_reachesTheDirector() async {
    // The lane end to end: the recogniser commits, and the exchange lands.
    let speech = FakeGlassesSpeech()
    let model = viewModel(
      audio: FakeAudioSource(),
      armed: Self.greenJayPreset,
      glassesSpeech: speech
    )

    let listening = Task { await model.listenForQuestions() }
    await Self.settle(until: speech.isListening)
    speech.say("It's green with a yellow belly")
    await Self.settle(until: model.uiState.session.events.count >= 2)

    guard case let .answer(_, text, _, _, _) = model.uiState.session.events.last else {
      Issue.record("the answer did not land")
      return
    }
    #expect(text == "That's likely a Green Jay.")
    listening.cancel()
  }

  @Test func deliverAnswer_putsTheBirdsGalleryOnTheDisplay() async {
    let display = FakeGlassesDisplay()
    let model = viewModel(audio: FakeAudioSource(), glassesDisplay: display)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)

    await Self.settle(until: !display.shown.isEmpty)
    #expect(display.shown == ["green-jay"])
  }

  @Test func stopSession_takesTheGalleryDown() async {
    let display = FakeGlassesDisplay()
    let model = viewModel(audio: FakeAudioSource(), glassesDisplay: display)

    model.stopSession()

    await Self.settle(until: display.clearCount == 1)
    #expect(display.clearCount == 1)
  }

  @Test func observeGlasses_aPairWithAPanel_offersTheSend() async {
    // The offer is the whole of what this flag is for — a row on the log becomes pressable
    // only once there is glass for the press to reach.
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(audio: FakeAudioSource(), glassesSession: glasses)

    let observing = Task { await model.observeGlasses() }
    defer { observing.cancel() }
    await Self.settle(until: glasses.isListening)

    glasses.report(
      GlassesDeviceInfo(name: "Ray-Ban Display", isAvailable: true, hasDisplay: true)
    )

    await Self.settle(until: model.uiState.isDisplayAvailable)
    #expect(model.uiState.isDisplayAvailable)
  }

  @Test func observeGlasses_aPanelThatGoesOutOfReach_withdrawsTheSend() async {
    // The same rule the charge keeps: a display on a pair that has left the room is a panel
    // nothing can reach, and a row still inviting a tap would be promising a send that dies
    // in the repository.
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(audio: FakeAudioSource(), glassesSession: glasses)

    let observing = Task { await model.observeGlasses() }
    defer { observing.cancel() }
    await Self.settle(until: glasses.isListening)

    glasses.report(
      GlassesDeviceInfo(name: "Ray-Ban Display", isAvailable: true, hasDisplay: true)
    )
    await Self.settle(until: model.uiState.isDisplayAvailable)

    // Same pair, same panel — only the link has gone.
    glasses.report(
      GlassesDeviceInfo(name: "Ray-Ban Display", isAvailable: false, hasDisplay: true)
    )

    await Self.settle(until: !model.uiState.isDisplayAvailable)
    #expect(!model.uiState.isDisplayAvailable)
  }

  @Test func cardGoesToGlasses_needsALiveGlassesSessionAndNotJustAPair() {
    // The bug this exists to stop: a Display pair sitting on the table while the run is
    // deliberately on the phone, and every card flying to a panel nobody is looking through.
    var onDevice = RealtimeUiState()
    onDevice.isDisplayAvailable = true
    var onGlasses = onDevice
    onGlasses.isGlassesSessionLive = true
    var noPanel = RealtimeUiState()
    noPanel.isGlassesSessionLive = true

    #expect(!onDevice.cardGoesToGlasses)
    #expect(onGlasses.cardGoesToGlasses)
    #expect(!noPanel.cardGoesToGlasses)
  }

  @Test func showCard_withAPanelInReachButTheRunOnThePhone_opensTheCardOnThePhone() async {
    let display = FakeGlassesDisplay()
    let glasses = FakeReachableGlassesSession()
    let model = viewModel(
      audio: FakeAudioSource(),
      glassesSession: glasses,
      glassesDisplay: display
    )

    let observing = Task { await model.observeGlasses() }
    defer { observing.cancel() }
    await Self.settle(until: glasses.isListening)

    glasses.report(
      GlassesDeviceInfo(name: "Ray-Ban Display", isAvailable: true, hasDisplay: true)
    )
    await Self.settle(until: model.uiState.isDisplayAvailable)

    model.showCard("green-jay")

    await Self.settle(until: model.uiState.cardOnPhone != nil)
    #expect(model.uiState.cardOnPhone?.species.id == "green-jay")
    #expect(display.shown.isEmpty)
  }

  @Test func showCard_withNoPanel_opensTheCardOnThePhone() async {
    // **A press is never refused**, and the difference from the automatic push matters: that
    // one is allowed to land nowhere, because nobody asked for it. This one was asked for, so
    // where there is no glass the card opens here instead of nothing happening.
    let display = FakeGlassesDisplay()
    let model = viewModel(audio: FakeAudioSource(), glassesDisplay: display)

    model.showCard("green-jay")

    await Self.settle(until: model.uiState.cardOnPhone != nil)
    #expect(model.uiState.cardOnPhone?.species.id == "green-jay")
    #expect(display.shown.isEmpty)
  }

  @Test func dismissCard_putsThePhonesCardAway() async {
    let model = viewModel(audio: FakeAudioSource())
    model.showCard("green-jay")
    await Self.settle(until: model.uiState.cardOnPhone != nil)

    model.dismissCard()

    #expect(model.uiState.cardOnPhone == nil)
  }

  // MARK: - The app's own voice

  @Test func observeSession_aConfidentBirdFinding_saysItPlainly() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.92)],
      spokenOutput: voice
    )

    await model.observeSession()

    await Self.settle(until: !voice.said.isEmpty)
    #expect(voice.said == ["I just heard a Green Jay."])
  }

  @Test func observeSession_anUnsureBirdFinding_hedges() async {
    // The number stays on the timeline where it can be looked at; the ear gets the
    // confidence as grammar.
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.61)],
      spokenOutput: voice
    )

    await model.observeSession()

    await Self.settle(until: !voice.said.isEmpty)
    #expect(voice.said == ["I think I heard a Green Jay."])
  }

  @Test func observeSession_aBirdFindingWithItsOwnLine_saysThatInstead() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [
        .bird(
          speciesId: "green-jay",
          commonName: "Green Jay",
          confidence: 0.92,
          spokenLine: "Hear that? Green Jays hold this whole thicket."
        )
      ],
      spokenOutput: voice
    )

    await model.observeSession()

    await Self.settle(until: !voice.said.isEmpty)
    #expect(voice.said == ["Hear that? Green Jays hold this whole thicket."])
  }

  @Test func observeSession_aFindingThatIsNotABird_saysNothing() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      findings: [.speech(text: "it's green with a yellow belly")],
      spokenOutput: voice
    )

    await model.observeSession()

    #expect(voice.said.isEmpty)
  }

  @Test func deliverPhotoResponse_speaksTheRowsLine() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(),
      frames: [Self.frame()],
      spokenOutput: voice
    )
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      DemoPhotoResponse(
        id: "photo-1",
        result: .species(speciesId: "green-jay", confidence: 0.92),
        caption: "Green Jay",
        spokenLine: "Green Jay, 92 percent.",
        delayMillis: 0
      ),
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    await Self.settle(until: !voice.said.isEmpty)
    #expect(voice.said == ["Green Jay, 92 percent."])
  }

  @Test func deliverPhotoResponse_aRowWithNoLineSaysNothing() async {
    // The absence of a line is the whole of the "speak: on/off" switch the Director
    // deliberately does not have — a row is silent because nobody wrote it anything to say.
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(),
      frames: [Self.frame()],
      spokenOutput: voice
    )
    await model.observeCamera()
    model.capturePhoto()

    await model.deliverPhotoResponse(
      .pastTheEnd,
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )

    await Self.settle(until: model.uiState.session.events.count == 1)
    #expect(voice.said.isEmpty)
  }

  @Test func deliverAnswer_speaksTheAnswer() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(audio: FakeAudioSource(), spokenOutput: voice)

    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: 0)

    await Self.settle(until: !voice.said.isEmpty)
    #expect(voice.said == [Self.greenJayQuestion.answer])
  }

  @Test func observeSession_whileTheAppIsSpeaking_theStripTakesNoAudio() async {
    // The line comes back down the open microphone, and the app's own voice is not birdsong.
    let voice = FakeSpokenOutput(isSpeaking: true)
    let model = viewModel(
      audio: FakeAudioSource(
        openFor: .milliseconds(30),
        chunks: [AudioChunk(samples: [Float](repeating: 0.5, count: 2048))]
      ),
      spokenOutput: voice
    )

    await model.observeSession()

    #expect(model.sonogram.count == 0)
  }

  @Test func observeSession_onceTheLineIsFinished_theStripDrawsAgain() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(
      audio: FakeAudioSource(
        openFor: .milliseconds(30),
        chunks: [AudioChunk(samples: [Float](repeating: 0.5, count: 2048))]
      ),
      spokenOutput: voice
    )

    await model.observeSession()

    #expect(model.sonogram.count > 0)
  }

  @Test func stopSession_cutsTheLineShort() async {
    let voice = FakeSpokenOutput()
    let model = viewModel(audio: FakeAudioSource(), spokenOutput: voice)

    model.stopSession()

    #expect(voice.silences == 1)
  }

  // MARK: - Stopping, and the review

  @Test func stopSession_landsOnTheReviewWithTheClockReading() {
    let clock = FakeSessionClock()
    clock.advance(by: 42)
    let model = viewModel(audio: FakeAudioSource(), clock: clock)

    model.stopSession()

    #expect(model.uiState.review?.durationSeconds == 42)
    #expect(model.uiState.isReviewing)
  }

  @Test func stopSession_closesTheCameraOnTheWayOut() {
    let model = viewModel(audio: FakeAudioSource())
    model.openCamera()

    model.stopSession()

    #expect(!model.uiState.isCameraOpen)
  }

  @Test func toggleBirdKept_dropsABirdAndTakesItBack() {
    let model = viewModel(audio: FakeAudioSource())
    model.stopSession()

    model.toggleBirdKept(at: 14.0)
    #expect(model.uiState.review?.droppedBirds == [14.0])

    model.toggleBirdKept(at: 14.0)
    #expect(model.uiState.review?.droppedBirds == [])
  }

  // MARK: - Saving

  @Test func performSave_writesTheSessionAsALiveOuting() async {
    let clock = FakeSessionClock()
    clock.advance(by: 8)
    let journal = FakeJournalRepository()
    let here = Coordinate(latitude: 39.142, longitude: -84.506)
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      fix: here,
      findings: [.bird(speciesId: "american-robin", commonName: "American Robin", confidence: 0.87)],
      journal: journal,
      clock: clock
    )

    await model.observeSession()
    clock.advance(by: 4)
    await model.deliverAnswer(Self.greenJayQuestion, sessionKey: model.uiState.session.startedAt)
    model.stopSession()
    model.setReviewNotes("A bright morning")
    await model.performSave()

    guard let draft = journal.saved else {
      Issue.record("the save should reach the journal")
      return
    }
    #expect(draft.kind == .live)
    #expect(draft.durationMs == 12_000)
    #expect(draft.location.latitude == here.latitude)
    #expect(draft.location.longitude == here.longitude)
    #expect(draft.notes == "A bright morning")

    // The robin heard on the clock is a detection; the exchange is kept whole.
    let detection = draft.events.first { $0.type == .detection }
    #expect(detection?.speciesId == "american-robin")
    #expect(detection?.offsetMs == 8_000)
    #expect(abs((detection?.confidence ?? 0) - 0.87) < 0.0001)
    let exchange = draft.events.first { $0.type == .qa }
    #expect(exchange?.question == "it's green with a yellow belly")
    #expect(exchange?.answer == "That's likely a Green Jay.")

    // Both birds enter the life list: the robin confirming its detection, the jay —
    // reached through the watcher's own words — confirming nothing, like the wizard's.
    #expect(Set(draft.sightings.map(\.speciesId)) == ["american-robin", "green-jay"])
    #expect(draft.sightings.first { $0.speciesId == "american-robin" }?.confirming?.id == detection?.id)
    #expect(draft.sightings.first { $0.speciesId == "green-jay" }?.confirming == nil)

    #expect(model.uiState.review?.savedOutingId == "outing-1")
  }

  @Test func performSave_writesWhatTheSessionHeard() async {
    let clock = FakeSessionClock()
    clock.advance(by: 2)
    let journal = FakeJournalRepository()
    let model = viewModel(
      audio: FakeAudioSource(
        openFor: .milliseconds(30),
        chunks: [AudioChunk(samples: [Float](repeating: 0.5, count: 2048))]
      ),
      fix: Coordinate(latitude: 39.142, longitude: -84.506),
      journal: journal,
      clock: clock
    )

    await model.observeSession()
    model.stopSession()
    await model.performSave()

    // One unbroken stretch on one microphone: one media row, pinned where the clock
    // stood when it opened, its length measured from the samples themselves.
    let audio = journal.saved?.media.filter { $0.type == .audio } ?? []
    #expect(audio.count == 1)
    #expect(audio.first?.fileExtension == "wav")
    #expect(audio.first?.source == .phone)
    #expect(audio.first?.offsetMs == 2_000)
    #expect(audio.first?.durationMs == 128)
    #expect(((try? WavCodec.decode(audio.first?.bytes ?? Data())) ?? []).count == 2048)
  }

  @Test func performSave_writesAPhotosBirdAsSeenInThatPhoto() async {
    // `seen`, not `heard`: the photo is the evidence, and the journal has a column that
    // points a detection at the media row it was found in.
    let journal = FakeJournalRepository()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      fix: Coordinate(latitude: 39.142, longitude: -84.506),
      armed: Self.jayPhotoPreset,
      frames: [Self.frame()],
      journal: journal
    )

    await model.observeSession()
    await model.observeCamera()
    model.capturePhoto()
    await model.deliverPhotoResponse(
      Self.jayPhotoPreset.photoResponses[0],
      sessionKey: model.uiState.session.startedAt,
      photoIndex: 0
    )
    model.stopSession()
    await model.performSave()

    guard let draft = journal.saved else {
      Issue.record("the save should reach the journal")
      return
    }
    let photo = draft.media.first { $0.type == .photo }
    let detection = draft.events.first { $0.type == .detection }
    #expect(draft.events.filter { $0.type == .detection }.count == 1)
    #expect(detection?.speciesId == "green-jay")
    #expect(detection?.mediaId == photo?.id)
    #expect(detection?.offsetMs == nil)

    // And it can enter the life list, confirming the detection it came from.
    #expect(draft.sightings.count == 1)
    #expect(draft.sightings.first?.speciesId == "green-jay")
    #expect(draft.sightings.first?.confirming?.id == detection?.id)
  }

  @Test func performSave_leavesADroppedBirdOutOfTheSightings() async {
    let clock = FakeSessionClock()
    clock.advance(by: 8)
    let journal = FakeJournalRepository()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      fix: Coordinate(latitude: 39.142, longitude: -84.506),
      findings: [.bird(speciesId: "american-robin", commonName: "American Robin", confidence: 0.87)],
      journal: journal,
      clock: clock
    )

    await model.observeSession()
    model.stopSession()
    model.toggleBirdKept(at: 8.0)
    await model.performSave()

    // The timeline keeps the detection — it happened — but nothing enters the life list.
    guard let draft = journal.saved else {
      Issue.record("the save should reach the journal")
      return
    }
    #expect(draft.events.filter { $0.type == .detection }.count == 1)
    #expect(draft.sightings.isEmpty)
  }

  @Test func performSave_withoutAFix_asksOnceMoreThenDeclines() async {
    let journal = FakeJournalRepository()
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      fix: nil,
      journal: journal
    )

    await model.observeSession()
    model.stopSession()
    await model.performSave()

    // Declining leaves the journal untouched and the buttons live, and says why.
    #expect(journal.saved == nil)
    #expect(model.uiState.review?.saveError == .noLocationFix)
    #expect(model.uiState.review?.isSaving == false)
    #expect(model.uiState.review?.savedOutingId == nil)
  }

  @Test func performSave_whenTheWriteFails_saysSoAndStaysLive() async {
    let journal = FakeJournalRepository(failWith: FakeWriteError())
    let model = viewModel(
      audio: FakeAudioSource(openFor: .milliseconds(30)),
      fix: Coordinate(latitude: 39.142, longitude: -84.506),
      journal: journal
    )

    await model.observeSession()
    model.stopSession()
    await model.performSave()

    #expect(model.uiState.review?.saveError == .writeFailed)
    #expect(model.uiState.review?.isSaving == false)
  }

  // MARK: - The run belongs to the app

  @Test func start_whileARunIsInFlight_doesNotStartAnother() async {
    // The cover calls this on every appearance and the shell on every voice launch, and
    // neither knows about the other: the second call has to find the first run and join
    // it rather than open a second microphone under it.
    let audio = OpenCountingAudioSource()
    let model = viewModel(audio: audio)

    model.start()
    await Self.settle(until: model.uiState.isRunning)
    model.start()
    await Self.settle(until: false)

    #expect(model.uiState.isRunning)
    #expect(audio.opens == 1)

    model.stopSession()
    await Self.settle(until: !model.uiState.isRunning)
  }

  @Test func start_clearsTheLastRunsReview() async {
    // The view model outlives the cover; a fresh run must not open onto the review the last
    // one ended on.
    let model = viewModel(audio: FakeAudioSource())
    model.stopSession()

    model.start()
    await Self.settle(until: !model.uiState.isRunning && model.uiState.review == nil)

    #expect(model.uiState.review == nil)
  }

  @Test func stopSession_endsTheRun() async {
    // The stop is what closes the microphone. The run is the view model's own, so no
    // screen has to be showing — or be cancelled — for it to end.
    let audio = OpenCountingAudioSource()
    let model = viewModel(audio: audio)
    model.start()
    await Self.settle(until: model.uiState.isRunning)

    model.stopSession()
    await Self.settle(until: !model.uiState.isRunning)

    #expect(!model.uiState.isRunning)
    #expect(model.uiState.isReviewing)
    #expect(audio.closes == 1)
  }

  private func viewModel(
    audio: any AudioCaptureSource,
    fix: Coordinate? = nil,
    bearings: [Double] = [],
    elevations: [Double] = [],
    findings: [SessionFinding] = [],
    armed: DemoPreset? = nil,
    frames: [PreviewFrame] = [],
    journal: FakeJournalRepository = FakeJournalRepository(),
    clock: FakeSessionClock? = nil,
    camera: FakeCameraSource? = nil,
    glassesInput: any GlassesInputRepository = FakeGlassesInput(),
    glassesSpeech: any GlassesSpeechRepository = FakeGlassesSpeech(),
    glassesSession: any GlassesSessionRepository = FakeGlassesSession(),
    glassesDisplay: any GlassesDisplayRepository = FakeGlassesDisplay(),
    spokenOutput: any SpokenOutput = FakeSpokenOutput()
  ) -> RealtimeViewModel {
    RealtimeViewModel(
      audioSource: audio,
      previewSource: camera ?? FakeCameraSource(frames: frames),
      detector: FakeDetector(findings: findings),
      director: FakeDirector(armed: armed),
      birdCatalog: FakeCatalog(),
      journal: journal,
      glassesSession: glassesSession,
      glassesCamera: FakeGlassesCamera(),
      glassesInput: glassesInput,
      glassesSpeech: glassesSpeech,
      glassesDisplay: glassesDisplay,
      spokenOutput: spokenOutput,
      locationProvider: FakeLocationProvider(fix: fix),
      headingProvider: FakeHeadingProvider(bearings: bearings),
      gazeProvider: FakeGazeProvider(elevations: elevations),
      clock: clock ?? FakeSessionClock()
    )
  }

  /// Yields until `condition` holds.
  ///
  /// **Bounded, so a condition that never arrives fails the expectation after the call rather
  /// than hanging the suite** — the same bargain every hand-rolled yield loop here makes, named
  /// once. Observers subscribe and deliver inside child tasks, so nothing they do has happened
  /// when the task that runs them returns.
  private static func settle(until condition: @autoclosure () -> Bool) async {
    for _ in 0..<100 where !condition() {
      await Task.yield()
    }
  }

  /// The same, for a condition that arrives on a clock rather than on a yield — a wait the
  /// view model polls on its own timer. Sleeps a little between looks, up to `within`.
  private static func settle(until condition: @autoclosure () -> Bool, within: Duration) async {
    let deadline = ContinuousClock.now + within
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  /// One pixel, which is all a capture has to be for a timeline to hold it.
  private static func frame() -> PreviewFrame {
    let context = CGContext(
      data: nil,
      width: 1,
      height: 1,
      bitsPerComponent: 8,
      bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return PreviewFrame(image: context.makeImage()!)
  }

  /// A capture on the timeline, waiting — what the resolution tests resolve onto.
  private static func photoEvent(at: Double, index: Int) -> SessionEvent {
    .photo(
      at: at,
      index: index,
      image: frame().image,
      source: .phone,
      gazeContext: nil,
      bearingDeg: nil,
      identification: .pending
    )
  }

  /// A capture whose picture is still crossing from the glasses — a row with its space held
  /// open and nothing in it yet.
  private static func crossingPhotoEvent(at: Double, index: Int) -> SessionEvent {
    .photo(
      at: at,
      index: index,
      image: nil,
      source: .glasses,
      gazeContext: nil,
      bearingDeg: nil,
      identification: nil
    )
  }

  /// A preset whose first capture is answered with a named bird, at once.
  private static let jayPhotoPreset = DemoPreset(
    id: "photo-jay",
    name: "Photo Jay",
    photoResponses: [
      DemoPhotoResponse(
        id: "photo-1",
        result: .species(speciesId: "green-jay", confidence: 0.92),
        caption: "Green Jay",
        spokenLine: nil,
        delayMillis: 0
      )
    ],
    unmatchedQuestion: "Sorry — didn't catch that."
  )

  /// The same capture, answered far too late for a test to see it land. What pins the
  /// *waiting* half: with a zero delay the shutter's own delivery resolves the row before
  /// the assertion can read it.
  private static let waitingPhotoPreset = DemoPreset(
    id: "photo-jay",
    name: "Photo Jay",
    photoResponses: [
      DemoPhotoResponse(
        id: "photo-1",
        result: .species(speciesId: "green-jay", confidence: 0.92),
        caption: "Green Jay",
        spokenLine: nil,
        delayMillis: 60_000
      )
    ],
    unmatchedQuestion: "Sorry — didn't catch that."
  )

  /// A preset with the starter's one STT row, and the line a miss comes back with.
  private static let greenJayPreset = DemoPreset(
    id: "green-jay-question",
    name: "Green Jay Question",
    questions: [greenJayQuestion],
    unmatchedQuestion: "Sorry — didn't catch that."
  )

  /// The starter's STT row, with no composing delay so a test lands it at once.
  private static let greenJayQuestion = DemoQuestion(
    id: "green-yellow-belly",
    prompts: ["it's green with a yellow belly", "green bird yellow belly"],
    answer: "That's likely a Green Jay.",
    speciesId: "green-jay",
    delayMillis: 0
  )
}

/// Glasses that are never there: no registration read, no pair listed, a session that
/// refuses. The default the session runs over when a test is not about the glasses.
private struct FakeGlassesSession: GlassesSessionRepository {
  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { $0.finish() }
  }

  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) { $0.finish() }
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { $0.finish(throwing: GlassesError.notConnected) }
  }

  func access(_ permission: GlassesPermission) async -> GlassesAccess { .unknown }
}

/// Glasses that are registered, whose snapshots the test reports one at a time.
///
/// Driven rather than scripted, for the same reason ``FakeGlassesInput`` is: a list yielded up
/// front is a list the observer may have drained before the test ever looks, which makes any
/// assertion about the state *between* two snapshots unwritable. Reporting one and waiting for it
/// to land makes each step observable.
///
/// Both streams stay open, because both carry standing facts rather than events: a stream that
/// finished would let the observer's task group return before the screen believed anything.
private final class FakeReachableGlassesSession: GlassesSessionRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var devices: AsyncStream<GlassesDeviceInfo?>.Continuation?

  /// Whether the observer has subscribed yet — what a test waits on before reporting, since a
  /// snapshot with nobody listening is dropped by design.
  var isListening: Bool { lock.withLock { devices != nil } }

  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { $0.yield(.registered) }
  }

  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) { continuation in
      lock.withLock { devices = continuation }
    }
  }

  /// Hand the screen one snapshot. `nil` is a pair gone from the list entirely.
  func report(_ device: GlassesDeviceInfo?) {
    lock.withLock { devices }?.yield(device)
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { $0.finish(throwing: GlassesError.notConnected) }
  }

  func access(_ permission: GlassesPermission) async -> GlassesAccess { .unknown }
}

/// Glasses that will take a session: registered, in reach, the grant read granted, and a
/// session that opens and holds until the collector hangs up. What a test that starts a run
/// on the glasses drives it over.
private struct FakeGrantedGlassesSession: GlassesSessionRepository {
  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { $0.yield(.registered) }
  }

  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) {
      $0.yield(GlassesDeviceInfo(name: "Ray-Ban", isAvailable: true))
    }
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { $0.yield(.starting) }
  }

  func access(_ permission: GlassesPermission) async -> GlassesAccess { .granted }
}

/// The camera half of ``FakeGlassesSession`` — a shutter with nothing behind it.
private struct FakeGlassesCamera: GlassesCameraRepository {
  let honoursCaptureSettings = true

  func capturePhoto(
    format: PhotoFormat,
    resolution: CaptureResolution,
    quality: CaptureQuality
  ) async throws -> CapturedPhoto {
    throw GlassesError.notConnected
  }
}

/// The buttons half of ``FakeGlassesSession`` — a pair of glasses whose temple the test uses.
/// The stream stays open between gestures, which is what a real one does.
private final class FakeGlassesInput: GlassesInputRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var listeners: [AsyncStream<GlassesInputEvent>.Continuation] = []

  /// Whether anything has subscribed yet — what a test waits on before pressing, since a
  /// press with nobody listening is dropped by design.
  var isListening: Bool { lock.withLock { !listeners.isEmpty } }

  func inputEventStream() -> AsyncStream<GlassesInputEvent> {
    AsyncStream { continuation in
      lock.withLock { listeners.append(continuation) }
    }
  }

  func press() {
    for listener in lock.withLock({ listeners }) { listener.yield(.shutter) }
  }

  func swipeBack() {
    for listener in lock.withLock({ listeners }) { listener.yield(.back) }
  }
}

/// A recogniser a test speaks through. Quiet until something says otherwise, which is what every
/// scenario that is not about speech needs from it.
private final class FakeGlassesSpeech: GlassesSpeechRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var listeners: [AsyncStream<Transcription>.Continuation] = []

  /// Whether anything has subscribed yet — what a test waits on before speaking, since an
  /// utterance with nobody listening is dropped by design.
  var isListening: Bool { lock.withLock { !listeners.isEmpty } }

  func transcriptionStream() -> AsyncStream<Transcription> {
    AsyncStream { continuation in
      lock.withLock { listeners.append(continuation) }
    }
  }

  func speechStateStream() -> AsyncStream<GlassesSpeechState> {
    AsyncStream { continuation in
      continuation.yield(.listening)
      continuation.finish()
    }
  }

  func say(_ text: String, isFinal: Bool = true) {
    let heard = Transcription(text: text, isFinal: isFinal)
    for listener in lock.withLock({ listeners }) { listener.yield(heard) }
  }
}

/// A voice that remembers every line it was given rather than saying any of them, and can be
/// told to hold — ``isSpeaking`` is what a session reads while an announcement is in the air,
/// and setting it is how a test puts the app mid-sentence without one being said.
private final class FakeSpokenOutput: SpokenOutput, @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  private var silenceCount = 0
  private var speaking: Bool

  init(isSpeaking: Bool = false) {
    speaking = isSpeaking
  }

  var isSpeaking: Bool { lock.withLock { speaking } }
  var said: [String] { lock.withLock { lines } }
  var silences: Int { lock.withLock { silenceCount } }

  func speak(_ words: String) async {
    lock.withLock { lines.append(words) }
  }

  func silence() {
    lock.withLock { silenceCount += 1 }
  }
}

/// The display half of ``FakeGlassesSession`` — a wall that remembers every gallery that
/// lands on it, by the bird's id, and every time it was wiped.
private final class FakeGlassesDisplay: GlassesDisplayRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var shownIds: [String] = []
  private var clears = 0

  var shown: [String] { lock.withLock { shownIds } }
  var clearCount: Int { lock.withLock { clears } }

  func showGallery(for bird: SpeciesWithMedia, message: String?) async {
    lock.withLock { shownIds.append(bird.species.id) }
  }

  func clear() async {
    lock.withLock { clears += 1 }
  }
}

/// A clock with the hands moved by hand. The session's own is monotonic and cannot be wound, which
/// is the point of it — a test that needs four seconds to pass should not take four seconds.
///
/// ``start()`` is **counted, not obeyed**: the hands stay where the test put them. Zeroing here
/// would make it impossible to say "this session is already eighteen seconds old" and then run it,
/// which is the only interesting thing to say to a clock.
@MainActor
private final class FakeSessionClock: SessionClock {
  private(set) var elapsed: Double = 0
  private(set) var starts = 0

  func start() {
    starts += 1
  }

  func advance(by seconds: Double) {
    elapsed += seconds
  }
}

/// A microphone that only ever fails, or hears nothing at all.
///
/// `openFor` holds the stream open without producing a sample. That is what the location tests
/// need: the fix runs beside the microphone and is cancelled when it stops, so a stream that ends
/// the instant it opens would race the GPS rather than test it.
private struct FakeAudioSource: AudioCaptureSource {
  var kind: CaptureSourceKind = .phone
  var failure: AudioCaptureError?
  var openFor: Duration?
  var chunks: [AudioChunk] = []

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      if let failure {
        continuation.finish(throwing: failure)
        return
      }
      for chunk in chunks { continuation.yield(chunk) }
      guard let openFor else {
        continuation.finish()
        return
      }
      let task = Task {
        try? await Task.sleep(for: openFor)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// A microphone that opens, says nothing, and stays open until it is cancelled — counting the
/// opens and the closes, which is what a test of who owns the run reads.
private final class OpenCountingAudioSource: AudioCaptureSource, @unchecked Sendable {
  let kind: CaptureSourceKind = .phone
  private let lock = NSLock()
  private var opened = 0
  private var closed = 0

  var opens: Int { lock.withLock { opened } }
  var closes: Int { lock.withLock { closed } }

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    lock.withLock { opened += 1 }
    return AsyncThrowingStream { continuation in
      continuation.onTermination = { [self] _ in lock.withLock { closed += 1 } }
    }
  }
}

/// A GPS with one answer ready: a fix, or the `nil` that stands for every way of not knowing.
private struct FakeLocationProvider: LocationProvider {
  let fix: Coordinate?

  func currentCoordinate() async -> Coordinate? { fix }
}

/// A compass with a script. Empty is the phone that has none — an ended stream, not an error.
private struct FakeHeadingProvider: HeadingProvider {
  let bearings: [Double]

  func headingStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      for bearing in bearings { continuation.yield(bearing) }
      continuation.finish()
    }
  }
}

/// A tilt with a script. Empty is the phone that cannot answer — an ended stream, not an error.
private struct FakeGazeProvider: GazeProvider {
  let elevations: [Double]

  func gazeStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      for elevation in elevations { continuation.yield(elevation) }
      continuation.finish()
    }
  }
}

/// A camera that never opens. The session does not need one.
private struct FakeCameraSource: CameraPreviewSource {
  let kind = CaptureSourceKind.phone

  /// What the shutter has to take, when a test is about the photo lane. Empty is the camera
  /// that never opens, which is what every other test wants.
  var frames: [PreviewFrame] = []

  /// How many times the light has been asked for — what a doubled capture shows up as.
  ///
  /// Behind a reference because ``CameraPreviewSource/setTorch(_:)`` is not mutating and this
  /// is a value. The counting is the mirror; where the box lives is the plumbing.
  var torch = TorchLog()
  var torchOns: Int { torch.ons }

  func previewStream() -> AsyncThrowingStream<PreviewFrame, Error> {
    AsyncThrowingStream { continuation in
      for frame in frames { continuation.yield(frame) }
      continuation.finish()
    }
  }

  func setTorch(_ isOn: Bool) {
    if isOn { torch.ons += 1 }
  }
}

/// The counter behind ``FakeCameraSource/torchOns``. Single-threaded by construction — the view
/// model is main-actor and so is every test that reads this.
private final class TorchLog: @unchecked Sendable {
  var ons = 0
}

/// A detector with a script, or with nothing scripted at all.
private struct FakeDetector: SessionDetector {
  var findings: [SessionFinding] = []

  func findingStream() -> AsyncThrowingStream<SessionFinding, Error> {
    AsyncThrowingStream { continuation in
      for finding in findings { continuation.yield(finding) }
      continuation.finish()
    }
  }
}

/// A Director armed with exactly `armed`, or with nothing. The cue methods keep the real
/// contract — the Nth row, the fixed past-the-end answer, nil when nothing is armed — so
/// the view model's handling is tested against the shape it will actually be handed.
private struct FakeDirector: DemoDirector {
  var armed: DemoPreset?

  func findingStream() -> AsyncThrowingStream<SessionFinding, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func response(toPhotoAt index: Int) -> DemoPhotoResponse? {
    guard let preset = armed else { return nil }
    guard preset.photoResponses.indices.contains(index) else { return .pastTheEnd }
    return preset.photoResponses[index]
  }

  /// Matched by plain containment on the lowercased transcript. The real normalise-and-contain
  /// policy is `PresetDemoDirector`'s and has scenarios of its own; what a session needs from
  /// here is only *matched* or *not*.
  func answer(to transcript: String) -> DemoQuestion? {
    let heard = transcript.lowercased()
    return armed?.questions.first { question in
      question.prompts.contains { heard.contains($0.lowercased()) }
    }
  }
}

/// Two birds and nothing else — what cue-landed answers resolve names against.
private struct FakeCatalog: BirdCatalogRepository {

  private let birds = [
    "american-robin": "American Robin",
    "green-jay": "Green Jay",
  ]

  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? {
    guard let commonName = birds[speciesId] else { return nil }
    return SpeciesWithMedia(
      species: Species(
        id: speciesId,
        commonName: commonName,
        scientificName: "Testus \(speciesId)",
        wikidataId: nil,
        ebirdSpeciesCode: nil,
        familyName: "Testidae",
        browseOrder: 10,
        groupName: "Test Birds",
        sizeClass: 3,
        conservationStatus: nil,
        aboutText: "",
        habitatText: ""
      ),
      media: []
    )
  }

  func allSpecies() async throws -> [Species] { [] }
  func browseGroups() async throws -> [SpeciesGroup] { [] }
  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] { [] }
  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? { nil }
  func seedVersion() async throws -> Int? { nil }
}

/// A journal that remembers the one draft handed to it — or refuses, when told to fail.
/// `@unchecked Sendable` because the tests drive it from one actor at a time.
private final class FakeJournalRepository: JournalRepository, @unchecked Sendable {
  private let failWith: (any Error)?
  private(set) var saved: OutingDraft?

  init(failWith: (any Error)? = nil) {
    self.failWith = failWith
  }

  func journalStream() -> AsyncThrowingStream<[OutingWithChildren], Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func lifeListCountStream() -> AsyncThrowingStream<Int, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func findById(_ outingId: String) async throws -> OutingWithChildren? { nil }

  func saveOuting(_ draft: OutingDraft) async throws -> String {
    if let failWith { throw failWith }
    saved = draft
    return "outing-1"
  }

  func updateNotes(outingId: String, notes: String?) async throws {}
  func delete(outingId: String) async throws {}
  func deleteAll() async throws {}
}

private struct FakeWriteError: Error {}
