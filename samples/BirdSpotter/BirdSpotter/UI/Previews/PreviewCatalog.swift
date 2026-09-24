/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PreviewCatalog.swift
//  birdspotter
//

import CoreGraphics
import Foundation

/// Preview fixtures — one real species, verbatim from the seed.
///
/// Previews run without the app's database, so they get their rows directly. The rows are
/// copied from the bundled catalog rather than invented, which means
/// the photos and the credits resolve for real: `SeedData/` is in the preview bundle too.
///
/// `nonisolated` for the same reason the data layer is: these are plain values, and the
/// target defaults top-level declarations to the main actor, which would make a preview
/// repository's `async` methods unable to read them.
nonisolated enum PreviewCatalog {

  /// The Northern Cardinal as shipped: three photos, a song, and the song's sonogram.
  static let bird = SpeciesWithMedia(
    species: Species(
      id: "northern-cardinal",
      commonName: "Northern Cardinal",
      scientificName: "Cardinalis cardinalis",
      familyName: "Cardinalidae",
      browseOrder: 920,
      groupName: "Cardinals & Grosbeaks",
      sizeClass: 2,
      aboutText: """
        A large, long-tailed songbird with a pointed crest and a heavy red-orange \
        bill. Males are brilliant red; females are warm tan with red accents. \
        Non-migratory and common at feeders across eastern and central North America.
        """,
      habitatText: """
        Woodland edges, thickets, backyards, and overgrown fields. Favors dense \
        shrubby cover for nesting and forages on or near the ground.
        """
    ),
    media: [
      SpeciesMedia(
        id: "northern-cardinal-photo-01",
        speciesId: "northern-cardinal",
        type: .photo,
        assetKey: "northern-cardinal/photo-01",
        credit: "patricia pierce / Wikimedia Commons (CC BY 2.0)",
        isPrimary: true,
        focusX: 0.51,
        focusY: 0.23,
        durationMs: nil,
        sortOrder: 0
      ),
      SpeciesMedia(
        id: "northern-cardinal-photo-02",
        speciesId: "northern-cardinal",
        type: .photo,
        assetKey: "northern-cardinal/photo-02",
        credit: "lwolfartist / Wikimedia Commons (CC BY 2.0)",
        isPrimary: false,
        focusX: 0.62,
        focusY: 0.31,
        durationMs: nil,
        sortOrder: 1
      ),
      SpeciesMedia(
        id: "northern-cardinal-photo-03",
        speciesId: "northern-cardinal",
        type: .photo,
        assetKey: "northern-cardinal/photo-03",
        credit: "Daniel Dwyer Jr / Wikimedia Commons (CC BY 4.0)",
        isPrimary: false,
        focusX: 0.63,
        focusY: 0.34,
        durationMs: nil,
        sortOrder: 2
      ),
      SpeciesMedia(
        id: "northern-cardinal-song-01",
        speciesId: "northern-cardinal",
        type: .song,
        assetKey: "northern-cardinal/song-01",
        credit: "steve / Xeno-canto (CC BY-SA 4.0)",
        isPrimary: true,
        focusX: nil,
        focusY: nil,
        durationMs: 12_000,
        sex: "male",
        stage: "adult",
        sortOrder: 0
      ),
      SpeciesMedia(
        id: "northern-cardinal-sonogram-01",
        speciesId: "northern-cardinal",
        type: .sonogram,
        assetKey: "northern-cardinal/sonogram-01",
        credit: "steve / Xeno-canto (CC BY-SA 4.0)",
        isPrimary: false,
        focusX: nil,
        focusY: nil,
        durationMs: nil,
        sortOrder: 0
      ),
    ]
  )

  /// Two sections of the browse list, in the order the seed puts them.
  ///
  /// Real ids, names and `browseOrder`s, so a preview shows the guide's actual sequence
  /// rather than a plausible-looking invention — and so a group that stopped being
  /// contiguous would look wrong here too. Hero photos only: the list never asks a row
  /// for anything else.
  static let guide = [
    group(
      "Jays & Crows",
      [
        row("american-crow", "American Crow", "Corvus brachyrhynchos", "Corvidae", 370, 5),
        row("blue-jay", "Blue Jay", "Cyanocitta cristata", "Corvidae", 390, 4),
        row("common-raven", "Common Raven", "Corvus corax", "Corvidae", 410, 6),
      ]),
    group(
      "Thrushes",
      [
        row("american-robin", "American Robin", "Turdus migratorius", "Turdidae", 600, 3),
        row("eastern-bluebird", "Eastern Bluebird", "Sialia sialis", "Turdidae", 610, 2),
        row("wood-thrush", "Wood Thrush", "Hylocichla mustelina", "Turdidae", 630, 3),
      ]),
  ]

  /// A Blue Jay, identified — the second bird a preview Journal needs beyond the cardinal.
  static let blueJay = SpeciesWithMedia(
    species: Species(
      id: "blue-jay",
      commonName: "Blue Jay",
      scientificName: "Cyanocitta cristata",
      familyName: "Corvidae",
      browseOrder: 390,
      groupName: "Jays & Crows",
      sizeClass: 4,
      aboutText: "",
      habitatText: ""
    ),
    media: [
      SpeciesMedia(
        id: "blue-jay-photo-01",
        speciesId: "blue-jay",
        type: .photo,
        assetKey: "blue-jay/photo-01",
        credit: nil,
        isPrimary: true,
        focusX: nil,
        focusY: nil,
        durationMs: nil,
        sortOrder: 0
      )
    ]
  )

  /// Three outings across two months — a wizard entry with its answers, a live outing
  /// that confirmed two birds, and a live outing that confirmed none — so a preview
  /// Journal shows a grouped list, the search results, and every headline branch of the
  /// labeling rule (bird-led, bird + n more, date-led). Timestamps are fixed (mid-2026,
  /// midday UTC) so the month buckets are deterministic, and the coordinates are real
  /// Cincinnati-area points so the detail screen's map draws somewhere plausible.
  static let journalEntries: [JournalEntry] = {
    let wizardOuting = outing(
      "preview-outing-1",
      kind: .manual,
      startedAt: 1_784_203_200_000,
      latitude: 39.2098,
      longitude: -84.4699,
      notes: "Singing from the very top of a bare maple — unmistakable once it started."
    )
    let wizardBird = confirmed(
      "preview-sighting-1",
      outingId: wizardOuting.id,
      speciesId: "northern-cardinal",
      createdAt: wizardOuting.startedAt
    )

    let liveOuting = outing(
      "preview-outing-2",
      kind: .live,
      startedAt: 1_783_155_600_000,
      durationMs: 14 * 60_000,
      latitude: 39.1523,
      longitude: -84.3822
    )
    // Both birds were heard, so each carries its moment and its score on the detection
    // behind it and nothing on the sighting itself. Neither gets a "Looking"/"Facing"
    // row on the detail screen, which is the honest rendering for a bird nothing aimed
    // a camera at.
    let firstHeard = heardDetection(
      "preview-detection-1",
      outingId: liveOuting.id,
      speciesId: "blue-jay",
      confidence: 0.87,
      offsetMs: 320_000,
      createdAt: liveOuting.startedAt + 320_000
    )
    let secondHeard = heardDetection(
      "preview-detection-2",
      outingId: liveOuting.id,
      speciesId: "northern-cardinal",
      confidence: 0.74,
      offsetMs: 610_000,
      createdAt: liveOuting.startedAt + 610_000
    )
    let firstBird = confirmed(
      "preview-sighting-2",
      outingId: liveOuting.id,
      speciesId: "blue-jay",
      sourceEventId: firstHeard.id,
      createdAt: liveOuting.startedAt + 320_000
    )
    let secondBird = confirmed(
      "preview-sighting-3",
      outingId: liveOuting.id,
      speciesId: "northern-cardinal",
      sourceEventId: secondHeard.id,
      createdAt: liveOuting.startedAt + 610_000
    )

    let birdlessOuting = outing(
      "preview-outing-3",
      kind: .live,
      startedAt: 1_781_940_600_000,
      durationMs: 6 * 60_000,
      latitude: 39.2277,
      longitude: -84.4530
    )

    return [
      JournalEntry(
        withChildren: OutingWithChildren(
          outing: wizardOuting,
          events: wizardAnswers(
            wizardOuting, size: "2", colors: "BLACK,RED", behavior: "IN_TREES_OR_BUSHES"
          ),
          sightings: [wizardBird]
        ),
        birds: [ConfirmedBird(sighting: wizardBird, species: bird)]
      ),
      JournalEntry(
        withChildren: OutingWithChildren(
          outing: liveOuting,
          events: [firstHeard, secondHeard],
          sightings: [firstBird, secondBird]
        ),
        birds: [
          ConfirmedBird(sighting: firstBird, species: blueJay),
          ConfirmedBird(sighting: secondBird, species: bird),
        ]
      ),
      JournalEntry(
        withChildren: OutingWithChildren(outing: birdlessOuting),
        birds: []
      ),
    ]
  }()

  /// The birdless live outing — the Merlin "0 birds, saved anyway" state, first-class.
  static let birdlessJournalEntry = journalEntries[2]

  /// The entries grouped as the Journal shows them — through the real grouping, so a preview
  /// reflects what ships.
  static let journalMonths = JournalViewModel.groupByMonth(journalEntries)

  private static func outing(
    _ id: String,
    kind: OutingKind,
    startedAt: Int64,
    durationMs: Int64? = nil,
    latitude: Double,
    longitude: Double,
    notes: String? = nil
  ) -> Outing {
    Outing(
      id: id,
      kind: kind,
      startedAt: startedAt,
      durationMs: durationMs,
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      createdAt: startedAt,
      updatedAt: startedAt
    )
  }

  private static func confirmed(
    _ id: String,
    outingId: String,
    speciesId: String,
    sourceEventId: String? = nil,
    createdAt: Int64
  ) -> Sighting {
    Sighting(
      id: id,
      outingId: outingId,
      sourceEventId: sourceEventId,
      speciesId: speciesId,
      createdAt: createdAt
    )
  }

  /// A bird the classifier heard — the moment and the score live here, not on the sighting.
  private static func heardDetection(
    _ id: String,
    outingId: String,
    speciesId: String,
    confidence: Double,
    offsetMs: Int64,
    createdAt: Int64
  ) -> OutingEvent {
    OutingEvent(
      id: id,
      outingId: outingId,
      mediaId: nil,
      type: .detection,
      offsetMs: offsetMs,
      speciesId: speciesId,
      confidence: confidence,
      question: nil,
      answer: nil,
      trait: nil,
      value: nil,
      createdAt: createdAt
    )
  }

  /// The wizard's three answers, in trait order, the way `saveSighting` writes them.
  private static func wizardAnswers(
    _ outing: Outing,
    size: String,
    colors: String,
    behavior: String
  ) -> [OutingEvent] {
    let answers: [(WizardTrait, String)] = [(.size, size), (.colors, colors), (.behavior, behavior)]
    return answers.enumerated().map { index, answer in
      OutingEvent(
        id: "\(outing.id)-answer-\(index)",
        outingId: outing.id,
        mediaId: nil,
        type: .wizardAnswer,
        offsetMs: nil,
        speciesId: nil,
        confidence: nil,
        question: nil,
        answer: nil,
        trait: answer.0,
        value: answer.1,
        createdAt: outing.startedAt
      )
    }
  }

  private static func group(
    _ name: String,
    _ species: [(String) -> SpeciesWithMedia]
  ) -> SpeciesGroup {
    SpeciesGroup(name: name, species: species.map { $0(name) })
  }

  private static func row(
    _ id: String,
    _ commonName: String,
    _ scientificName: String,
    _ familyName: String,
    _ browseOrder: Int,
    _ sizeClass: Int
  ) -> (String) -> SpeciesWithMedia {
    { groupName in
      SpeciesWithMedia(
        species: Species(
          id: id,
          commonName: commonName,
          scientificName: scientificName,
          familyName: familyName,
          browseOrder: browseOrder,
          groupName: groupName,
          sizeClass: sizeClass,
          aboutText: "",
          habitatText: ""
        ),
        media: [
          SpeciesMedia(
            id: "\(id)-photo-01",
            speciesId: id,
            type: .photo,
            assetKey: "\(id)/photo-01",
            credit: nil,
            isPrimary: true,
            focusX: nil,
            focusY: nil,
            durationMs: nil,
            sortOrder: 0
          )
        ]
      )
    }
  }
}

/// Stands in for the real catalog in previews. `isEmpty` drives the honest empty states —
/// the ones that only appear when the seed failed to stage.
nonisolated struct PreviewBirdCatalog: BirdCatalogRepository {
  var isEmpty = false

  func allSpecies() async throws -> [Species] {
    isEmpty ? [] : [PreviewCatalog.bird.species]
  }

  func browseGroups() async throws -> [SpeciesGroup] {
    isEmpty ? [] : PreviewCatalog.guide
  }

  func findById(_ speciesId: String) async throws -> SpeciesWithMedia? {
    isEmpty ? nil : PreviewCatalog.bird
  }

  func identifyCandidates(_ query: IdentifyQuery) async throws -> [SpeciesWithMedia] {
    isEmpty ? [] : [PreviewCatalog.bird]
  }

  func birdOfTheDay(epochDay: Int64) async throws -> SpeciesWithMedia? {
    isEmpty ? nil : PreviewCatalog.bird
  }

  func seedVersion() async throws -> Int? { 1 }
}

/// Stands in for a camera in previews, which have none.
///
/// The three shapes it takes are the three the viewfinder has to draw: a frame that arrives and
/// stays (the default), a stream that never produces one (`isSilent` — the opening beat), and one
/// that gives up straight away (`failure`). Leaving the continuation unfinished is what holds the
/// first two open, exactly as a real camera would.
///
/// A preview cannot hand a `PreviewFrame` straight to the viewfinder while the view owns its
/// model, so the frames arrive the way a camera's would: through a source.
nonisolated struct PreviewCameraSource: CameraPreviewSource {
  var kind: CaptureSourceKind = .phone
  var isSilent = false
  var failure: CameraPreviewError?

  func previewStream() -> AsyncThrowingStream<PreviewFrame, Error> {
    AsyncThrowingStream { continuation in
      if let failure {
        continuation.finish(throwing: failure)
        return
      }
      guard !isSilent, let frame = PreviewCatalog.viewfinderFrame else { return }
      continuation.yield(frame)
    }
  }
}

/// Stands in for a microphone in previews, which have none.
///
/// Twenty seconds of a wandering tone, handed over a second at a time with a beat between — the
/// session's clock counts columns, so feeding it at thirty times real speed gives a preview a full
/// strip in under a second without anything downstream knowing it was hurried.
///
/// It is not a recording of a bird and does not pretend to be: a preview with no microphone has
/// nothing true to play, and a fabricated robin would be the dishonest kind of fake.
nonisolated struct PreviewAudioSource: AudioCaptureSource {
  var kind: CaptureSourceKind = .phone
  var failure: AudioCaptureError?

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      if let failure {
        continuation.finish(throwing: failure)
        return
      }
      let task = Task {
        for second in 0..<20 {
          continuation.yield(AudioChunk(samples: Self.tone(second: second)))
          try await Task.sleep(for: .milliseconds(30))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// One second of a tone that drifts, so the strip has a shape rather than a stripe.
  private static func tone(second: Int) -> [Float] {
    (0..<captureSampleRate).map { n in
      let t = Double(second) + Double(n) / Double(captureSampleRate)
      let frequency = 900 + 450 * sin(t * 0.9)
      return Float(0.6 * sin(2 * .pi * frequency * t))
    }
  }
}

/// Stands in for the GPS in previews, which have none.
///
/// A fixed point in Cincinnati, handed back after a beat — the beat is the part that matters, since
/// what the real-time header draws is a dot arriving partway into a session rather than a dot that
/// was always lit. `never` is the other half of the surface: a fix that does not come, which is
/// every way of not knowing rolled into the one `nil` ``LocationProvider`` promises.
struct PreviewLocationProvider: LocationProvider {
  var never = false

  func currentCoordinate() async -> Coordinate? {
    try? await Task.sleep(for: .milliseconds(400))
    return never ? nil : Coordinate(latitude: 39.1420, longitude: -84.5063)
  }
}

/// Stands in for the compass in previews, which have none.
///
/// Turns slowly through a full circle rather than holding one bearing, so a preview shows the plate
/// changing letters — the thing worth looking at — instead of a single `NE` that could as easily be
/// hard-coded. `silent` is the other half of the surface: a phone with no magnetometer, including
/// every simulator.
struct PreviewHeadingProvider: HeadingProvider {
  var silent = false

  func headingStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      guard !silent else {
        continuation.finish()
        return
      }
      let task = Task {
        var bearing = 20.0
        while !Task.isCancelled {
          continuation.yield(bearing)
          bearing += 11
          try await Task.sleep(for: .milliseconds(500))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Stands in for the tilt in previews, which have none.
///
/// Sweeps from the ground up past the overhead and back down, so a preview walks the chip through
/// every one of the five bands rather than parking on whichever one a fixed angle happens to hit.
/// `silent` is the other half of the surface: a device with no device-motion support, which is every
/// simulator.
struct PreviewGazeProvider: GazeProvider {
  var silent = false

  func gazeStream() -> AsyncStream<Double> {
    AsyncStream { continuation in
      guard !silent else {
        continuation.finish()
        return
      }
      let task = Task {
        var elevation = -70.0
        var step = 9.0
        while !Task.isCancelled {
          continuation.yield(elevation)
          if elevation >= 80 || elevation <= -70 { step = -step }
          elevation += step
          try await Task.sleep(for: .milliseconds(500))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Stands in for the scripted detector in previews, at the same thirty-times speed
/// ``PreviewAudioSource`` runs at — so the robin still lands around eight seconds of *session*
/// time, where the real script puts it.
nonisolated struct PreviewDetector: SessionDetector {
  func findingStream() -> AsyncThrowingStream<SessionFinding, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        try await Task.sleep(for: .milliseconds(240))
        continuation.yield(.bird(speciesId: "american-robin", commonName: "American Robin", confidence: 0.87))
        try await Task.sleep(for: .milliseconds(210))
        continuation.yield(.speech(text: "It's green with a yellow belly"))
        try await Task.sleep(for: .milliseconds(90))
        continuation.yield(.bird(speciesId: "green-jay", commonName: "Green Jay", confidence: 0.91))
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Stands in for the Demo Director in previews: nothing armed, so the honesty line reads
/// "No demo preset armed", every photo goes unanswered, and no question list is offered.
nonisolated struct PreviewDemoDirector: DemoDirector {
  var armed: DemoPreset? { nil }
  func findingStream() -> AsyncThrowingStream<SessionFinding, Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func response(toPhotoAt index: Int) -> DemoPhotoResponse? { nil }
  func answer(to transcript: String) -> DemoQuestion? { nil }
}

/// Stands in for the journal in previews: it accepts a save and forgets it, which is all a
/// review screen being looked at needs.
nonisolated struct PreviewJournal: JournalRepository {
  func journalStream() -> AsyncThrowingStream<[OutingWithChildren], Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func lifeListCountStream() -> AsyncThrowingStream<Int, Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func findById(_ outingId: String) async throws -> OutingWithChildren? { nil }
  func saveOuting(_ draft: OutingDraft) async throws -> String { "preview-outing" }
  func updateNotes(outingId: String, notes: String?) async throws {}
  func delete(outingId: String) async throws {}
  func deleteAll() async throws {}
}

/// Stands in for the glasses in previews, which have none: never registered, no pair
/// listed, every stream quiet. The pill stays a label and Settings shows the set-up card.
nonisolated struct PreviewGlassesSession: GlassesSessionRepository {
  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { continuation in
      continuation.yield(.available)
      continuation.finish()
    }
  }

  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) { continuation in
      continuation.yield(nil as GlassesDeviceInfo?)
      continuation.finish()
    }
  }

  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish(throwing: GlassesError.notConnected)
    }
  }

  func access(_ permission: GlassesPermission) async -> GlassesAccess { .unknown }
}

/// The camera half of ``PreviewGlassesSession`` — a shutter with nothing behind it.
nonisolated struct PreviewGlassesCamera: GlassesCameraRepository {
  let honoursCaptureSettings = true

  func capturePhoto(
    format: PhotoFormat,
    resolution: CaptureResolution,
    quality: CaptureQuality
  ) async throws -> CapturedPhoto {
    throw GlassesError.notConnected
  }
}

/// The buttons half of ``PreviewGlassesSession`` — a pair of glasses nobody is pressing. The
/// stream stays open rather than finishing, which is what a real one does between presses.
nonisolated struct PreviewGlassesInput: GlassesInputRepository {
  func inputEventStream() -> AsyncStream<GlassesInputEvent> {
    AsyncStream { _ in }
  }
}

/// The speech half of ``PreviewGlassesSession`` — a recogniser that never hears anything, which
/// is the honest reading for a preview with no glasses on a face.
nonisolated struct PreviewGlassesSpeech: GlassesSpeechRepository {
  func transcriptionStream() -> AsyncStream<Transcription> {
    AsyncStream { _ in }
  }

  func speechStateStream() -> AsyncStream<GlassesSpeechState> {
    AsyncStream { continuation in
      continuation.yield(.idle)
      continuation.finish()
    }
  }
}

/// The display half of ``PreviewGlassesSession`` — a wall every gallery lands on quietly.
nonisolated struct PreviewGlassesDisplay: GlassesDisplayRepository {
  func showGallery(for bird: SpeciesWithMedia, message: String?) async {}
  func clear() async {}
}

/// A voice with nowhere to speak, which is what every preview has: the lines are taken and
/// nothing is said, and ``isSpeaking`` stays false so the strip keeps drawing.
nonisolated struct PreviewSpokenOutput: SpokenOutput {
  var isSpeaking: Bool { false }
  func speak(_ words: String) async {}
  func silence() {}
}

extension PreviewCatalog {

  /// A flat frame, so previews can show the chrome over a picture. Field green, because the
  /// point of the preview is the chrome's contrast against something a camera might see.
  static let viewfinderFrame: PreviewFrame? = {
    guard
      let context = CGContext(
        data: nil,
        width: 9,
        height: 16,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.setFillColor(red: 0.24, green: 0.29, blue: 0.24, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 9, height: 16))
    return context.makeImage().map { PreviewFrame(image: $0) }
  }()
}
