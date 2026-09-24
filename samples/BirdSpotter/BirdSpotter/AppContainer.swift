/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  AppContainer.swift
//  birdspotter
//

import Foundation

/// The composition root: every long-lived dependency, built once and handed down.
///
/// No DI framework, deliberately. The object graph is a handful of repositories over two
/// SQLite files and (later) the DAT SDK, and the mirrored-architecture contract asks for
/// init injection, so anything Meta puts in a side-by-side snippet has to be constructed
/// the plain way rather than conjured by an annotation.
///
/// Built once in `birdspotterApp` and passed into the view tree.
@MainActor
final class AppContainer {

  /// The rolling diagnostic log's files — where the Diagnostics screen reads them from,
  /// and where ``FileLogSink`` writes them. See ``DiagnosticsLogStore``.
  let diagnosticsLogStore: DiagnosticsLogStore

  /// Whether the log writes files, and how far down it records. Read before the first line
  /// of the run — see ``installDiagnostics()``.
  let diagnosticsSettings: DiagnosticsSettingsStore

  let birdCatalogRepository: any BirdCatalogRepository

  /// Bundled photos and calls. Not a repository — it resolves files, not rows.
  let catalogAssetStore: CatalogAssetStore

  let journalRepository: any JournalRepository

  /// The captured-media directory, shared by the Journal store and the screens that draw
  /// captured photos. Exposed like ``catalogAssetStore`` — it resolves files, not rows.
  let mediaFileStore: MediaFileStore

  /// Where a photograph taken only to be looked at lands. Nothing in the Journal's world
  /// touches it — see ``CaptureScratchStore``.
  let captureScratchStore: CaptureScratchStore

  /// OS permission status for the Identify tab's gates (camera, mic, location) and the trip
  /// back to Settings. Requesting the prompt lives in the Identify screen — see
  /// ``PermissionsController``.
  let permissionsController: any PermissionsController

  /// Phone GPS for the sighting stamp — one fix per identify run. See ``LocationProvider``.
  let locationProvider: any LocationProvider

  /// The phone's compass, for as long as a session is watching it. See ``HeadingProvider``.
  let headingProvider: any HeadingProvider

  /// How high the phone is aimed, for as long as a session is watching it. Its own provider rather
  /// than a second question put to ``headingProvider`` — see ``GazeProvider``.
  let gazeProvider: any GazeProvider

  /// The live viewfinder's frames — the phone's, and only the phone's: the glasses have no
  /// viewfinder in this app, and their photographs arrive finished through
  /// ``glassesCameraRepository`` instead. See ``CameraPreviewSource``.
  let cameraPreviewSource: any CameraPreviewSource

  /// The real-time session's spine. Held open for the whole session, where the camera comes
  /// and goes — see ``AudioCaptureSource``.
  ///
  /// A ``FailoverAudioSource`` in the built app: the phone's microphone until a glasses session
  /// is live, the glasses' while it is, and the phone's again the moment it is not.
  let audioCaptureSource: any AudioCaptureSource

  /// The app's own voice — an identification said where the wearer will hear it, when there
  /// is an ear to say it into. See ``SpokenOutput``.
  let spokenOutput: any SpokenOutput

  /// The Demo Director's saved presets and armed id. Shared by the Director (which reads
  /// the armed preset) and the settings screens (which author and arm them) — one store,
  /// so arming in Settings is what the next session plays.
  let demoSettingsStore: DemoSettingsStore

  /// The Demo Director: scripts what the app "identifies", from the armed preset — see
  /// ``DemoDirector``. Exposed with its full surface so the settings panel and the photo/STT
  /// paths reach the parts that answer on cue; the realtime session takes it as
  /// ``sessionDetector``.
  let demoDirector: any DemoDirector

  /// What decides a bird was heard. The Director wearing its ``SessionDetector`` hat —
  /// scripted on purpose, per the honest-fakes pillar.
  let sessionDetector: any SessionDetector

  /// Hands a logged sighting's location off to Apple Maps. See ``MapLauncher``.
  let mapLauncher: any MapLauncher

  /// The app's standing with the glasses — registration, the device that would answer, and
  /// the session a live run holds open. See ``GlassesSessionRepository``.
  let glassesSessionRepository: any GlassesSessionRepository

  /// The glasses camera: one photograph on demand, through the running session's camera.
  /// Shares the session repository underneath because a capture is scoped to the
  /// session's own camera capability — see ``GlassesCameraRepository``.
  let glassesCameraRepository: any GlassesCameraRepository

  /// The buttons on the glasses, for as long as a session is listening. Shares the session
  /// repository for the same reason the camera does — the capability rides the session. See
  /// ``GlassesInputRepository``.
  let glassesInputRepository: any GlassesInputRepository

  /// The display on the glasses — an identified bird's photographs, paged where the wearer
  /// is already looking. Shares the session repository because the capability rides the
  /// session, and the asset store because the photographs are the catalog's own. See
  /// ``GlassesDisplayRepository``.
  let glassesDisplayRepository: any GlassesDisplayRepository

  /// What the wearer says, transcribed on the glasses themselves. Shares the session repository
  /// for the same reason every other sense does — the capability rides the session.
  ///
  /// **No phone-side counterpart, and that is the design.** Every other sense here has a
  /// failover onto the device in the watcher's hand; this one deliberately does not, because a
  /// phone recogniser would have to take the microphone away from the ambient lane to work. See
  /// ``GlassesSpeechRepository``.
  let glassesSpeechRepository: any GlassesSpeechRepository

  /// What the wearer says to Meta AI about this app — "Hey Meta, open BirdSpotter" — and
  /// the acknowledgement each invocation is owed. Its own object rather than another hat
  /// on the session repository: a launch is what *asks* for a session, so the channel
  /// cannot ride one. See ``GlassesVoiceRepository``.
  let glassesVoiceRepository: any GlassesVoiceRepository

  /// How the mock is set: the switch, the model it fakes, where its button was pinned.
  /// Shared by the repository (which restores it at launch) and the overlay (which moves the
  /// button) — one store, so the pin survives the relaunch. See ``MockDeviceSettingsStore``.
  let mockDeviceSettingsStore: MockDeviceSettingsStore

  /// Meta's Mock Device Kit, as the app drives it: the switch that stands simulated glasses
  /// in for real ones, and the controls on the simulated pair. Built after the session
  /// repository because the flip has to end that repository's leases first, and built at
  /// launch because building it is what restores the last choice. See ``MockDeviceRepository``.
  let mockDeviceRepository: any MockDeviceRepository

  /// The one real-time session the app can hold, alive whether or not a screen is showing it.
  /// Here rather than in the cover that draws it because a session started by a voice launch
  /// with the phone locked in a pocket has no cover, and a cover that falls must not take a
  /// session in progress down with it.
  ///
  /// Lazy, because its strip allocates its whole ring up front and nothing needs it until
  /// a session is asked for.
  lazy var realtimeViewModel = RealtimeViewModel(
    audioSource: audioCaptureSource,
    previewSource: cameraPreviewSource,
    detector: sessionDetector,
    director: demoDirector,
    birdCatalog: birdCatalogRepository,
    journal: journalRepository,
    glassesSession: glassesSessionRepository,
    glassesCamera: glassesCameraRepository,
    glassesInput: glassesInputRepository,
    glassesSpeech: glassesSpeechRepository,
    glassesDisplay: glassesDisplayRepository,
    spokenOutput: spokenOutput,
    locationProvider: locationProvider,
    headingProvider: headingProvider,
    gazeProvider: gazeProvider
  )

  init() {
    // **First, before anything else is built.** Everything below this line can fail in a
    // way worth a log line, and a logger installed after them is a logger that missed the
    // launch — which is the run people most often come asking about.
    diagnosticsLogStore = DiagnosticsLogStore.open()
    diagnosticsSettings = DiagnosticsSettingsStore.open()
    // The static form, because `self` is not whole yet — and it has to happen here
    // rather than at the end of `init` for the reason above.
    Self.installDiagnostics(store: diagnosticsLogStore, settings: diagnosticsSettings)

    catalogAssetStore = CatalogAssetStore()

    // A catalog that cannot be opened is a build that was never staged, so the app degrades to an empty
    // guide and says so on screen rather than crashing on launch. It is the one
    // failure here worth surviving: the Explore screen already has an honest empty
    // state, and every other screen works without the catalog.
    do {
      let database = try CatalogDatabase.open()
      birdCatalogRepository = LocalBirdCatalogRepository(store: database.speciesStore())
    } catch {
      BirdLog.error(.catalog, "could not open the bird catalog", error)
      birdCatalogRepository = EmptyBirdCatalogRepository()
    }

    // The journal is different: it lives in Application Support and is created on
    // demand, so failing to open it means the filesystem itself is broken — which no
    // fallback mends, and which hiding would turn into silently discarded sightings.
    do {
      let journalDatabase = try JournalDatabase.open()
      mediaFileStore = try MediaFileStore.open()
      // Caches, so a failure here is a failure to make a directory the system hands out
      // freely — the same "the filesystem itself is broken" the two stores above assume.
      captureScratchStore = try CaptureScratchStore.open()
      journalRepository = LocalJournalRepository(
        store: journalDatabase.journalStore(),
        mediaFileStore: mediaFileStore
      )
    } catch {
      fatalError("Required app storage is unavailable: \(error)")
    }

    permissionsController = SystemPermissionsController()
    locationProvider = SystemLocationProvider()
    mapLauncher = SystemMapLauncher()
    cameraPreviewSource = PhoneCameraPreviewSource()
    spokenOutput = SystemSpokenOutput()
    demoSettingsStore = DemoSettingsStore.open()
    demoDirector = PresetDemoDirector(
      store: demoSettingsStore,
      catalog: birdCatalogRepository
    )
    sessionDetector = demoDirector

    // The session-scoped glasses repositories are all hats on the one object the live DAT
    // session lives in — a capture, a button press, a motion sample and a transcript are
    // scoped to the session's own capabilities, so the handles have one home.
    let glassesLink = DatGlassesSessionRepository()
    glassesSessionRepository = glassesLink
    // One stream, two microphones underneath — the session asks for the glasses when it
    // has them and is handed the phone back when it does not, without the screen above
    // learning that failover exists. See ``FailoverAudioSource``. The glasses' ears are the
    // session's camera stream, so they hang off the same link as the shutter.
    audioCaptureSource = FailoverAudioSource(
      preferred: GlassesMicrophoneSource(link: glassesLink),
      fallback: PhoneMicrophoneSource()
    )
    glassesCameraRepository = DatGlassesCameraRepository(link: glassesLink)
    glassesInputRepository = DatGlassesInputRepository(link: glassesLink)
    glassesDisplayRepository = DatGlassesDisplayRepository(
      link: glassesLink,
      assets: catalogAssetStore
    )
    glassesSpeechRepository = DatGlassesSpeechRepository(link: glassesLink)
    let glassesVoice = DatGlassesVoiceRepository()
    glassesVoiceRepository = glassesVoice
    let glassesMotion = DatGlassesMotionRepository(link: glassesLink)

    // Last of the glasses objects, deliberately: its construction may swap the SDK's
    // providers for the mock's, and everything above is built to follow that swap
    // through the streams it already holds rather than to be built after it. The two
    // leases the swap cannot carry across — the session and the voice channel — are
    // handed to it so the flip can close them first.
    mockDeviceSettingsStore = MockDeviceSettingsStore.open()
    mockDeviceRepository = DatMockDeviceRepository(
      link: glassesLink,
      voice: glassesVoice,
      settings: mockDeviceSettingsStore
    )

    // Both aim readings work the way the microphone does: the head the wearer is actually
    // aiming when the session has it, the device in their hand when it does not, and nothing
    // above here learns that either one changed. See ``FailoverReadings``.
    headingProvider = FailoverHeadingProvider(
      preferred: GlassesHeadingProvider(motion: glassesMotion),
      fallback: SystemHeadingProvider()
    )
    gazeProvider = FailoverGazeProvider(
      preferred: GlassesGazeProvider(motion: glassesMotion),
      fallback: SystemGazeProvider()
    )
  }

  /// Points ``BirdLog`` at its sinks, per ``diagnosticsSettings``, and opens a file for
  /// this run of the app.
  ///
  /// **Also the Diagnostics screen's apply button.** Turning file logging on or off there
  /// calls this again rather than reaching into ``BirdLog`` itself, so the rule for which
  /// sinks are installed is written once. Re-running it starts another file, which is the
  /// right answer for a switch flipped mid-session: the run before the change and the run
  /// after it are two different things to read.
  ///
  /// The console sink is unconditional. It costs nothing on a device nobody has attached a
  /// debugger to, and switching off the *files* should not also blind the developer who is
  /// sitting in front of Xcode.
  func installDiagnostics() {
    Self.installDiagnostics(store: diagnosticsLogStore, settings: diagnosticsSettings)
  }

  /// The work itself, `static` so ``init()`` can run it before `self` is whole.
  private static func installDiagnostics(
    store: DiagnosticsLogStore,
    settings: DiagnosticsSettingsStore
  ) {
    BirdLog.minimumLevel = settings.minimumLevel

    var sinks: [any LogSink] = [ConsoleLogSink()]
    if settings.isFileLoggingEnabled {
      store.beginNewRun()
      sinks.append(FileLogSink(store: store))
    }
    BirdLog.install(sinks: sinks)

    // The first line of every file, and the one that makes a shared-out log worth
    // reading: which build, on what, recording how much.
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    BirdLog.info(
      .app,
      """
      BirdSpotter \(version) (\(build)) · iOS \(ProcessInfo.processInfo.operatingSystemVersionString) \
      · recording at \(BirdLog.minimumLevel.displayLabel) \
      · files \(settings.isFileLoggingEnabled ? "on" : "off")
      """
    )
  }
}

/// Stands in when `catalog.db` could not be opened. Answers "nothing" to everything,
/// which is what the UI's empty state already renders.
private struct EmptyBirdCatalogRepository: BirdCatalogRepository {
  func allSpecies() async throws -> [Species] { [] }
  func browseGroups() async throws -> [SpeciesGroup] { [] }
  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? { nil }
  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] { [] }
  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? { nil }
  func seedVersion() async throws -> Int? { nil }
}
