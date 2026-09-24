/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingDetailViewModel.swift
//  birdspotter
//

import Foundation

/// One moment of a saved outing's timeline, ready to render — the live log's row shapes,
/// rebuilt from the rows the journal kept.
///
/// Three kinds rather than the event table's three types: `WIZARD_ANSWER` events are
/// provenance and stay in the field notes, and a photo nothing pointed at earns a row of its
/// own — the watcher pressed the shutter, and the timeline records what happened.
nonisolated enum TimelineRow: Identifiable, Equatable, Sendable {

  /// A detection — what the app offered, confirmed into the life list or not.
  case detection(
    id: String,
    offsetMs: Int64?,
    commonName: String?,
    confidence: Double?,
    isConfirmed: Bool,
    photo: OutingMedia?
  )

  /// One Q&A exchange — the watcher asked, the app answered.
  case exchange(id: String, offsetMs: Int64?, question: String, answer: String)

  /// A photo no detection claimed. Still a moment; still on the clock.
  case photo(id: String, offsetMs: Int64?, media: OutingMedia)

  var id: String {
    switch self {
    case let .detection(id, _, _, _, _, _): id
    case let .exchange(id, _, _, _): id
    case let .photo(id, _, _): id
    }
  }

  /// Where this sits on the outing's clock — and where a tap seeks to. Nil when clockless.
  var offsetMs: Int64? {
    switch self {
    case let .detection(_, offsetMs, _, _, _, _): offsetMs
    case let .exchange(_, offsetMs, _, _): offsetMs
    case let .photo(_, offsetMs, _): offsetMs
    }
  }
}

/// The recording, ready to play: the whole outing's sonogram, and where the playhead is on
/// it. Published beside the page state rather than inside it, the way the bird page keeps
/// its clip transport beside the bird — the entry does not change thirty times a second.
struct OutingPlaybackUiState {
  /// The full session's strip, built once from the saved segments. Gaps stay dark.
  let sonogram: SonogramBuffer
  let totalMs: Int64
  var positionMs: Int64 = 0
  var isPlaying: Bool = false
}

/// What the journal-entry detail screen renders.
///
/// `notFound` is not an error: an outing can be deleted from under an open address, or a
/// stale link can name one that never existed. The screen says so plainly rather than
/// spinning.
nonisolated enum OutingDetailUiState: Equatable {
  case loading
  case notFound
  case loaded(JournalEntry, timeline: [TimelineRow])
}

/// The journal entry page's state holder.
///
/// Takes the outing id rather than the row, so the page is reachable by address alone —
/// `Route.outingDetail(outingId:)` — the same way ``BirdDetailViewModel`` takes a slug.
/// Reads the outing from the Journal store and resolves its confirmed birds against the
/// catalog, producing the same ``JournalEntry`` the list is built from.
///
/// A `LIVE` entry also gets its recording back: the audio segments are decoded off the main
/// actor into one ``OutingPlayback`` — the edit decision list, gaps and all — and the same
/// samples are run through the same ``SonogramAnalyzer`` the session drew with, so the strip
/// here is the strip the watcher saw, recomputed rather than stored. Playback
/// position is sampled on a ticker while playing, the way the bird page samples its clip.
@MainActor
@Observable
final class OutingDetailViewModel {

  private(set) var uiState: OutingDetailUiState = .loading

  /// Nil until the recording is decoded — and forever, for an outing that has none.
  private(set) var playback: OutingPlaybackUiState?

  private let outingId: String
  private let journal: any JournalRepository
  private let birdCatalog: any BirdCatalogRepository
  private let mediaFileStore: MediaFileStore
  private let player: any OutingAudioPlayer

  /// Samples ``OutingAudioPlayer/positionMs`` at the strip's cadence while playing.
  private var ticker: Task<Void, Never>?

  init(
    outingId: String,
    journal: any JournalRepository,
    birdCatalog: any BirdCatalogRepository,
    mediaFileStore: MediaFileStore,
    player: any OutingAudioPlayer
  ) {
    self.outingId = outingId
    self.journal = journal
    self.birdCatalog = birdCatalog
    self.mediaFileStore = mediaFileStore
    self.player = player
  }

  /// Driven by `.task` on the view, so the load starts when the screen appears and is
  /// cancelled with it.
  func load() async {
    do {
      guard let withChildren = try await journal.findById(outingId) else {
        uiState = .notFound
        return
      }
      var birds: [ConfirmedBird] = []
      for sighting in JournalEntry.storyOrder(withChildren) {
        let species = (try? await birdCatalog.findById(sighting.speciesId)) ?? nil
        birds.append(ConfirmedBird(sighting: sighting, species: species))
      }
      uiState = .loaded(
        JournalEntry(withChildren: withChildren, birds: birds),
        timeline: await timeline(withChildren)
      )
      await prepareRecording(withChildren)
    } catch is CancellationError {
      // Left as-is, so returning to the screen shows the placeholder rather than a
      // stale "not found".
    } catch {
      uiState = .notFound
    }
  }

  /// The outing's moments, oldest first — the order the walk happened in, which is the
  /// order a reader replays it. Stable within a stamp, so two moments the same second
  /// keep their written order.
  private func timeline(_ withChildren: OutingWithChildren) async -> [TimelineRow] {
    let confirmedEvents = Set(withChildren.sightings.compactMap(\.sourceEventId))
    let claimedPhotos = Set(withChildren.events.compactMap(\.mediaId))

    var rows: [TimelineRow] = []
    for event in withChildren.events {
      switch event.type {
      case .detection:
        var commonName: String?
        if let speciesId = event.speciesId {
          commonName =
            ((try? await birdCatalog.findById(speciesId)) ?? nil)?
            .species.commonName
        }
        rows.append(
          .detection(
            id: event.id,
            offsetMs: withChildren.offset(of: event),
            commonName: commonName,
            confidence: event.confidence,
            isConfirmed: confirmedEvents.contains(event.id),
            photo: withChildren.media(for: event)
          )
        )

      case .qa:
        guard let question = event.question, let answer = event.answer else { break }
        rows.append(
          .exchange(
            id: event.id,
            offsetMs: withChildren.offset(of: event),
            question: question,
            answer: answer
          )
        )

      // Provenance, not a moment — the field notes already read the wizard's answers.
      case .wizardAnswer:
        break
      }
    }
    for photo in withChildren.photos where !claimedPhotos.contains(photo.id) {
      rows.append(.photo(id: photo.id, offsetMs: photo.offsetMs, media: photo))
    }
    return rows.sorted { ($0.offsetMs ?? .max) < ($1.offsetMs ?? .max) }
  }

  /// Decodes the saved segments and hands the page its recording — off the main actor,
  /// because a walk's worth of WAV and FFT belongs nowhere near a frame.
  ///
  /// A segment whose file is gone drops out silently: a row pointing at a missing file is
  /// the recoverable case the delete ordering was designed around, and the rest of the
  /// recording is still worth playing.
  ///
  /// **The strip is read back rather than measured, when Save left one.** Every one of its
  /// columns was computed already, as the audio arrived during the session; the sidecar is
  /// that work kept instead of thrown away. The analyzer still runs for an outing saved
  /// before the sidecar existed, or one whose sidecar no longer reads — which is why the
  /// fallback is a second stage rather than a branch inside the first.
  private func prepareRecording(_ withChildren: OutingWithChildren) async {
    let audioRows = withChildren.audio
    guard !audioRows.isEmpty else { return }

    let store = mediaFileStore
    let sonogramPath = MediaFileStore.sonogramPath(outingId: outingId)
    let outingDurationMs = withChildren.outing.durationMs ?? 0

    // Stage one, off the main actor: the disk. The audio the transport plays, and the
    // strip as Save left it — whether those bytes are usable is decided back on the main
    // actor, where `SonogramBuffer` lives.
    let loaded: (playback: OutingPlayback, segments: [PlaybackSegment], sonogram: Data?)? =
      await Task.detached(priority: .userInitiated) {
        let segments: [PlaybackSegment] = audioRows.compactMap { row in
          guard let bytes = try? Data(contentsOf: store.resolve(row.filePath)),
            let samples = try? WavCodec.decode(bytes)
          else { return nil }
          return PlaybackSegment(offsetMs: row.offsetMs ?? 0, samples: samples)
        }
        guard !segments.isEmpty else { return nil }
        return (
          OutingPlayback(segments: segments, totalMs: outingDurationMs),
          segments,
          try? Data(contentsOf: store.resolve(sonogramPath))
        )
      }.value

    guard let loaded else { return }

    // Stage two: the strip. Reading one back is a byte copy and belongs here beside the
    // buffer; measuring one is the walk's entire FFT and very much does not.
    let sonogram: SonogramBuffer
    // `oldest > 0` means the live ring had already overwritten the start of the walk before
    // Save read it — a session longer than ``sonogramCapacity``. The journal wants the whole
    // outing, so a strip missing its opening is recomputed rather than drawn short.
    if let stored = loaded.sonogram.flatMap({ SonogramBuffer.decoded(from: $0) }),
      stored.oldest == 0
    {
      sonogram = stored
    } else {
      let segments = loaded.segments
      sonogram = sonogramOf(
        await Task.detached(priority: .userInitiated) { Self.analyzed(segments) }.value
      )
    }

    player.load(loaded.playback)
    player.onFinish = { [weak self] in
      // Played out: transport returns to the top, ready to play again.
      self?.player.seek(toMs: 0)
      self?.playback?.isPlaying = false
      self?.playback?.positionMs = 0
    }
    playback = OutingPlaybackUiState(
      sonogram: sonogram,
      totalMs: loaded.playback.totalMs
    )
  }

  /// Every segment through the analyzer — what a walk with no readable sidecar costs.
  ///
  /// `nonisolated` so it can run off the main actor: it touches nothing but its argument,
  /// which is exactly what lets the FFT stay away from the frame.
  private nonisolated static func analyzed(
    _ segments: [PlaybackSegment]
  ) -> [(offsetMs: Int64, columns: [SonogramColumn])] {
    let analyzer = SonogramAnalyzer()
    return
      segments
      .sorted { $0.offsetMs < $1.offsetMs }
      .map { segment in
        // A fresh start per segment: the next one begins on its own clock reading,
        // not on the last one's leftover samples.
        analyzer.reset()
        return (
          offsetMs: segment.offsetMs,
          columns: analyzer.analyze(AudioChunk(samples: segment.samples))
        )
      }
  }

  /// The whole outing's strip, from the same analyzer the session drew with. Sized to the
  /// outing rather than the live ring's ten minutes — the journal wants all of it, and a
  /// byte per bin keeps even a long walk under a few megabytes.
  private func sonogramOf(_ strips: [(offsetMs: Int64, columns: [SonogramColumn])]) -> SonogramBuffer {
    let lastColumn =
      strips
      .map { Int(Double($0.offsetMs) / 1000.0 * sonogramColumnsPerSecond) + $0.columns.count }
      .max() ?? 0
    let buffer = SonogramBuffer(capacity: lastColumn + 1)

    for strip in strips {
      // Each segment starts on its own clock reading; the distance from the last
      // one's end stays dark, which is what a gap in the audio looks like.
      buffer.advance(to: Int(Double(strip.offsetMs) / 1000.0 * sonogramColumnsPerSecond))
      for column in strip.columns { buffer.append(column) }
    }
    return buffer
  }

  // ── Transport ──────────────────────────────────────────────────────────

  /// Play from here — or from the top, when the playhead is at the end — or hold.
  func togglePlayback() {
    guard let state = playback else { return }
    if state.isPlaying {
      player.pause()
      playback?.isPlaying = false
      playback?.positionMs = player.positionMs
      ticker?.cancel()
    } else {
      if state.positionMs >= state.totalMs {
        player.seek(toMs: 0)
        playback?.positionMs = 0
      }
      resume()
    }
  }

  /// The playhead under a moving finger. The engine goes quiet for the length of the
  /// scrub — seeking stops a streamed transport (see ``OutingAudioPlayer/seek(toMs:)``) —
  /// but the transport's *intent* is left alone, so a recording that was playing is still
  /// playing as far as the page is concerned, and ``seek(toMs:)`` picks it back up when the
  /// finger lets go.
  func scrub(toMs: Int64) {
    move(toMs: toMs)
  }

  /// Settles the playhead: the strip's tap, the end of a scrub, and a tapped row's landing.
  /// A recording that was playing carries straight on from the new position — moving the
  /// playhead is not asking the recording to stop.
  func seek(toMs: Int64) {
    let wasPlaying = playback?.isPlaying ?? false
    move(toMs: toMs)
    if wasPlaying { resume() }
  }

  /// A tap on a timeline row: the playhead goes to its moment. Clockless rows stay put.
  func seekTo(_ row: TimelineRow) {
    if let offsetMs = row.offsetMs { seek(toMs: offsetMs) }
  }

  /// What a scrub and a seek share: the playhead moves, and the ticker stops — position is
  /// the finger's to say until the transport is rolling again.
  private func move(toMs: Int64) {
    guard let state = playback else { return }
    let clamped = min(max(toMs, 0), state.totalMs)
    player.seek(toMs: clamped)
    ticker?.cancel()
    playback?.positionMs = clamped
  }

  /// Rolls from wherever the playhead is.
  private func resume() {
    guard let state = playback else { return }
    guard state.positionMs < state.totalMs else {
      // Scrubbed to the very end: there is nothing left to play, so the transport reads
      // stopped rather than showing a pause button over silence. The play button is
      // what returns it to the top.
      playback?.isPlaying = false
      return
    }
    player.play()
    playback?.isPlaying = true
    startTicker()
  }

  private func startTicker() {
    ticker?.cancel()
    ticker = Task { [weak self] in
      while !Task.isCancelled, let self, self.player.isPlaying {
        self.playback?.positionMs = self.player.positionMs
        try? await Task.sleep(for: timelineTick)
      }
    }
  }

  /// Lets the engine go with the screen — the player is this page's, not the app's.
  func releasePlayer() {
    ticker?.cancel()
    player.release()
  }

  /// Deletes the outing — its files first, then the rows, per ``JournalRepository`` —
  /// and reports whether it succeeded, so the screen pops on success.
  func delete() async -> Bool {
    do {
      try await journal.delete(outingId: outingId)
      return true
    } catch {
      return false
    }
  }
}
