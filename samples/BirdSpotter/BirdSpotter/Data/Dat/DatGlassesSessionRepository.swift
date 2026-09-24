/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesSessionRepository.swift
//  birdspotter
//

import AVFoundation
import Foundation
import MWDATCamera
import MWDATCore
import MWDATDisplay
import MWDATInputs
import MWDATMockDevice
import MWDATMotion
import MWDATSpeech

/// The DAT-backed ``GlassesSessionRepository`` — the one class a live SDK session actually
/// lives in.
///
/// A session here is three SDK moves held to one cold-stream lease: create a
/// `DeviceSession` over `AutoDeviceSelector`, start it, and — the moment the device reports
/// started — attach the `Camera` capability and start the shutter it owns. The video half of
/// that capability is never looked at: frames and stills compete for the one sensor and cannot
/// be captured at the same time, and this app has never wanted a frame. What the stream does
/// carry that the app wants is the glasses' **microphone**, which rides it as audio — see
/// ``audioChunksFromActiveSession()``. ``DatGlassesCameraRepository`` reaches the shutter
/// through ``captureThroughActiveCamera(format:)``, which is here because the handles are here.
nonisolated final class DatGlassesSessionRepository: GlassesSessionRepository, @unchecked Sendable {

  /// The running session's handles: written by the one `sessionStream()` collector, read
  /// by the shutter. `lock` is the whole concurrency story — nothing here awaits while
  /// holding it.
  private var activeSession: DeviceSession?
  private var activeCamera: Camera?
  private var activeInputs: Inputs?
  private var activeMotion: Motion?
  private var activeSpeech: Speech?
  private var activeDisplay: Display?
  /// The pair the session was opened on, kept so the display attach can ask whether this
  /// pair has one — the capability is hardware most pairs do not carry.
  private var activeDeviceIdentifier: DeviceIdentifier?
  private var cameraStateToken: (any AnyListenerToken)?
  private var streamStateToken: (any AnyListenerToken)?
  /// The one reader of the capability's event stream — see ``attachInputsIfNeeded(to:)``.
  private var inputsDrain: Task<Void, Never>?
  /// The one reader of the motion capability's samples — see ``attachMotionIfNeeded(to:)``.
  private var motionDrain: Task<Void, Never>?
  /// The task bringing the sensor back after something else on the link put it down — see
  /// ``reviveMotion()``. One at a time; `nil` whenever nothing is being waited on.
  private var motionRevival: Task<Void, Never>?
  /// The same, for the button — see ``reviveInputs()``.
  private var inputsRevival: Task<Void, Never>?
  /// The same, for the camera — see ``reviveCamera()``.
  private var cameraRevival: Task<Void, Never>?
  /// The same, for the recogniser — see ``reviveSpeech()``.
  private var speechRevival: Task<Void, Never>?
  /// The task asking the display capability to attach on the lease with no camera frames to
  /// gate the asking — see ``attachDisplayWithPatience(to:announcingTo:)``. Nil whenever
  /// nothing is asking.
  private var displayPatience: Task<Void, Never>?
  /// Whether the button has ever been listening this run. `inactive` is both the state the
  /// capability is born in and the state it dies in, and only the second one is worth acting on.
  private var inputsHasActivated = false
  /// Everyone listening for a reading, by subscription — the same fan-out the presses use, and
  /// for the same reason: the capability's stream has room for one reader.
  private var motionListeners: [UUID: AsyncStream<GlassesMotionSample>.Continuation] = [:]
  /// The motion capability's subscriptions, which live as long as the sensor does — see
  /// ``attachMotionIfNeeded(to:)``.
  private let motionTokens = ListenerTokenBag()
  /// The inputs capability's subscriptions, which live as long as the button does — see
  /// ``attachInputsIfNeeded(to:)``.
  private let inputsTokens = ListenerTokenBag()
  /// The display capability's subscriptions, which live as long as the display does — see
  /// ``attachDisplayIfNeeded(to:)``.
  private let displayTokens = ListenerTokenBag()
  /// The speech capability's subscriptions, which live as long as the recogniser does — see
  /// ``attachSpeechIfNeeded(to:)``.
  private let speechTokens = ListenerTokenBag()
  /// Everyone listening for a transcript, by subscription — the same fan-out the presses and the
  /// readings use, and for the same reason: the capability announces to one place.
  private var transcriptionListeners: [UUID: AsyncStream<Transcription>.Continuation] = [:]
  /// Everyone watching where the recogniser is, by subscription.
  private var speechStateListeners: [UUID: AsyncStream<GlassesSpeechState>.Continuation] = [:]
  /// Where the recogniser is, held rather than only announced: a screen that opens mid-session
  /// has to be told what is already true, and a stream that carried only *changes* would leave
  /// it looking at `idle` while the glasses were listening. Reset with the session that owned it.
  private var speechState: GlassesSpeechState = .idle
  /// Whether the recogniser has ever been listening this run. `stopped` is both the state the
  /// capability is born in and the state it dies in, and only the second one is worth going back
  /// for.
  private var speechHasStarted = false
  /// Which sources this run's motion feed has been heard from, so ``describeOnce(_:)`` says its
  /// piece once each instead of five times a second. Cleared when the capability attaches — the
  /// question it answers is about this pair on this run.
  private var motionSourcesHeard: Set<MWDATMotion.MotionSource> = []
  /// When ``describeEvery(_:)`` last wrote a line, on the sensor's own clock. Zero until the
  /// first sample, so the first one always prints.
  private var lastMotionLogMillis: Int64 = 0
  /// Everyone listening for a press, by subscription. A dictionary rather than one
  /// continuation because the capability hands over a stream that can only be drained once,
  /// so the drain is here and the fanning out is this.
  private var inputListeners: [UUID: AsyncStream<GlassesInputEvent>.Continuation] = [:]
  /// The photo capability's subscriptions, which live as long as the camera does — see
  /// ``observePhotoCaptures(_:announcingTo:)``.
  private let photoTokens = ListenerTokenBag()
  /// Whether the shutter is up. **This is what the session announces on**, not the camera
  /// underneath it: the hardware being awake says nothing about whether the capability that
  /// takes photographs has finished starting, and the shutter is the only thing this app
  /// wants the glasses for.
  private var isPhotoStarted = false
  /// Whether the camera has been up at all this session. Its `stopped` is both the state it
  /// is born in and the state it dies in, and only the second one means anything.
  private var cameraHasStarted = false
  /// Whether the shutter has already been asked to start this session — see
  /// ``startPhotoIfNeeded()``.
  private var photoStartRequested = false
  /// Whether the video stream was put down on purpose — see ``releaseVideoStream()``. Its
  /// `stopped` is otherwise indistinguishable from the glasses going away, and that reading
  /// ends the session.
  private var streamStopIntended = false
  /// Whether this session's stream was opened with the glasses' microphone on it — decided once,
  /// before the camera attaches, from Meta AI's microphone grant. See
  /// ``audioChunksFromActiveSession()``.
  private var streamCarriesAudio = false
  /// Everyone listening to the glasses' microphone, by subscription — the same fan-out the
  /// readings use, and for the same reason: the stream announces to one place.
  private var audioListeners: [UUID: AsyncThrowingStream<AudioChunk, Error>.Continuation] = [:]
  /// The stream's audio and error subscriptions, which live as long as the camera does.
  private let audioTokens = ListenerTokenBag()
  /// Turns whatever buffers the stream hands over into the app's one format. Built on the
  /// first frame, once the stream has said what that format actually is — see
  /// ``receive(audio:)``.
  private var audioConverter: AVAudioConverter?
  /// Whether a buffer has arrived since the stream was last started — so each start writes one
  /// line saying the microphone is back, and a start that never does is visible by its absence.
  private var audioHeardSinceStart = false
  /// The task waiting to see whether a restarted stream speaks again — see
  /// ``bringStreamBack(_:)``. Nil whenever nothing is waiting.
  private var audioRevival: Task<Void, Never>?
  /// The one format the glasses' microphone is handed on in — see ``captureSampleRate``.
  private let glassesAudioFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Double(captureSampleRate),
    channels: 1,
    interleaved: false
  )
  /// The photograph currently crossing, when one is — held so the link going down can end its
  /// wait at once. See ``failPendingPhoto()``.
  private var pendingPhoto: AsyncStream<Data>.Continuation?
  private let lock = NSLock()

  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { continuation in
      let task = Task {
        for await state in Wearables.shared.registrationStateStream() {
          let mapped = GlassesRegistrationState(state)
          // The first thing to check when the glasses will not answer, and the one
          // reading that is otherwise invisible — the Settings card shows it, but
          // only while somebody is looking at Settings.
          BirdLog.info(.glasses, "registration — \(mapped)")
          continuation.yield(mapped)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The pair this app is about, and whether its link is up **right now**.
  ///
  /// **Every paired device is watched, not just the first one listed.** A developer's
  /// phone routinely has several pairs registered — Display glasses, a Ray-Ban, an older
  /// pair — of which at most one is connected at a time, and Meta AI lists them in no
  /// order the app should trust. Reporting on `identifiers.first` means reporting on
  /// whichever pair happens to be at the head of the list, which is very often a pair
  /// sitting in a drawer. See ``preferred(among:)`` for the choice.
  ///
  /// Two sources, because the SDK splits them: `devicesStream()` fires when the *list*
  /// changes, and the per-device listeners fire when one connects or its compatibility
  /// resolves. Reading either property once per list change is not enough — a pair is
  /// listed the instant the app launches, while its link and its name arrive later, so a
  /// one-shot read pins a blank, disconnected pair forever.
  ///
  /// Neither pairing would be needed if the SDK published the device as a stream that
  /// re-emitted on every change; on this side it does not.
  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    // The element type spelled out: with an optional element, a bare trailing closure
    // resolves to AsyncStream's `unfolding:` initializer instead of this build one.
    AsyncStream(GlassesDeviceInfo?.self) { continuation in
      let task = Task {
        // Every reading is taken from the device objects themselves, never from
        // values captured when they were handed over. `Device` is a class whose
        // properties fill in asynchronously.
        let publish: @Sendable ([Device]) -> Void = { devices in
          // Logged as well as published: "not reachable" has several causes that
          // look identical on screen, and the roster is what tells them apart on
          // a phone nobody can attach a debugger to mid-demo. Filter the
          // Diagnostics screen to Glasses, or grep for `glasses reading`.
          let roster =
            devices
            .map { "\($0.nameOrId())=\(String(describing: $0.linkState))" }
            .joined(separator: ", ")
          guard let chosen = Self.preferred(among: devices) else {
            BirdLog.info(.glasses, "glasses reading — no devices paired")
            continuation.yield(nil as GlassesDeviceInfo?)
            return
          }
          BirdLog.info(
            .glasses,
            """
            glasses reading — paired: \(devices.count) [\(roster)] \
            · chosen: "\(chosen.nameOrId())", \
            link: \(String(describing: chosen.linkState)), \
            compatibility: \(chosen.compatibility().displayString), \
            don: \(String(describing: chosen.donState)), \
            battery: \(chosen.batteryLevel.map(String.init) ?? "?"), \
            thermal: \(String(describing: chosen.thermalLevel))
            """
          )
          continuation.yield(
            GlassesDeviceInfo(
              // `nameOrId()` is the SDK's own fallback and it is right for a
              // device *picker*, where the identifier at least distinguishes two
              // pairs. On a status row it is 32 characters of hex wrapped over
              // two lines, so the generic label reads better and the identifier
              // stays in the log line above, which is where it is any use.
              name: chosen.name.isEmpty ? "Meta glasses" : chosen.name,
              isAvailable: chosen.linkState == .connected,
              compatibility: GlassesCompatibility(chosen.compatibility()),
              isWorn: chosen.donState.asWorn,
              // Zero crosses as unknown, not as a reading — a control channel
              // still warming up reports it, and an empty pair would not be
              // connected. Mapping it out is what lets a number here be trusted.
              batteryLevel: chosen.batteryLevel.flatMap { $0 > 0 ? $0 : nil },
              isCharging: chosen.chargingState.asCharging,
              thermal: chosen.thermalLevel.asGlassesThermal,
              // Read off the device's own description rather than the link, so it
              // is answered for a pair that is merely known — which is what lets a
              // screen decide whether to offer a send before a session exists.
              hasDisplay: chosen.supportsDisplay()
            ))
        }

        var tokens: [any AnyListenerToken] = []

        for await identifiers in Wearables.shared.devicesStream() {
          for token in tokens { await token.cancel() }
          tokens.removeAll()

          // The stream carries identifiers; the device behind one is a lookup.
          let devices = identifiers.compactMap {
            Wearables.shared.deviceForIdentifier($0)
          }
          publish(devices)

          // Listened to on *every* pair, because the one that matters is the one
          // that connects, and which that is only becomes clear when it does. The
          // listeners re-read everything rather than trusting their argument, so
          // whichever fires carries the others' news too — and they hold the
          // devices, which is what keeps the subscriptions alive.
          for device in devices {
            tokens.append(device.addLinkStateListener { _ in publish(devices) })
            tokens.append(device.addCompatibilityListener { _ in publish(devices) })
            // Wear, battery and charging ride the same snapshot, delivered
            // once on subscribe and again on every change — which is what
            // keeps the settings rows live while somebody is looking at them.
            tokens.append(device.addDeviceStateListener { _ in publish(devices) })
          }
        }

        for token in tokens { await token.cancel() }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// How good a candidate a pair is, lower being better — the **worn** connected pair first,
  /// then any connected pair, then one merely vouched for, then anything else.
  ///
  /// Two pairs can be connected at once — a display pair and another — and the one on the
  /// wearer's face is the one a launch is spoken from and a session should open on. Don state
  /// is the tie-break that names it; without it the choice falls to list position, which
  /// answers a different question. A fuller picker is still its own feature.
  private static func rank(_ device: Device) -> Int {
    if device.linkState == .connected && device.donState == .donned { return 0 }
    if device.linkState == .connected { return 1 }
    if device.compatibility() == .compatible { return 2 }
    return 3
  }

  /// Which of several paired pairs this app is about.
  private static func preferred(among devices: [Device]) -> Device? {
    devices.min { rank($0) < rank($1) }
  }

  /// The same choice, made synchronously against the SDK's current list — what a session
  /// is opened on, so the pair the status screen names is the pair the session runs on.
  /// The voice channel starts on it too (see ``DatGlassesVoiceRepository``), so a launch
  /// is answered from the pair the rest of the app is already about.
  static func preferredIdentifier() -> DeviceIdentifier? {
    let devices = Wearables.shared.devices.compactMap {
      Wearables.shared.deviceForIdentifier($0)
    }
    return preferred(among: devices)?.identifier
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [self] in
        do {
          let wearables = Wearables.shared

          // **Named, not auto-chosen.** `AutoDeviceSelector` fills its active device
          // from the device stream asynchronously, so one built at the moment of the
          // tap is empty and the session fails `noEligibleDevice` — the race an
          // asynchronous selector always leaves open. Naming the pair also closes a
          // subtler gap: the status screen and the session would otherwise be free to
          // disagree about which glasses these are.
          guard let identifier = Self.preferredIdentifier() else {
            BirdLog.error(.glasses, "glasses session — no paired device to run it on")
            continuation.finish(throwing: GlassesError.notConnected)
            return
          }
          // **Asked before the camera attaches, because the answer is baked into the
          // stream.** Audio is part of the configuration the camera is added with, and
          // a stream asked for audio the wearer never allowed is a stream that may not
          // come up at all — taking the shutter with it. So the microphone is only put
          // on the stream when the grant is known to be there; without it the session
          // runs exactly as it would have, and the listening stays on the phone.
          //
          // **Never on the mock kit.** Its camera plays a file or the phone's own
          // camera and has no audio feed behind it, so a stream asked for audio there
          // is at best silent and at worst a code path the mock never expected to
          // run. The phone's microphone is the honest answer on a mock pair.
          let hearsGlasses: Bool
          if MockDeviceKit.shared.isEnabled {
            hearsGlasses = false
            BirdLog.info(.glasses, "glasses session — mock pair; the stream carries no audio")
          } else {
            hearsGlasses = await access(.microphone) == .granted
            if !hearsGlasses {
              BirdLog.warning(
                .glasses,
                "glasses session — no microphone grant; the stream carries no audio"
              )
            }
          }
          lock.withLock { streamCarriesAudio = hearsGlasses }
          let session = try wearables.createSession(
            deviceSelector: SpecificDeviceSelector(device: identifier)
          )
          lock.withLock {
            activeSession = session
            activeDeviceIdentifier = identifier
          }
          // Back to nothing-has-asked-yet, so a screen watching across two runs is not
          // still reading the ending of the one before this.
          publish(speechState: .idle)
          BirdLog.info(.glasses, "glasses session — starting on \(identifier)")
          try session.start()

          // The session's own failures, which `start()` never throws: it returns the
          // moment the request is away, and everything the glasses have to say about
          // whether they can host the session arrives afterwards, over the link.
          // Ending the run is left to the state stream — a session that fails is a
          // session that stops, and it will say so — except for the one failure that
          // is somebody's to fix, which this ends with the reason attached.
          let errorRun = Task {
            for await error in session.errorStream() {
              BirdLog.error(.glasses, "glasses session — \(error.description)")
              guard error == .datAppOnTheGlassesUpdateRequired else { continue }
              continuation.finish(throwing: GlassesError.glassesUpdateRequired)
            }
          }
          defer { errorRun.cancel() }

          for await state in session.stateStream() {
            if Task.isCancelled { break }
            // Every transition, because the shape of a stall is which state it
            // stopped in — a session parked on `starting` and one that reached
            // `started` and never had a camera attach are different bugs
            // that look identical from the pill on screen.
            BirdLog.debug(.glasses, "glasses session — \(String(describing: state))")
            switch state {
            case .starting:
              continuation.yield(.starting)
            case .started:
              // **`started` means the session exists, not that the glasses are
              // reachable.** The device is still arriving at this point — the
              // camera says so out loud, spending its first beats in
              // `waitingForDevice` — and a capability started into that window
              // fails with `deviceDisconnected` and does not try again.
              //
              // So only the camera is attached here, because only the camera is
              // willing to wait. The sensors follow it, once its frames have
              // proved the device is really there — see
              // ``attachSensorsIfNeeded(to:)``. Announcing `started` waits for
              // the shutter, for the same reason.
              attachCameraIfNeeded(to: session, announcingTo: continuation)
            case .paused:
              continuation.yield(.paused)
            case .stopping:
              continuation.yield(.stopping)
            case .stopped:
              continuation.yield(.stopped)
              continuation.finish()
              return
            default:
              break // idle — the state a session is born in, before start()
            }
          }
          continuation.finish()
        } catch let error as DeviceSessionError {
          // Named in the log, because the cases are the diagnosis: a session that
          // will not open reads the same on screen whether nothing was eligible,
          // one was already running, or the glasses want a DAT update.
          BirdLog.error(.glasses, "glasses session — \(error.description)")
          continuation.finish(throwing: error.asGlassesError)
        } catch {
          BirdLog.error(.glasses, "glasses session failed", error)
          continuation.finish(throwing: GlassesError.notConnected)
        }
      }
      continuation.onTermination = { [self] _ in
        task.cancel()
        releaseLink()
      }
    }
  }

  /// The display-only lease — ``GlassesSessionRepository/displaySessionStream()``.
  ///
  /// The same three SDK moves as ``sessionStream()`` — create on the named pair, start,
  /// attach — with everything the display does not need left dark: no camera lit, no
  /// stream started, no sensors, no recogniser. What the full lease loses with them is
  /// its proof that the device has really arrived, which is why the attach below needs
  /// patience of its own.
  ///
  /// The teardown is the display's alone. The other capabilities were never attached, and
  /// asking a session to remove what it never grew is a log line of failures pretending
  /// to be a cleanup.
  func displaySessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [self] in
        do {
          guard let identifier = Self.preferredIdentifier() else {
            BirdLog.error(.glasses, "display session — no paired device to run it on")
            continuation.finish(throwing: GlassesError.notConnected)
            return
          }
          let session = try Wearables.shared.createSession(
            deviceSelector: SpecificDeviceSelector(device: identifier)
          )
          lock.withLock {
            activeSession = session
            activeDeviceIdentifier = identifier
          }
          BirdLog.info(.glasses, "display session — starting on \(identifier)")
          try session.start()

          // The session's own failures, which `start()` never throws — the same
          // bargain the full lease strikes: the state stream ends the run, except
          // for the one failure that is somebody's to fix.
          let errorRun = Task {
            for await error in session.errorStream() {
              BirdLog.error(.glasses, "display session — \(error.description)")
              guard error == .datAppOnTheGlassesUpdateRequired else { continue }
              continuation.finish(throwing: GlassesError.glassesUpdateRequired)
            }
          }
          defer { errorRun.cancel() }

          for await state in session.stateStream() {
            if Task.isCancelled { break }
            BirdLog.debug(.glasses, "display session — \(String(describing: state))")
            switch state {
            case .starting:
              continuation.yield(.starting)
            case .started:
              // `started` is not announced here — on this lease the word means
              // *the panel can be drawn on*, and only the attach knows when
              // that turned true. See ``attachDisplayWithPatience(to:announcingTo:)``.
              attachDisplayWithPatience(to: session, announcingTo: continuation)
            case .paused:
              continuation.yield(.paused)
            case .stopping:
              continuation.yield(.stopping)
            case .stopped:
              continuation.yield(.stopped)
              continuation.finish()
              return
            default:
              break // idle — the state a session is born in, before start()
            }
          }
          continuation.finish()
        } catch let error as DeviceSessionError {
          BirdLog.error(.glasses, "display session — \(error.description)")
          continuation.finish(throwing: error.asGlassesError)
        } catch {
          BirdLog.error(.glasses, "display session failed", error)
          continuation.finish(throwing: GlassesError.notConnected)
        }
      }
      continuation.onTermination = { [self] _ in
        task.cancel()
        releaseDisplayLease()
      }
    }
  }

  /// One of Meta AI's grants, as far as it can be read right now.
  ///
  /// **A thrown error here is not a denial — it is usually "nothing is connected".** DAT
  /// reads the grant off the glasses themselves, so with no pair on the link the check
  /// throws `noDeviceWithConnection` rather than answering; `noDevice` (none paired at
  /// all) and `metaAINotInstalled` land the same way, and none of the three is the wearer
  /// saying no. Every failure therefore becomes ``GlassesAccess/unknown``, and the
  /// specific error goes to the log, where it is the diagnosis.
  ///
  /// The success side has only two answers to give: DAT's `PermissionStatus` is
  /// `granted`/`denied` and carries no not-determined, so a grant never asked for arrives
  /// here as `denied`.
  func access(_ permission: GlassesPermission) async -> GlassesAccess {
    let name = permission.logName
    do {
      let status = try await Wearables.shared.checkPermissionStatus(permission.datPermission)
      BirdLog.info(.glasses, "\(name) access — \(status == .granted ? "granted" : "denied")")
      return status == .granted ? .granted : .denied
    } catch {
      // Still `info`, not `error`: with nothing on the link this throws every time it
      // is asked, and it is not a failure — see the doc above.
      BirdLog.info(.glasses, "\(name) access unreadable — \(String(describing: error))")
      return .unknown
    }
  }

  /// One photograph through the running shutter, for ``DatGlassesCameraRepository``.
  ///
  /// The ask and the answer are separate: `capturePhoto` fires, and the finished image lands
  /// on `photoDataPublisher` once it has crossed the Bluetooth link. This stitches the two
  /// back into the one suspending call the domain promises. The arrival is delivered by the
  /// session-long subscription in ``observePhotoCaptures(_:announcingTo:)``, so the crossing is armed
  /// before the shutter fires.
  ///
  /// Two things can end the wait besides the photograph: the link going down under it, which
  /// ends it at once — see ``failPendingPhoto()`` — and ``photoTransferTimeout``, the backstop
  /// for a crossing that dies mid-air with the link still up.
  func captureThroughActiveCamera(
    format: PhotoFormat,
    resolution: CaptureResolution,
    quality: CaptureQuality
  ) async throws -> CapturedPhoto {
    guard let camera = lock.withLock({ activeCamera }) else {
      BirdLog.warning(.glasses, "capture — asked for, but no camera is attached")
      throw GlassesError.notConnected
    }
    // The shutter has a readiness of its own, and asking anyway is worse than not asking:
    // the capability refuses synchronously, which reads on the log as a photograph that
    // crossed in no time at all and arrived empty.
    guard lock.withLock({ isPhotoStarted }) else {
      BirdLog.warning(.glasses, "capture — asked for, but the shutter has not started")
      throw GlassesError.notConnected
    }
    // A stream that is carrying the microphone is holding the sensor too, and it is put down
    // for the length of this photograph and started again however the photograph ends.
    let streamSetAside = await setStreamAsideForPhoto(camera)
    // Stamped so the line below can say how long the crossing took. That number is the
    // single most useful thing in the file when a demo "felt slow": a photograph is
    // supposed to be about a second, and knowing it was nine is the whole diagnosis.
    let startedAt = ContinuousClock.now

    let photos = AsyncStream<Data> { continuation in
      // Registered rather than subscribed, because the arrival this waits on is
      // delivered by the session-long listener, and the ending it also has to survive
      // arrives from somewhere else entirely — see ``failPendingPhoto()``.
      lock.withLock { pendingPhoto = continuation }
    }
    defer { lock.withLock { pendingPhoto = nil } }

    // The capability encodes what it encodes and takes no format argument; the request
    // carries size and compression instead. Named here so the day a second format
    // appears, this is the one line that learns about it.
    switch format {
    case .jpeg: break
    }
    camera.photo.capturePhoto(resolution: resolution.datResolution, quality: quality.datQuality)
    BirdLog.debug(
      .glasses,
      "capture — fired at \(resolution.rawValue)/\(quality.rawValue), waiting on the crossing"
    )

    let imageData: Data? = await withTaskGroup(of: Data?.self) { group in
      group.addTask {
        for await data in photos { return data }
        return nil
      }
      group.addTask {
        try? await Task.sleep(for: photoTransferTimeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
    if streamSetAside { await bringStreamBack(camera) }

    let elapsed = ContinuousClock.now - startedAt
    guard let imageData else {
      // Both endings land here — the timeout, and the link going down under the
      // crossing — and the elapsed time is what tells them apart without a second line.
      BirdLog.error(.glasses, "capture — nothing arrived after \(elapsed.milliseconds) ms")
      throw GlassesError.transferFailed
    }
    BirdLog.info(
      .glasses,
      "capture — \(imageData.count) bytes crossed in \(elapsed.milliseconds) ms"
    )
    return CapturedPhoto(imageData: imageData)
  }

  /// Attaches the camera capability once per session — a pause and resume must not stack a
  /// second one on the first — and lets the shutter's own state announce when the glasses
  /// are usable.
  ///
  /// **The video stream is the ignition, and then it gets out of the way.** A `Camera` owns
  /// the hardware and hands out two children that compete for it — frames and stills cannot
  /// be captured at the same time, and stopping one before starting the other is the caller's
  /// job. But the parent does not power itself: nothing brings the sensor up except a child
  /// asking for it, and the shutter cannot do the asking. `Photo.start()` on a cold camera
  /// sits at `starting` forever.
  ///
  /// So the stream is started to wake the hardware, the shutter is started the moment the
  /// frames prove it is awake, and the stream is then put down — see ``releaseVideoStream()``.
  /// Nothing ever draws those frames; they exist for the two seconds it takes to prove the
  /// sensor is alive. What is left is a camera that is up, with the shutter alone on it.
  ///
  /// **Unless the stream is also the glasses' ears.** The microphone rides the stream as
  /// audio, and a stream put down is a microphone gone deaf — so when this session's stream
  /// carries audio, it stays up for the life of the session and is set aside only for the
  /// length of each photograph. See ``captureThroughActiveCamera(format:resolution:quality:)``.
  ///
  /// The stream is configured as small as the SDK sells, because every one of those frames is
  /// bandwidth spent on proving a point. The audio is asked for at 16 kHz mono, the narrowest
  /// the stream offers and exactly the one format the app records in.
  private func attachCameraIfNeeded(
    to session: DeviceSession,
    announcingTo continuation: AsyncThrowingStream<GlassesSessionState, Error>.Continuation
  ) {
    let alreadyAttached = lock.withLock { activeCamera != nil }
    guard !alreadyAttached else { return }

    let carriesAudio = lock.withLock { streamCarriesAudio }
    // **Compressed, not raw, and the reason is the pocket.** The SDK pauses a raw stream
    // the moment the app leaves the foreground and keeps an HEVC one flowing (its changelog
    // says so, at 0.5.0). This stream is the glasses' microphone, so a raw stream would be
    // a session that goes deaf when the phone is locked. Nothing here ever decodes a
    // frame, so the codec costs the app nothing either way.
    let config = StreamConfiguration(
      videoCodec: .hvc1,
      audioCodec: carriesAudio ? .pcm(sampleRate: .rate16000, numberOfChannels: 1) : nil,
      resolution: .low,
      frameRate: 7
    )
    guard let camera = try? session.addCamera(config: config) else {
      // No capability, no photographs — which is not a session worth claiming.
      BirdLog.error(.glasses, "glasses session — the camera capability would not attach")
      continuation.finish(throwing: GlassesError.notConnected)
      return
    }
    // Held before anything is subscribed or started, because both of those can answer
    // immediately: a state that arrives while the handle is still unwritten is a shutter
    // that reports no camera during the one beat the camera is coming up.
    lock.withLock { activeCamera = camera }
    // Read directly rather than waited for: `statePublisher` announces *changes*, so a
    // camera that is already where it is going to be says nothing at all, and "no camera
    // line on the log" is otherwise impossible to tell from "the camera never came up".
    BirdLog.debug(.glasses, "camera — attached at \(String(describing: camera.state))")
    observePhotoCaptures(camera, announcingTo: continuation)
    if carriesAudio { observeAudio(on: camera.stream) }

    let token = camera.statePublisher.listen { [weak self] state in
      // The hardware coming up, which is a different beat from the session's own and
      // arrives after it. A session that says started and then sits here is the classic
      // "it claims the glasses but the shutter does nothing" report.
      BirdLog.debug(.glasses, "camera — \(String(describing: state))")
      guard let self else { return }
      switch state {
      case .started:
        self.lock.withLock { self.cameraHasStarted = true }
      case .stopped, .stopping:
        // **Only a camera that was up and went down means the glasses are gone.** The
        // state a camera is born in is `stopped` too, and reading that as a session
        // ending would end every session at the moment it attached.
        guard self.lock.withLock({ self.cameraHasStarted }) else { break }
        // The session may well still be up; the *camera* is not, and this app has
        // nothing to do with a pair of glasses it cannot photograph through — including
        // a photograph it was in the middle of taking.
        self.failPendingPhoto()
        continuation.yield(.stopped)
        // A stream that has gone down is a microphone gone deaf, and the failover
        // only moves on a failure — so the ears are handed to the phone now rather
        // than after a silence long enough to notice. They come back with the camera.
        self.finishAudioListeners(throwing: AudioCaptureError.interrupted)
        // And the camera is asked back, the way the sensors are — see ``reviveCamera()``.
        self.reviveCamera()
      default:
        break // starting — still the linking beat
      }
    }

    let streamToken = camera.stream.statePublisher.listen { [weak self] state in
      BirdLog.debug(.glasses, "camera stream — \(String(describing: state))")
      guard let self else { return }
      switch state {
      case .streaming:
        // The sensor is provably awake. That is the entire job of these frames, and the
        // shutter can now be started on a camera that is up.
        self.startPhotoIfNeeded()
        // And the device is provably *there*, which is the thing the other capabilities
        // needed somebody to establish for them.
        self.attachSensorsIfNeeded()
      case .stopped, .stopping:
        // Ours, almost always — see ``releaseVideoStream()`` and
        // ``setStreamAsideForPhoto(_:)``. A stream this app did not stop is the glasses
        // going away, and the camera's own state says so too, so it is left to say it.
        break
      default:
        break // waitingForDevice, starting — still the linking beat
      }
    }

    lock.withLock {
      cameraStateToken = token
      streamStateToken = streamToken
    }

    camera.stream.start()
  }

  /// Attaches the capabilities that will not wait for the glasses to arrive.
  ///
  /// **The camera is the only one with patience.** Its stream has a `waitingForDevice` state
  /// and sits in it until the device answers; `Motion` and `Inputs` have no equivalent, so
  /// asked for in that same window they fail with `deviceDisconnected` — once, quietly, with
  /// no retry of their own. That is a sensor that goes `starting → stopping → stopped` in the
  /// space of three log lines and never speaks again, taking the wearer's own bearing with it.
  ///
  /// So they are attached off the back of the frames instead: by the time a frame arrives,
  /// the device is not merely sessioned but *there*. The display rides the same beat for the
  /// same reason. All of them are idempotent, so the repeated `streaming` of a pause and
  /// resume costs nothing.
  private func attachSensorsIfNeeded() {
    guard let session = lock.withLock({ activeSession }) else { return }
    attachInputsIfNeeded(to: session)
    attachMotionIfNeeded(to: session)
    attachSpeechIfNeeded(to: session)
    attachDisplayIfNeeded(to: session)
  }

  /// Puts the video stream down, once the shutter is up and holding the camera open.
  ///
  /// **Nothing on either device draws these frames.** They exist only to wake the sensor, and
  /// a stream still running past that point is the one thing that stops a still from being
  /// taken: the two children compete, and the frames win by being already in progress. This
  /// is the "stop one before starting the other" the reference asks for, done the moment the
  /// other one is confirmed started.
  private func releaseVideoStream() {
    let stream: MWDATCamera.Stream? = lock.withLock {
      guard !streamStopIntended, let camera = activeCamera else { return nil }
      streamStopIntended = true
      return camera.stream
    }
    guard let stream else { return }
    BirdLog.info(.glasses, "camera stream — put down; the shutter has the sensor to itself")
    stream.stop()
  }

  /// Stops a stream that is carrying the microphone, for the length of one photograph, and waits
  /// for it to be down. Answers whether it did, which is whether ``bringStreamBack(_:)`` owes it
  /// a start afterwards.
  ///
  /// **The still would be refused otherwise.** Frames and stills compete for the sensor, and a
  /// running stream wins by being already in progress — the capture fails in about 100 ms with
  /// not one byte crossed. The wait matters as much as the stop: `stop()` returns at once and the
  /// stream is still holding the sensor for a beat after it.
  ///
  /// **The microphone goes quiet with it, and that is a gap rather than a loss.** The listeners
  /// are held across it, the way the sensors are held across a crossing: a session that handed
  /// its ears to the phone and back for every photograph would be worse than one that misses a
  /// second of birdsong.
  private func setStreamAsideForPhoto(_ camera: Camera) async -> Bool {
    guard lock.withLock({ streamCarriesAudio }), camera.stream.state != .stopped else {
      return false
    }
    BirdLog.info(.glasses, "camera stream — set aside for a photograph; the microphone pauses")
    camera.stream.stop()
    let deadline = ContinuousClock.now + streamSetAsideTimeout
    while camera.stream.state != .stopped, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    return true
  }

  /// Starts the stream again once a photograph has finished crossing, however it ended — see
  /// ``setStreamAsideForPhoto(_:)``. A session that ended in the meantime has no stream to bring
  /// back.
  ///
  /// **The audio is subscribed afresh, before the start.** Whether a listener taken out on the
  /// stream survives a stop and a start is the stream's business, not documented, and the cost
  /// of guessing wrong is a microphone that never speaks again after the first photograph — so
  /// the old subscription is dropped and a new one taken before the frames can flow.
  private func bringStreamBack(_ camera: Camera) async {
    guard lock.withLock({ activeCamera != nil }) else { return }
    await audioTokens.cancelAll()
    // Emptied as well as cancelled: whether `cancelAll` also lets go of the tokens is the
    // bag's business, and a bag that keeps them grows by two dead tokens per photograph.
    audioTokens.clear()
    lock.withLock { audioHeardSinceStart = false }
    observeAudio(on: camera.stream)
    BirdLog.info(.glasses, "camera stream — back up after the photograph")
    camera.stream.start()
    // **A restart that never speaks again must not leave the session deaf.** Whether the
    // stream comes back with its audio is the one thing about this path nobody has watched
    // on hardware, and a stream that returns frames but no buffers looks exactly like a
    // quiet field. So the microphone is given a beat to be heard from, and if it is not, its
    // listeners are failed — which is what hands the session's ears back to the phone.
    lock.withLock {
      audioRevival?.cancel()
      audioRevival = Task { [weak self] in
        try? await Task.sleep(for: audioRevivalPatience)
        guard let self, !Task.isCancelled else { return }
        let heard = self.lock.withLock { self.audioHeardSinceStart }
        guard !heard else { return }
        BirdLog.error(.glasses, "camera stream — no audio since the photograph; the ears go back to the phone")
        self.finishAudioListeners(throwing: AudioCaptureError.interrupted)
      }
    }
  }

  /// The glasses' microphone, for ``GlassesMicrophoneSource`` — one subscription per caller,
  /// fed by the single listener in ``observeAudio(on:)``.
  ///
  /// **Fails at once when there is nothing to hear.** No session, or a session whose stream was
  /// opened without audio, is ``AudioCaptureError/unavailable`` straight away, which is the
  /// answer the failover needs to keep the phone. Unlike the readings, a subscription here is
  /// only meaningful against a session that is already up — the failover asks for the glasses
  /// only once one is.
  ///
  /// A session that ends under a listener finishes it with ``AudioCaptureError/interrupted``, so
  /// the failover hears a lost microphone rather than watching a silent one.
  func audioChunksFromActiveSession() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      let id = UUID()
      let listening: Bool = lock.withLock {
        guard activeCamera != nil, streamCarriesAudio else { return false }
        audioListeners[id] = continuation
        return true
      }
      guard listening else {
        continuation.finish(throwing: AudioCaptureError.unavailable)
        return
      }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { _ = self.audioListeners.removeValue(forKey: id) }
      }
    }
  }

  /// Subscribes to the stream's audio once per camera.
  ///
  /// Only an audio failure ends the listeners. The stream's other errors are about the frames or
  /// the link, and the link going away is heard through the camera's own state, which ends the
  /// session and every listener with it.
  private func observeAudio(on stream: MWDATCamera.Stream) {
    stream.audioFramePublisher.listen { [weak self] frame in
      self?.receive(audio: frame)
    }.store(in: audioTokens)
    stream.errorPublisher.listen { [weak self] error in
      guard error == .audioStreamingError else { return }
      BirdLog.error(.glasses, "camera stream — \(error.description)")
      self?.finishAudioListeners(throwing: AudioCaptureError.interrupted)
    }.store(in: audioTokens)
  }

  /// One buffer off the stream, as the app's one format, handed to every listener.
  ///
  /// **Converted rather than trusted.** The stream is asked for 16 kHz mono, but the buffer says
  /// what it actually is, and `AVAudioConverter` makes whatever arrives into ``captureSampleRate``
  /// floats — a no-op when the two agree, and the difference between a sonogram and a smear when
  /// they do not.
  private func receive(audio frame: AudioFrame) {
    let buffer = frame.pcmBuffer
    guard buffer.frameLength > 0, let targetFormat = glassesAudioFormat else { return }

    let converter: AVAudioConverter? = lock.withLock {
      if !audioHeardSinceStart {
        audioHeardSinceStart = true
        BirdLog.info(.glasses, "camera stream — audio flowing, \(buffer.frameLength) frames a buffer")
      }
      if let existing = audioConverter, existing.inputFormat == buffer.format { return existing }
      BirdLog.info(.glasses, "camera stream — audio arriving as \(buffer.format)")
      audioConverter = AVAudioConverter(from: buffer.format, to: targetFormat)
      return audioConverter
    }
    guard let converter else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
      return
    }
    // One buffer in, then `.noDataNow` — the converter pulls, because a rate change means the
    // input and output frame counts differ.
    var supplied = false
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return buffer
    }
    guard error == nil, let samples = converted.floatChannelData?[0], converted.frameLength > 0 else {
      return
    }

    let chunk = AudioChunk(
      samples: Array(UnsafeBufferPointer(start: samples, count: Int(converted.frameLength))),
      source: .glasses
    )
    let listeners = lock.withLock { Array(audioListeners.values) }
    for listener in listeners { listener.yield(chunk) }
  }

  /// Ends every microphone subscription — the session is gone, or its audio is.
  private func finishAudioListeners(throwing error: AudioCaptureError) {
    let listeners = lock.withLock {
      defer { audioListeners.removeAll() }
      return Array(audioListeners.values)
    }
    guard !listeners.isEmpty else { return }
    BirdLog.info(.glasses, "microphone — no audio to give; ending \(listeners.count) subscription(s)")
    for listener in listeners { listener.finish(throwing: error) }
  }

  /// Asks the shutter to start, once per session.
  ///
  /// A capability told to start a second time is an answer nobody is waiting on, so the ask is
  /// remembered rather than repeated. ``releaseLink()`` forgets it with the rest of the
  /// session.
  private func startPhotoIfNeeded() {
    let photo: Photo? = lock.withLock {
      guard !photoStartRequested, let camera = activeCamera else { return nil }
      photoStartRequested = true
      return camera.photo
    }
    photo?.start()
  }

  /// The presses, for ``DatGlassesInputRepository`` — one subscription per caller, fed by
  /// the single drain in ``attachInputsIfNeeded(to:)``.
  ///
  /// Subscribing before a session exists is deliberately allowed: the registry outlives any
  /// one session, so a listener that registers while the glasses are still linking is the
  /// same listener that hears the first press once they are up. Nothing here starts the
  /// capability — the session does that when it reaches started.
  func inputEventsFromActiveSession() -> AsyncStream<GlassesInputEvent> {
    AsyncStream { continuation in
      let id = UUID()
      lock.withLock { inputListeners[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { _ = self.inputListeners.removeValue(forKey: id) }
      }
    }
  }

  /// Attaches the inputs capability once per session, and listens to everything it will send.
  ///
  /// **Subscribing *is* consuming, and the band is left out for that reason.** `sources` is not
  /// a filter this app applies to a stream it would have received anyway — it is a request sent
  /// to the glasses, which then route those surfaces here instead of to whatever was handling
  /// them. Asked for all five, this took the Neural Band's swipes, and the swipe the wearer
  /// makes on the band is how the card on the display is scrolled. A card that draws three
  /// photographs and a description below the fold, on a surface whose renderer scrolls it
  /// natively, cannot also be a card whose scroll gesture this app is quietly eating.
  ///
  /// So the band is not asked for, and neither is its drag. What is left is the temple and the
  /// buttons: the surfaces this app has something to *do* with, and none of which scroll
  /// anything.
  ///
  /// **`consumeBack` is unaffected by that narrowing** — it rides the attach request as its own
  /// field rather than being implied by a source, so back stays this app's while the band stays
  /// the wearer's.
  ///
  /// **A narrow subscription hides one failure, and it has bitten here before.** Asked for
  /// `captureButton` alone, the capability once reported `active` and then delivered nothing at
  /// all through a whole session of pressing the temple — and a subscription that narrow cannot
  /// tell *the button sends nothing* apart from *the button sends something this app did not ask
  /// for*, which want opposite fixes. Keeping the temple and both buttons is what keeps that
  /// distinction visible; if the shutter ever goes quiet again, widening the set is the first
  /// thing to try.
  ///
  /// **`consumeBack` is on, and back belongs to this app.** Left off, back keeps its system
  /// meaning, and that meaning is *leave the running experience*: a wearer who swipes back
  /// mid-run takes the session down with them — camera, sensors, display and all — and the
  /// cause is invisible from the phone, which sees only a session that ended for no reason
  /// anyone can name. Consuming the gesture is the only way to stop that.
  ///
  /// **The cost of consuming it is that back now owes the wearer an answer,** and the reason
  /// that debt is payable is scope: this capability lives exactly as long as a glasses-backed
  /// run does, so the one screen that can be on the glasses is also the screen that answers
  /// back. There is no stretch of the app where the gesture is quietly dead. What it answers
  /// with is decided above the data layer — see ``receive(_:)``.
  ///
  /// A capability that will not attach is logged and lived with. The shutter on screen still
  /// works, and a session with no button is worth a great deal more than no session.
  private func attachInputsIfNeeded(to session: DeviceSession) {
    let alreadyAttached = lock.withLock { activeInputs != nil }
    guard !alreadyAttached else { return }

    let configuration = InputsConfiguration(
      sources: [.captouch, .captureButton, .actionButton],
      consumeBack: true
    )
    let attached: Inputs?
    do {
      attached = try session.addInputs(configuration: configuration)
    } catch {
      BirdLog.error(.glasses, "glasses session — inputs would not attach: \(error.description)")
      return
    }
    guard let inputs = attached else {
      // The capability answers `nil` rather than throwing when this pair has nothing to
      // offer, which is a fact about the hardware and not a fault.
      BirdLog.info(.glasses, "glasses session — this pair reports no inputs to listen to")
      return
    }

    // Drained exactly once: the capability hands over a stream with room for one reader,
    // and a second `for await` on it would simply take turns with the first.
    let drain = Task { [weak self] in
      for await event in inputs.events {
        self?.receive(event)
      }
      // **A stream that ends is not a button nobody pressed.** Both look like silence from
      // here, and only one of them is worth chasing.
      BirdLog.info(.glasses, "inputs — the event stream ended")
    }
    // Held before anything is subscribed, because a subscription can answer immediately: an
    // `active` that lands while the flag is still unwritten is a button whose next silence
    // reads as the state it was born in, and nothing goes to fetch it back.
    lock.withLock {
      activeInputs = inputs
      inputsDrain = drain
      inputsHasActivated = false
    }

    // **The only two things that say whether the button is listening.** The capability
    // activates itself on attach and reports nothing back through this call, so a pair whose
    // presses never arrive is otherwise indistinguishable from a wearer who never pressed —
    // which is exactly the silence that hid the sensor coming up dead for three runs.
    inputs.statePublisher.listen { [weak self] state in
      BirdLog.debug(.glasses, "inputs — \(String(describing: state))")
      guard let self else { return }
      switch state {
      case .active:
        self.lock.withLock { self.inputsHasActivated = true }
      case .inactive:
        // **Only a button that was listening and then went quiet is one to attach
        // again.** `inactive` is also the state the capability is born in, and acting on
        // that one would tear down a capability that is still on its way up.
        guard self.lock.withLock({ self.inputsHasActivated }) else { break }
        self.reviveInputs()
      default:
        break // activating, deactivating — the linking beats
      }
    }.store(in: inputsTokens)
    inputs.errorPublisher.listen { error in
      BirdLog.error(.glasses, "inputs — \(error.description)")
    }.store(in: inputsTokens)
  }

  /// Attaches the button again after it has gone quiet under a running session.
  ///
  /// **A photograph is what takes it away.** A still crosses on the file-transfer channel rather
  /// than the video stream, and taking that channel puts down the other capabilities the session
  /// is holding. The button comes back from that the way it goes down: it does not. Left alone,
  /// the first photograph of a run is the last press of it — the temple stops answering and the
  /// only thing that still fires the shutter is the control on the phone, which is precisely the
  /// half of the demo the glasses are there for.
  ///
  /// **Unlike the sensor, this capability cannot simply be started again** — it has no start of
  /// its own, and one that has ended holds its place until it is removed, so the dead one goes
  /// before a live one can take the slot. That is destructive enough to be worth being sure
  /// about, which is what ``inputsHasActivated`` is for.
  private func reviveInputs() {
    lock.withLock {
      guard inputsRevival == nil, activeInputs != nil, activeSession != nil else { return }
      inputsRevival = Task { [weak self] in
        guard let self else { return }
        await self.bringInputsBack()
        self.lock.withLock { self.inputsRevival = nil }
      }
    }
  }

  private func bringInputsBack() async {
    await waitOutCrossing()
    if Task.isCancelled { return }
    guard let session = lock.withLock({ activeSession }) else { return }
    let (dead, drain) = lock.withLock {
      defer {
        activeInputs = nil
        inputsDrain = nil
        inputsHasActivated = false
      }
      return (activeInputs, inputsDrain)
    }
    guard dead != nil else { return }
    BirdLog.info(.glasses, "inputs — the button went quiet; attaching it again")
    drain?.cancel()
    // The old subscriptions go down with the capability they were watching. Left running,
    // the dead one's own `inactive` arrives against the live one and takes it down again.
    await inputsTokens.cancelAll()
    try? session.removeInputs()
    attachInputsIfNeeded(to: session)
  }

  /// The readings, for ``DatGlassesMotionRepository`` — one subscription per caller, fed by
  /// the single drain in ``attachMotionIfNeeded(to:)``.
  ///
  /// Subscribing before a session exists is allowed for the same reason a press listener may:
  /// the registry outlives any one session, so a compass that subscribes while the glasses are
  /// still linking is the one that reads the first sample once they are up.
  func motionSamplesFromActiveSession() -> AsyncStream<GlassesMotionSample> {
    AsyncStream { continuation in
      let id = UUID()
      lock.withLock { motionListeners[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { _ = self.motionListeners.removeValue(forKey: id) }
      }
    }
  }

  /// Attaches the motion capability once per session and starts it.
  ///
  /// **The slowest rate the SDK offers, and it is still faster than the screen.** Both readings
  /// this feeds are words — one of eight compass points, one of five strata — and neither turns
  /// over for a degree of wobble. 5 Hz is a reading every 200 ms on a link that is also carrying
  /// a video stream and owes it the bandwidth; the rates above it would buy a smoother number
  /// that nothing on screen is drawing.
  ///
  /// **The capability must be started, unlike inputs.** `addMotion` attaches the sensor and
  /// leaves it stopped; without the `start()` the samples stream stays silent forever, which
  /// looks exactly like a pair with no IMU.
  ///
  /// A capability that will not attach is logged and lived with. The phone's own compass and
  /// attitude are still there behind the failover, and a session with a bearing from the wrong
  /// device is worth more than a session with no bearing.
  private func attachMotionIfNeeded(to session: DeviceSession) {
    let alreadyAttached = lock.withLock { activeMotion != nil }
    guard !alreadyAttached else { return }

    let attached: Motion?
    do {
      attached = try session.addMotion(
        configuration: MotionConfiguration(samplingRate: .hz5)
      )
    } catch {
      BirdLog.error(.glasses, "glasses session — motion would not attach: \(error.description)")
      // Nothing is coming, so nobody should be left waiting for it.
      finishMotionListeners()
      return
    }
    guard let motion = attached else {
      // The capability answers `nil` rather than throwing when this pair has no IMU to
      // offer, which is a fact about the hardware and not a fault.
      BirdLog.info(.glasses, "glasses session — this pair reports no motion sensors")
      finishMotionListeners()
      return
    }

    // Drained exactly once: the capability hands over a stream with room for one reader,
    // and a second `for await` on it would simply take turns with the first.
    let drain = Task { [weak self] in
      for await sample in motion.samples {
        self?.receive(sample)
      }
    }

    // Held before anything is subscribed or started, because both of those can answer
    // immediately: a stop that arrives while the handle is still unwritten is a sensor
    // ``reviveMotion()`` cannot see, and so a sensor nothing goes back for.
    lock.withLock {
      activeMotion = motion
      motionDrain = drain
      motionSourcesHeard.removeAll()
      lastMotionLogMillis = 0
    }

    // **The only two things that say whether the sensor came up.** `start()` returns nothing
    // and is silently ignored unless the capability is stopped, so a run where the chips never
    // move is otherwise indistinguishable from a run where they were never asked to. Started
    // here and no sample below is a different bug from neither.
    motion.statePublisher.listen { [weak self] state in
      BirdLog.debug(.glasses, "motion — \(String(describing: state))")
      // A sensor that stops without being asked to is one something else on the link took
      // away, and it is brought back rather than mourned — see ``reviveMotion()``.
      if case .stopped = state { self?.reviveMotion() }
    }.store(in: motionTokens)
    motion.errorPublisher.listen { error in
      BirdLog.error(.glasses, "motion — \(error.description)")
    }.store(in: motionTokens)

    motion.start()
  }

  /// Starts the sensor again after something else on the link has put it down.
  ///
  /// **A photograph is what puts it down.** A still crosses on the file-transfer channel rather
  /// than the video stream, and taking that channel stops the capabilities the session is
  /// holding alongside it: the sensor goes `stopping → stopped` in the middle of a capture and
  /// stays there, because nothing in the SDK brings it back. Left alone, the first photograph of
  /// a run is the last reading of it — the compass and the stratum freeze on whatever the wearer
  /// happened to be looking at while every log line still says the glasses have the aim.
  ///
  /// So a stop this app did not ask for is read as an interruption rather than an ending.
  /// `start()` is only honoured on a capability that is already `stopped`, which is what makes
  /// this safe to attempt more than once: a sensor that came back on its own ignores it.
  ///
  /// **The listeners are held across the gap on purpose.** Ending them hands the aim to the
  /// phone (see ``finishMotionListeners()``), and a reading that crosses to the phone and back
  /// for every photograph is worse than one that holds still for a second — the failover exists
  /// for an instrument that is gone, not for one that is busy. They are only ended once the
  /// sensor has refused to come back at all, which is the point at which the glasses really do
  /// have nothing to give.
  /// Starts the camera again after something else on the link has put it down — the sensors'
  /// revival, for the one capability whose stop the app used to read as the glasses leaving.
  ///
  /// **A photograph is what puts it down, on a stream that carries the microphone.** The
  /// still crosses on the file-transfer channel, and the first time that channel was watched
  /// on hardware the whole camera went `stopping → stopped` a few milliseconds after the
  /// stream was started again behind the crossing, taking the shutter and the ears with it —
  /// with the session itself still up, still transcribing, still delivering the button. Read
  /// as the glasses leaving, that made the first photograph of a run the last, and every
  /// press after it *the shutter has not started*.
  ///
  /// So a stop this app did not ask for is read as an interruption, the way it is for the
  /// sensors: the camera has no `start()` of its own, but its stream does, and the stream
  /// coming up is what starts the shutter again and announces `started` to the session. The
  /// ears were handed to the phone when the camera went down (see the camera's state
  /// listener), and the session asks for them back the moment `started` lands. The stream is
  /// subscribed afresh first, for the reason ``bringStreamBack(_:)`` gives.
  private func reviveCamera() {
    lock.withLock {
      guard cameraRevival == nil, activeCamera != nil else { return }
      cameraRevival = Task { [weak self] in
        guard let self else { return }
        await self.bringCameraBack()
        self.lock.withLock { self.cameraRevival = nil }
      }
    }
  }

  private func bringCameraBack() async {
    for attempt in 1...sensorRevivalAttempts {
      await waitOutCrossing()
      if Task.isCancelled { return }
      // No session left to have a camera on.
      guard let camera = lock.withLock({ activeCamera }) else { return }
      // Up again already — a stop that arrived late about a camera that has since come back.
      guard camera.state == .stopped else { return }
      BirdLog.info(
        .glasses,
        "camera — stopped without being asked to; starting it again "
          + "(\(attempt) of \(sensorRevivalAttempts))"
      )
      let carriesAudio = lock.withLock {
        // A stream put down deliberately on a stream without audio is put down again
        // once the shutter is back — see ``releaseVideoStream()``.
        streamStopIntended = false
        audioHeardSinceStart = false
        return streamCarriesAudio
      }
      if carriesAudio {
        await audioTokens.cancelAll()
        audioTokens.clear()
        observeAudio(on: camera.stream)
      }
      camera.stream.start()
      // `start()` answers on the state publishers and nowhere else, so the only way to know
      // whether it took is to look again a beat later.
      try? await Task.sleep(for: sensorRevivalDelay)
      if Task.isCancelled { return }
      guard camera.state == .stopped else {
        BirdLog.info(.glasses, "camera — back up")
        return
      }
    }
    BirdLog.error(.glasses, "camera — would not start again; the glasses are done for this run")
  }

  private func reviveMotion() {
    lock.withLock {
      guard motionRevival == nil, activeMotion != nil else { return }
      motionRevival = Task { [weak self] in
        guard let self else { return }
        await self.bringMotionBack()
        self.lock.withLock { self.motionRevival = nil }
      }
    }
  }

  private func bringMotionBack() async {
    for attempt in 1...sensorRevivalAttempts {
      await waitOutCrossing()
      if Task.isCancelled { return }
      // No session left to have a sensor on.
      guard let motion = lock.withLock({ activeMotion }) else { return }
      // Up again already: either it never really went down, or a stop arrived late about a
      // capability that has since been started.
      guard motion.state == .stopped else { return }
      BirdLog.info(
        .glasses,
        "motion — stopped without being asked to; starting it again "
          + "(\(attempt) of \(sensorRevivalAttempts))"
      )
      motion.start()
      // `start()` answers on the state publisher and nowhere else, so the only way to know
      // whether it took is to look again a beat later.
      try? await Task.sleep(for: sensorRevivalDelay)
      if Task.isCancelled { return }
      guard motion.state == .stopped else {
        BirdLog.info(.glasses, "motion — back up")
        return
      }
    }
    BirdLog.error(.glasses, "motion — would not start again; the aim goes back to the phone")
    finishMotionListeners()
  }

  /// What the wearer said, for ``DatGlassesSpeechRepository`` — one subscription per caller, fed
  /// by the single listener in ``attachSpeechIfNeeded(to:)``.
  ///
  /// Subscribing before a session exists is allowed for the same reason a press listener may:
  /// the registry outlives any one session, so a screen that subscribes while the glasses are
  /// still linking is the one that hears the first thing said once they are up.
  func transcriptionsFromActiveSession() -> AsyncStream<Transcription> {
    AsyncStream { continuation in
      let id = UUID()
      lock.withLock { transcriptionListeners[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { _ = self.transcriptionListeners.removeValue(forKey: id) }
      }
    }
  }

  /// Where the recogniser is, for ``DatGlassesSpeechRepository``. The current reading is handed
  /// over the moment a subscription opens — see ``speechState``.
  func speechStateFromActiveSession() -> AsyncStream<GlassesSpeechState> {
    AsyncStream { continuation in
      let id = UUID()
      let current = lock.withLock {
        speechStateListeners[id] = continuation
        return speechState
      }
      continuation.yield(current)
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { _ = self.speechStateListeners.removeValue(forKey: id) }
      }
    }
  }

  /// Attaches the speech capability once per session and starts it listening.
  ///
  /// **Nothing but text crosses the link.** The recognition runs on the glasses' own engine,
  /// so this costs the session no audio bandwidth — the words arrive already written, where
  /// the microphone's audio has to cross the camera stream as samples. That is the reason the
  /// app transcribes here rather than on the phone.
  ///
  /// **The capability must be started, like the sensor and unlike the button.** `addSpeech`
  /// attaches a recogniser and leaves it stopped; without the `start()` the transcript stream
  /// stays silent forever, which looks exactly like a wearer who never said anything.
  ///
  /// **A pair that cannot do this says so once, and the reading is terminal.** `unavailable` is
  /// hardware, not a link that will come back, and a screen told it can stop offering something
  /// these glasses will never do. Every other failure is logged and lived with: a session that
  /// cannot hear the wearer is still a session that photographs and identifies.
  private func attachSpeechIfNeeded(to session: DeviceSession) {
    let alreadyAttached = lock.withLock { activeSpeech != nil }
    guard !alreadyAttached else { return }

    publish(speechState: .starting)
    let attached: Speech?
    do {
      attached = try session.addSpeech()
    } catch {
      BirdLog.error(.glasses, "glasses session — speech would not attach: \(error.description)")
      publish(speechState: .unavailable)
      return
    }
    guard let speech = attached else {
      // The capability answers `nil` rather than throwing when this pair has nothing to
      // offer, which is a fact about the hardware and not a fault.
      BirdLog.info(.glasses, "glasses session — this pair reports no on-device speech")
      publish(speechState: .unavailable)
      return
    }

    // Held before anything is subscribed or started, because both of those can answer
    // immediately: a stop that arrives while the handle is still unwritten is a recogniser
    // ``reviveSpeech()`` cannot see, and so a recogniser nothing goes back for.
    lock.withLock {
      activeSpeech = speech
      speechHasStarted = false
    }

    speech.transcriptionPublisher.listen { [weak self] result in
      self?.receive(result)
    }.store(in: speechTokens)

    // **The only two things that say whether the recogniser came up.** `start()` returns
    // nothing, so a run where nobody is heard is otherwise indistinguishable from a run where
    // the glasses were never asked to listen.
    speech.statePublisher.listen { [weak self] state in
      BirdLog.debug(.glasses, "speech — \(String(describing: state))")
      guard let self else { return }
      switch state {
      case .started:
        self.lock.withLock { self.speechHasStarted = true }
        self.publish(speechState: .listening)
      case .stopped:
        // **Only a recogniser that was listening and then went quiet is one to start
        // again.** `stopped` is also the state the capability is born in, and acting on
        // that one would chase a recogniser still on its way up.
        guard self.lock.withLock({ self.speechHasStarted }) else { break }
        self.publish(speechState: .stopped)
        self.reviveSpeech()
      default:
        break // starting, stopping — the linking beats
      }
    }.store(in: speechTokens)

    speech.errorPublisher.listen { [weak self] error in
      BirdLog.error(.glasses, "speech — \(error.description)")
      // The one error that is a fact about the glasses rather than about this moment.
      // Everything else is a link, a state, or a start that can be tried again, and none of
      // those is worth telling a screen to give up over.
      guard error == .unavailable else { return }
      self?.publish(speechState: .unavailable)
    }.store(in: speechTokens)

    speech.start()
  }

  /// Starts the recogniser again after something else on the link has put it down.
  ///
  /// **A photograph is what puts it down**, the same crossing that stops the sensor — see
  /// ``reviveMotion()``, which this mirrors beat for beat. Left alone, the first photograph of a
  /// run would be the last thing the wearer could say to the app.
  ///
  /// `start()` is only honoured on a capability that is already `stopped`, which is what makes
  /// this safe to attempt more than once.
  private func reviveSpeech() {
    lock.withLock {
      guard speechRevival == nil, activeSpeech != nil else { return }
      speechRevival = Task { [weak self] in
        guard let self else { return }
        await self.bringSpeechBack()
        self.lock.withLock { self.speechRevival = nil }
      }
    }
  }

  private func bringSpeechBack() async {
    for attempt in 1...sensorRevivalAttempts {
      await waitOutCrossing()
      if Task.isCancelled { return }
      // No session left to have a recogniser on.
      guard let speech = lock.withLock({ activeSpeech }) else { return }
      // Up again already: either it never really went down, or a stop arrived late about a
      // capability that has since been started.
      guard speech.state == .stopped else { return }
      BirdLog.info(
        .glasses,
        "speech — stopped without being asked to; starting it again "
          + "(\(attempt) of \(sensorRevivalAttempts))"
      )
      speech.start()
      // `start()` answers on the state publisher and nowhere else, so the only way to know
      // whether it took is to look again a beat later.
      try? await Task.sleep(for: sensorRevivalDelay)
      if Task.isCancelled { return }
      guard speech.state == .stopped else {
        BirdLog.info(.glasses, "speech — back up")
        return
      }
    }
    BirdLog.error(
      .glasses,
      "speech — would not start again; nothing more will be heard this session"
    )
    publish(speechState: .stopped)
  }

  /// One transcript off the capability, in the app's own terms, handed to everyone listening.
  ///
  /// **A confidence the recogniser will not give is `nil`, not a number.** The SDK spends `-1.0`
  /// on *no answer*, which is a value that survives every comparison a caller might make of it
  /// and reads as total disbelief in what was heard.
  private func receive(_ result: MWDATSpeech.TranscriptionResult) {
    let confidence = result.confidence >= 0 ? result.confidence : nil
    BirdLog.debug(
      .glasses,
      "speech — \"\(result.text)\" (\(result.isFinal ? "final" : "partial")"
        + (confidence.map { ", \($0.twoDecimals))" } ?? ")")
    )
    let heard = Transcription(
      text: result.text,
      isFinal: result.isFinal,
      confidence: confidence
    )
    let listeners = lock.withLock { Array(transcriptionListeners.values) }
    for listener in listeners { listener.yield(heard) }
  }

  /// Records where the recogniser is and tells everyone watching. Held as well as announced, so
  /// a subscription opened afterwards is answered rather than left waiting for the next change.
  private func publish(speechState state: GlassesSpeechState) {
    let listeners: [AsyncStream<GlassesSpeechState>.Continuation] = lock.withLock {
      guard speechState != state else { return [] }
      speechState = state
      return Array(speechStateListeners.values)
    }
    for listener in listeners { listener.yield(state) }
  }

  /// Attaches the display capability once per session — and only to a pair that has one.
  ///
  /// **Most pairs do not, and that is a fact about the hardware rather than a failure.** The
  /// gate is the device's own answer, read at attach time; a pair without a display simply
  /// never grows the capability, and every send through ``sendThroughActiveDisplay(_:)``
  /// answers `notConnected` — the same quiet a caller gets from a session that has ended.
  ///
  /// A capability that will not attach is logged and lived with, the sensors' bargain again:
  /// the identification still lands on the timeline, and a session that cannot decorate the
  /// wearer's view is worth a great deal more than no session.
  private func attachDisplayIfNeeded(to session: DeviceSession) {
    let alreadyAttached = lock.withLock { activeDisplay != nil }
    guard !alreadyAttached else { return }

    guard let identifier = lock.withLock({ activeDeviceIdentifier }),
      let device = Wearables.shared.deviceForIdentifier(identifier),
      device.supportsDisplay()
    else {
      BirdLog.info(.glasses, "glasses session — this pair has no display")
      return
    }

    let display: Display
    do {
      display = try session.addDisplay()
    } catch {
      BirdLog.error(.glasses, "glasses session — display would not attach: \(error.description)")
      return
    }
    // Held before anything is subscribed or started, because both of those can answer
    // immediately — the same beat every other capability here guards.
    lock.withLock { activeDisplay = display }

    // **The only thing that says whether the panel came up.** `start()` returns nothing,
    // so a display that never draws is otherwise indistinguishable from one never asked to.
    display.statePublisher.listen { state in
      BirdLog.debug(.glasses, "display — \(String(describing: state))")
    }.store(in: displayTokens)

    display.start()
  }

  /// Attaches the display capability with retries, and announces `started` when it lands —
  /// for the lease with no camera frames to wait behind.
  ///
  /// ``attachDisplayIfNeeded(to:)`` gets to ask exactly once because the frames have
  /// already proved the device is there. On the display-only lease nothing has, and a
  /// capability asked for while the device is still arriving fails once and quietly — so
  /// this one asks again on the sensors' own revival beat, until the capability answers or
  /// the run ends and takes the job with it.
  ///
  /// A pair with no display announces `started` on the spot: there is nothing to wait for,
  /// the settings screen's own reading says why a send will land nowhere, and holding the
  /// announcement would dress a hardware fact up as a connection problem.
  private func attachDisplayWithPatience(
    to session: DeviceSession,
    announcingTo continuation: AsyncThrowingStream<GlassesSessionState, Error>.Continuation
  ) {
    // A pause and resume lands here again with the capability already up — only the
    // announcement is owed.
    if lock.withLock({ activeDisplay != nil }) {
      continuation.yield(.started)
      return
    }
    guard lock.withLock({ displayPatience == nil }) else { return }

    let patience = Task { [self] in
      guard let identifier = lock.withLock({ activeDeviceIdentifier }),
        let device = Wearables.shared.deviceForIdentifier(identifier),
        device.supportsDisplay()
      else {
        BirdLog.info(.glasses, "display session — this pair has no display")
        continuation.yield(.started)
        return
      }
      while !Task.isCancelled {
        let display: Display
        do {
          display = try session.addDisplay()
        } catch {
          BirdLog.debug(
            .glasses,
            "display session — the display would not attach, asking again: "
              + String(describing: error)
          )
          try? await Task.sleep(for: sensorRevivalDelay)
          continue
        }
        lock.withLock { activeDisplay = display }
        // **The only thing that says whether the panel came up.** `start()` returns
        // nothing, so a display that never draws is otherwise indistinguishable from
        // one never asked to.
        display.statePublisher.listen { state in
          BirdLog.debug(.glasses, "display — \(String(describing: state))")
        }.store(in: displayTokens)
        display.start()
        continuation.yield(.started)
        return
      }
    }
    lock.withLock { displayPatience = patience }
  }

  /// The display-only lease's way down: the patience cancelled, the capability stopped,
  /// the session let go — and nothing else touched, because nothing else was grown.
  private func releaseDisplayLease() {
    let (patience, display, session) = lock.withLock {
      defer {
        displayPatience = nil
        activeDisplay = nil
        activeDeviceIdentifier = nil
        activeSession = nil
      }
      return (displayPatience, activeDisplay, activeSession)
    }
    patience?.cancel()
    Task { [displayTokens] in
      await displayTokens.cancelAll()
    }
    display?.stop()
    session?.stop()
  }

  /// One view onto the running display, for ``DatGlassesDisplayRepository`` — the whole
  /// screen at once, because that is the only unit the display takes.
  ///
  /// **A stopped display is started again on the way through rather than mourned.** A
  /// photograph's crossing takes the session's other capabilities down with it (see
  /// ``reviveMotion()``), and the display goes the same way — which is precisely the moment
  /// a gallery is about to be sent, since the identification the gallery answers rode that
  /// photograph. `start()` is only honoured on a capability that is `stopped`, so asking on
  /// a display that never went down costs nothing.
  func sendThroughActiveDisplay(_ view: some DisplayableView) async throws {
    guard let display = lock.withLock({ activeDisplay }) else {
      // Which leg failed matters here: no capability on the session means the attach
      // never happened — the answer is further up the log, at session start.
      BirdLog.debug(
        .glasses,
        "display — asked to draw, but no display capability is attached to this session"
      )
      throw GlassesError.notConnected
    }
    if display.state != .started {
      display.start()
      for _ in 1...sensorRevivalAttempts where display.state != .started {
        try? await Task.sleep(for: sensorRevivalDelay)
      }
    }
    guard display.state == .started else {
      BirdLog.warning(.glasses, "display — asked to draw, but the panel would not start")
      throw GlassesError.notConnected
    }
    try await display.send(view)
  }

  /// Blanks the running display, if there is one. Quiet on purpose: the callers are
  /// teardowns, and a display that is already gone is a display that is already blank.
  func clearActiveDisplay() async {
    guard let display = lock.withLock({ activeDisplay }) else { return }
    try? await display.clearDisplay()
  }

  /// Waits until no photograph is crossing, and at least one beat besides.
  ///
  /// **A capability asked for anything mid-transfer is asked in the one window it cannot
  /// answer** — the channel that would carry the request is the channel carrying the picture.
  /// The beat on the end is for the crossing's own teardown, which lands a moment after the
  /// image does and would otherwise put back down whatever this had just brought up.
  private func waitOutCrossing() async {
    repeat {
      try? await Task.sleep(for: sensorRevivalDelay)
      if Task.isCancelled { return }
    } while lock.withLock({ pendingPhoto != nil })
  }

  /// One sample off the capability, in the app's own terms — or dropped, when it is not the
  /// glasses talking.
  ///
  /// **The source filter is the whole reason this is not a `map`.** One motion feed can carry
  /// the glasses *and* a Neural Band, which are two rigid bodies moving independently; a
  /// consumer that averaged them would produce a bearing describing neither, and it would do it
  /// silently. `unknown` is dropped with them: a sample that will not say what it is attached to
  /// cannot be trusted to be attached to a head.
  ///
  /// A sample with no accelerometer is dropped too. Both readings this app takes — elevation
  /// and a tilt-compensated bearing — start from where down is, so a sample that cannot say has
  /// nothing to give either of them.
  private func receive(_ sample: MWDATMotion.MotionSample) {
    describeOnce(sample)
    describeEvery(sample)
    guard sample.source == .glasses, let acceleration = sample.accelerometer else { return }
    let reading = GlassesMotionSample(
      acceleration: Vector3(
        x: Double(acceleration.x),
        y: Double(acceleration.y),
        z: Double(acceleration.z)
      ),
      magneticField: sample.magnetometer.map {
        Vector3(x: Double($0.x), y: Double($0.y), z: Double($0.z))
      }
    )
    let listeners = lock.withLock { Array(motionListeners.values) }
    for listener in listeners { listener.yield(reading) }
  }

  /// Ends every motion subscription, because the glasses have no readings to give.
  ///
  /// **Silence and *there is nothing here* are the same thing to a listener, and they must not
  /// be.** Whoever is waiting on these samples treats the stream ending as *the glasses cannot
  /// answer this, ask the phone* — that is the whole of how the aim falls back (see
  /// `FailoverReadings`). A capability that never attached, or that went down under a running
  /// session, would otherwise leave the stream open and mute: the failover keeps waiting on a
  /// pair that is never going to speak, the phone's own sensors are never asked again, and the
  /// reading on screen freezes on whatever it last had while every log line says the glasses
  /// have it.
  ///
  /// **This is for a sensor that is gone, not one that is busy.** A stop that came from
  /// something else on the link is answered by ``reviveMotion()`` instead, and only reaches here
  /// once the sensor has refused to come back — the failover is a change of instrument, and
  /// making one for every photograph would be worse than the freeze it avoids.
  ///
  /// Unlike the presses, these subscriptions are not a lease worth keeping — a listener whose
  /// stream ends can open another one the moment there is a session to open it against, and the
  /// aim does exactly that.
  private func finishMotionListeners() {
    let listeners = lock.withLock {
      defer { motionListeners.removeAll() }
      return Array(motionListeners.values)
    }
    guard !listeners.isEmpty else { return }
    BirdLog.info(.glasses, "motion — no readings to give; ending \(listeners.count) subscription(s)")
    for listener in listeners { listener.finish() }
  }

  /// Says out loud, once per source per run, what the motion feed is actually delivering.
  ///
  /// **Three of this path's ways of failing are silent by construction, and all three look
  /// identical on screen.** A sample from anything but the glasses is dropped above; an
  /// accelerometer the device omits arrives as nothing, and a sample with no down is dropped
  /// above too; a pair with no magnetometer ends the bearing and hands the compass back
  /// to the phone. In every one of them the chips simply keep the last reading they had — which
  /// is also exactly what a wearer sees when the sensor never started in the first place. One
  /// line per source is what tells them apart.
  ///
  /// **`unknown` is the one to watch for**, because it is the SDK's *default* when a device omits
  /// the field rather than a claim that something unidentified is moving. A pair whose firmware
  /// leaves it unset has every sample dropped by a filter written to keep a wrist out of a
  /// bearing about a head.
  ///
  /// The vector is logged rather than its length, because the axis convention in `GlassesAim` is
  /// still a guess and a still head reading roughly `9.8` on one component is the measurement
  /// that settles it.
  private func describeOnce(_ sample: MWDATMotion.MotionSample) {
    let firstOfItsKind = lock.withLock { motionSourcesHeard.insert(sample.source).inserted }
    guard firstOfItsKind else { return }

    let accel =
      sample.accelerometer.map {
        "(\($0.x.oneDecimal), \($0.y.oneDecimal), \($0.z.oneDecimal)) m/s²"
      } ?? "none — no elevation or bearing from this pair"
    let field = sample.magnetometer == nil ? "none — no bearing from this pair" : "present"
    // The fused attitude, which would make both derivations arithmetic instead of a guess
    // about which way the axes point. Reported because nothing else says whether this pair
    // sends one.
    let attitude = sample.orientation == nil ? "none" : "present"
    let dropped = sample.source == .glasses ? "" : " · dropped, not the glasses"
    BirdLog.info(
      .glasses,
      "motion — first sample from \(String(describing: sample.source)): accel \(accel), "
        + "magnetometer \(field), orientation \(attitude)\(dropped)"
    )
  }

  /// Every sample, every field, for as long as the sensor runs.
  ///
  /// **The whole reading, not the part a derivation happens to use.** `receive(_:)` keeps two
  /// vectors out of six fields and throws the rest away before anything can see it, which
  /// makes every question about the sensor unanswerable without a rebuild — and the questions
  /// keep coming, because the frame these readings are in was never documented. The gyroscope
  /// in particular has never once been logged, and it is the field that says whether a
  /// wandering elevation is the wearer's head moving or the sensor lying about it.
  ///
  /// **One line every three seconds, timed off the sensor's own clock.** Every sample was five
  /// lines a second, which buried every other glasses line in the file and made the log worth
  /// less than the thing it was recording. Three seconds is the cadence of a wearer moving
  /// their head, not of an IMU, and it is what these readings are actually read at.
  ///
  /// The interval is measured on `timestampNs` rather than a count, so it stays three seconds
  /// if the sampling rate changes, and rather than the wall clock, because that is the clock
  /// the samples are stamped on and a correction mid-session must not open a gap in the log.
  private func describeEvery(_ sample: MWDATMotion.MotionSample) {
    let millis = sample.timestampNs / 1_000_000
    let due = lock.withLock {
      guard millis - lastMotionLogMillis >= motionLogIntervalMillis else { return false }
      lastMotionLogMillis = millis
      return true
    }
    guard due else { return }

    let accel =
      sample.accelerometer.map {
        "(\($0.x.oneDecimal), \($0.y.oneDecimal), \($0.z.oneDecimal)) m/s²"
      } ?? "none"
    let gyro =
      sample.gyroscope.map {
        "(\($0.x.twoDecimals), \($0.y.twoDecimals), \($0.z.twoDecimals)) rad/s"
      } ?? "none"
    let field =
      sample.magnetometer.map {
        "(\($0.x.oneDecimal), \($0.y.oneDecimal), \($0.z.oneDecimal)) µT"
      } ?? "none"
    let attitude =
      sample.orientation.map {
        "(\($0.x.twoDecimals), \($0.y.twoDecimals), \($0.z.twoDecimals), \($0.w.twoDecimals))"
      } ?? "none"
    BirdLog.debug(
      .glasses,
      "motion — \(String(describing: sample.source)) accel \(accel) · gyro \(gyro) · "
        + "mag \(field) · orientation \(attitude) · t \(sample.timestampNs / 1_000_000) ms"
    )
  }

  /// One event off the capability, translated into something the app has a meaning for —
  /// or, far more often, deliberately dropped.
  ///
  /// **Everything is logged, including what is ignored.** Two questions about this hardware
  /// are still open and only a real pair of glasses can answer them: how a fast double press
  /// is decomposed — two short presses, one double, or all three — and whether a short press
  /// also leaves a photograph in the wearer's own camera roll. Both are read straight off
  /// these lines, which is why the ignored press types say so out loud instead of vanishing.
  private func receive(_ event: InputEvent) {
    switch event {
    case let .capture(pressType, source, _):
      guard pressType == .shortPress, source == .captureButton else {
        BirdLog.debug(
          .glasses,
          "input — ignored capture \(String(describing: pressType)) "
            + "from \(String(describing: source))"
        )
        return
      }
      BirdLog.info(.glasses, "input — capture button, short press")
      publish(.shutter)
    case let .back(source, _):
      // **Unfiltered by source, unlike the shutter.** A back is the same request from the
      // wearer whatever sent it, and answering only one surface would make the gesture work
      // or not work depending on what they happen to have on. In practice the temple is the
      // only one that can send it, since the band is not subscribed — but that is a fact
      // about the attach request, not something this handler should re-decide. The source is
      // logged instead, because which surfaces actually send it is a fact about this
      // hardware nobody has read off a real pair yet.
      BirdLog.info(.glasses, "input — back from \(String(describing: source))")
      publish(.back)
    default:
      // Nothing else has a meaning up there, so anything else arriving is worth a line: it
      // means the configuration is not the whole story about what this pair sends.
      BirdLog.debug(.glasses, "input — ignored \(String(describing: event))")
    }
  }

  /// Hands a gesture to everyone listening. One with nobody listening is dropped, which is
  /// what should happen to a temple pressed while no session is watching for it.
  private func publish(_ event: GlassesInputEvent) {
    let listeners = lock.withLock { Array(inputListeners.values) }
    for listener in listeners { listener.yield(event) }
  }

  /// Subscribes to the photo capability for the life of the session.
  ///
  /// **The subscription has to exist before the shutter fires.** The shutter no longer
  /// answers the call that pulls it: `capturePhoto` returns at once and the picture lands
  /// later on `photoDataPublisher`, which replays nothing. A listener registered per
  /// capture would race the arrival and could miss it outright, so all three publishers are
  /// subscribed once, here, the moment the capability attaches.
  ///
  /// Each arrival is handed to whatever crossing is waiting — see
  /// ``captureThroughActiveCamera(format:)``. An arrival with no crossing waiting is
  /// dropped, which is what should happen to a photograph nobody asked for.
  private func observePhotoCaptures(
    _ camera: Camera,
    announcingTo continuation: AsyncThrowingStream<GlassesSessionState, Error>.Continuation
  ) {
    let photo = camera.photo

    photo.statePublisher.listen { [weak self] state in
      // The reading that was missing, and the one that explains a shutter failing the
      // instant it is pressed: a capture asked of a capability that is not `started` is
      // refused synchronously, and the refusal arrives looking exactly like a Bluetooth
      // crossing that went nowhere.
      BirdLog.debug(.glasses, "camera photo — \(String(describing: state))")
      guard let self else { return }
      switch state {
      case .started:
        // **The session is announced here and nowhere else.** This is the first moment
        // a press can actually produce a photograph, and the pill must not claim the
        // glasses before it.
        let carriesAudio = self.lock.withLock {
          self.isPhotoStarted = true
          return self.streamCarriesAudio
        }
        // The frames have done their job — see ``releaseVideoStream()``. Put down
        // before the session is announced, so the shutter is alone on the sensor by the
        // time anything on screen invites a press. A stream carrying the microphone
        // stays up instead, and steps aside per photograph.
        if !carriesAudio { self.releaseVideoStream() }
        continuation.yield(.started)
      case .stopped, .stopping:
        self.lock.withLock {
          self.isPhotoStarted = false
          // Asked again the next time the frames flow, so a shutter that went down
          // under a stream coming back from a photograph comes back with it.
          self.photoStartRequested = false
        }
        // A photograph cannot outlive the capability carrying it.
        self.failPendingPhoto()
      default:
        break // starting — still the linking beat
      }
    }.store(in: photoTokens)

    photo.photoDataPublisher.listen { [weak self] photoData in
      // The metadata length is logged because it is the open question on this path: if
      // the orientation lives there rather than in the image bytes, this is the line
      // that says so on the first crossing through real glasses.
      BirdLog.debug(
        .glasses,
        "capture — \(photoData.imageData.count) bytes, "
          + "\(photoData.metadata?.count ?? 0) bytes of metadata"
      )
      guard let waiting = self?.takePendingPhoto() else {
        BirdLog.debug(.glasses, "capture — a photograph arrived with nothing waiting on it")
        return
      }
      waiting.yield(photoData.imageData)
      waiting.finish()
    }.store(in: photoTokens)

    photo.errorPublisher.listen { [weak self] error in
      // **`description` is the case and nothing else.** Two of the three cases carry an
      // underlying error, and that is the half that says what actually went wrong —
      // dropped, three unrelated causes arrive on the log as one identical line.
      let detail: String
      switch error {
      case .captureFailure(let underlying), .sessionSetupFailed(let underlying):
        detail = underlying.map { " — \($0)" } ?? " — no underlying error given"
      default:
        detail = ""
      }
      BirdLog.error(.glasses, "capture failed: \(error.description)\(detail)")
      // The shutter waits on the crossing, not on the SDK call, so the failure has to be
      // delivered there or it waits out the whole timeout.
      self?.failPendingPhoto()
    }.store(in: photoTokens)

    photo.transferProgressPublisher.listen { progress in
      // The one number that explains a crossing that "felt slow" while it is still
      // happening, rather than after the fact from the elapsed total.
      BirdLog.debug(
        .glasses,
        "capture — \(progress.bytesReceived)/\(progress.totalBytes) bytes"
      )
    }.store(in: photoTokens)
  }

  /// Fails whatever photograph is mid-crossing, if any.
  ///
  /// **A crossing cannot outlive the stream it is crossing.** The picture arrives on
  /// `photoDataPublisher` and nothing else wakes that wait, so a session ended under it — a long
  /// press on the temple, a hinge, the watcher tapping the switch — left the shutter sitting on
  /// ``photoTransferTimeout``: fifteen seconds of an empty row on the log, and then a line about
  /// glasses on a screen that had been back on the phone the whole time.
  ///
  /// Finishing the stream with nothing on it is what fails the capture: ``captureThroughActiveCamera(format:)``
  /// takes the first of *a photograph* and *no photograph*, and this is the second.
  ///
  /// The timeout stays, for the case it was written for — a crossing that dies mid-air with the
  /// link still up, which nothing here can hear about.
  private func failPendingPhoto() {
    takePendingPhoto()?.finish()
  }

  /// Claims the waiting crossing, if there is one, so exactly one of its endings can finish
  /// it. Both endings go through here, which is what makes "first one wins" true.
  @discardableResult
  private func takePendingPhoto() -> AsyncStream<Data>.Continuation? {
    lock.withLock {
      defer { pendingPhoto = nil }
      return pendingPhoto
    }
  }

  /// Ends whatever lease is open — the full session or the display's — and waits for it to
  /// be gone.
  ///
  /// **For the mock kit's flip, and nothing else.** Swapping the SDK's providers under an
  /// open session leaves that session pointing at a device that no longer exists, and nothing
  /// in the swap tells it so; ending the lease first is what keeps the flip clean. Asking the
  /// session to stop is enough — its own state stream delivers `stopped`, the collector
  /// finishes, and the ordinary teardown runs — but that lands a beat later, which is why
  /// this waits for the handle to clear rather than returning on the ask.
  ///
  /// A no-op with nothing open, and bounded either way: a session that will not stop inside
  /// a second is a session the flip goes ahead without.
  func endActiveSessions() async {
    lock.withLock { activeSession }?.stop()
    for _ in 0..<endActiveSessionsPolls {
      if lock.withLock({ activeSession == nil }) { return }
      try? await Task.sleep(for: .milliseconds(endActiveSessionsPollMillis))
    }
    BirdLog.error(.glasses, "glasses session — did not end in time for the mock kit's flip")
  }

  /// Stops whatever is still running and forgets the handles. Idempotent — the stream's
  /// termination handler and a stopped session may both arrive here.
  private func releaseLink() {
    // First, so the shutter hears about it now rather than fifteen seconds from now.
    failPendingPhoto()
    // And so the aim stops waiting on a pair that has gone.
    finishMotionListeners()
    // And so the session's ears go back to the phone at once, rather than falling silent.
    finishAudioListeners(throwing: AudioCaptureError.interrupted)
    // And so nothing is still trying to bring a capability back on a session that has ended.
    let (motionRevivalTask, inputsRevivalTask, speechRevivalTask, audioRevivalTask, cameraRevivalTask) = lock.withLock {
      defer {
        motionRevival = nil
        inputsRevival = nil
        speechRevival = nil
        audioRevival = nil
        cameraRevival = nil
        inputsHasActivated = false
        speechHasStarted = false
      }
      return (motionRevival, inputsRevival, speechRevival, audioRevival, cameraRevival)
    }
    motionRevivalTask?.cancel()
    inputsRevivalTask?.cancel()
    speechRevivalTask?.cancel()
    audioRevivalTask?.cancel()
    cameraRevivalTask?.cancel()
    // Never `unavailable` here — that is a fact about the pair, and this is a session ending.
    // A screen still watching should read *it stopped*, not *these glasses cannot do it*.
    publish(speechState: .stopped)

    let (camera, session, token, streamToken, drain, motion, motionReader, display, speech) = lock.withLock {
      defer {
        activeCamera = nil
        activeInputs = nil
        activeMotion = nil
        activeSpeech = nil
        activeDisplay = nil
        activeDeviceIdentifier = nil
        activeSession = nil
        cameraStateToken = nil
        streamStateToken = nil
        inputsDrain = nil
        motionDrain = nil
        // The shutter goes down with the camera, and the next session has to ask it to
        // start again from nothing.
        isPhotoStarted = false
        cameraHasStarted = false
        photoStartRequested = false
        streamStopIntended = false
        // Asked again, from the grant, by the next session.
        streamCarriesAudio = false
        audioConverter = nil
        audioHeardSinceStart = false
      }
      return (
        activeCamera, activeSession, cameraStateToken, streamStateToken,
        inputsDrain, activeMotion, motionDrain, activeDisplay, activeSpeech
      )
    }
    Task { [photoTokens, audioTokens, motionTokens, inputsTokens, displayTokens, speechTokens] in
      await token?.cancel()
      await streamToken?.cancel()
      await photoTokens.cancelAll()
      await audioTokens.cancelAll()
      await motionTokens.cancelAll()
      await inputsTokens.cancelAll()
      await displayTokens.cancelAll()
      await speechTokens.cancelAll()
    }
    drain?.cancel()
    motionReader?.cancel()
    // The *press* listeners are deliberately left registered: a subscription is its owner's
    // lease, and the next session's presses should reach whoever is still holding one. The
    // motion listeners are not, and that asymmetry is deliberate — see
    // ``finishMotionListeners()``. A press nobody sends is a wearer who did not press; a
    // reading nobody sends is an instrument the aim has to stop waiting on and replace with
    // the phone's.
    //
    // Removing is the only way to switch inputs off — the capability has no stop of its
    // own, having started itself the moment it attached.
    try? session?.removeInputs()
    // Motion does have a stop, and it is the one that puts the sensor down; removing the
    // capability then releases it with the session.
    motion?.stop()
    try? session?.removeMotion()
    // The recogniser goes down the same way the sensor does, and for the same reason:
    // `stop()` is what stops it listening, and removing it releases the capability.
    speech?.stop()
    try? session?.removeSpeech()
    // The display goes dark with the session that was feeding it.
    display?.stop()
    // Stopping the camera cascades to the stream and the shutter it owns.
    camera?.stop()
    session?.stop()
  }
}

/// How long a photograph gets to cross before the shutter is failed. The published claim
/// is about a second; fifteen forgives a congested link without stranding the UI forever.
private nonisolated let photoTransferTimeout = Duration.seconds(15)

/// How often the full motion reading is written out — see ``describeEvery(_:)``.
private nonisolated let motionLogIntervalMillis: Int64 = 3_000

/// How long a capability gets between tries at coming back — see ``DatGlassesSessionRepository``.
private nonisolated let sensorRevivalDelay = Duration.milliseconds(750)

/// How many times the sensor is asked to start again before the aim goes back to the phone.
private nonisolated let sensorRevivalAttempts = 3

/// How long a stream set aside for a photograph gets to let go of the sensor before the shutter
/// fires anyway — see ``DatGlassesSessionRepository``. A refused still is the worst that follows.
private nonisolated let streamSetAsideTimeout = Duration.seconds(2)

/// How long a stream started again after a photograph gets to deliver a buffer before its
/// listeners are handed back to the phone — see ``DatGlassesSessionRepository``.
private nonisolated let audioRevivalPatience = Duration.seconds(5)

private extension CaptureResolution {
  /// The domain's size on the capability's own ladder. The two lists are the same four
  /// steps, so this is a rename and nothing more — but it is the rename that keeps the SDK's
  /// vocabulary out of every screen that wants to ask for a bigger photograph.
  nonisolated var datResolution: PhotoResolution {
    switch self {
    case .small: .small
    case .medium: .medium
    case .large: .large
    case .full: .full
    }
  }
}

private extension CaptureQuality {
  /// The same, for compression. See ``CaptureQuality`` for what the app's own default costs.
  nonisolated var datQuality: PhotoQuality {
    switch self {
    case .low: .low
    case .medium: .medium
    case .high: .high
    }
  }
}

private extension Float {
  /// A sensor reading at the precision a log line can use, without going through a formatter —
  /// the decimal separator of whatever locale the phone is set to has no business in a
  /// diagnostic that gets pasted into a bug report.
  var oneDecimal: Double { Double((self * 10).rounded()) / 10 }

  /// The same, for the readings a single decimal would flatten to zero — a gyroscope in rad/s
  /// spends most of its life under `0.05`, and a column of `0.0` says nothing at all.
  var twoDecimals: Double { Double((self * 100).rounded()) / 100 }
}

private extension Duration {
  /// Whole milliseconds, for a log line. Read off a monotonic clock, which is the property
  /// that matters: a wall clock corrected mid-crossing would otherwise report a photograph
  /// that took negative time.
  var milliseconds: Int64 {
    let (seconds, attoseconds) = components
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }
}

private extension DeviceSessionError {
  /// What a session failure means to the app.
  ///
  /// **One case is singled out, and the rest deliberately are not.** The screen can offer
  /// exactly two answers — go update your glasses, or try again — so the only distinction
  /// worth carrying up is the one that changes which of those a wearer is told. Everything
  /// else (nothing eligible, a session already running, heat, power) is a link that will not
  /// hold, which is what ``GlassesError/notConnected`` says; the specific case is in the log
  /// line above, which is where it is any use.
  nonisolated var asGlassesError: GlassesError {
    switch self {
    case .datAppOnTheGlassesUpdateRequired: .glassesUpdateRequired
    default: .notConnected
    }
  }
}

extension GlassesPermission {
  /// The SDK's own case. Exhaustive on purpose: DAT's `Permission` is the reason this
  /// domain enum has the two cases it has, and a third arriving in a preview release
  /// should stop the build here rather than quietly go unaskable.
  ///
  /// Not private, because *reading* a grant and *asking* for one are split across two
  /// layers — the settings screen owns the raise, for the reason ``PermissionsController``
  /// documents — and one translation of the same two cases is enough.
  ///
  /// The module qualifier is load-bearing: the app has a `Permission` of its own, for the
  /// OS grants, and this file is where the two names meet.
  nonisolated var datPermission: MWDATCore.Permission {
    switch self {
    case .camera: .camera
    case .microphone: .microphone
    }
  }

  /// What to call it in the log — the grants read identically, so the line has to say
  /// which one was asked about.
  nonisolated fileprivate var logName: String {
    switch self {
    case .camera: "camera"
    case .microphone: "microphone"
    }
  }
}

private extension GlassesCompatibility {
  nonisolated init(_ compatibility: Compatibility) {
    switch compatibility {
    case .compatible: self = .compatible
    case .deviceUpdateRequired: self = .deviceUpdateRequired
    case .sdkUpdateRequired: self = .sdkUpdateRequired
    case .undefined: self = .unknown
    default: self = .unknown
    }
  }
}

private extension GlassesRegistrationState {
  nonisolated init(_ state: RegistrationState) {
    switch state {
    case .available: self = .available
    case .registering: self = .registering
    case .registered: self = .registered
    case .unavailable: self = .unavailable
    default: self = .unavailable
    }
  }
}

private extension DonState {
  /// Worn as the tri-state fact the domain carries — the SDK's `unknown` is genuinely
  /// no answer, not a doff.
  nonisolated var asWorn: Bool? {
    switch self {
    case .donned: true
    case .doffed: false
    default: nil
    }
  }
}

private extension ChargingState {
  nonisolated var asCharging: Bool? {
    switch self {
    case .charging: true
    case .notCharging: false
    default: nil
    }
  }
}

private extension ThermalLevel {
  /// The SDK's eight grades, collapsed to the three a wearer can act on.
  ///
  /// **Where the lines fall is the judgement.** `light` sits with nominal because warm
  /// glasses are the normal state of glasses doing anything at all, and a panel that
  /// cries heat during ordinary use teaches the wearer to ignore it. `moderate` is where
  /// the SDK starts throttling, which is the first thing worth saying out loud.
  /// `critical` and up are the grades the session's own errors fire from, so the row and
  /// the session agree about when the run is in danger.
  nonisolated var asGlassesThermal: GlassesThermalLevel? {
    switch self {
    case .none, .light: .nominal
    case .moderate, .severe: .elevated
    case .critical, .emergency, .shutdown: .critical
    default: nil
    }
  }
}

/// How long ``DatGlassesSessionRepository/endActiveSessions()`` waits for a lease to clear —
/// twenty looks, fifty milliseconds apart: a second, which a stopping session never needs.
private let endActiveSessionsPolls = 20
private let endActiveSessionsPollMillis = 50
