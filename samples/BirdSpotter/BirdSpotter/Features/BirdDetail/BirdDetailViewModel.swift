/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdDetailViewModel.swift
//  birdspotter
//

import Foundation

/// What the bird detail screen renders.
///
/// `notFound` is not an error state. ``BirdCatalogRepository/findById(_:)`` answers nil for
/// an id the catalog does not have, which is exactly what an address outlives when a seed
/// drops a species — or what a hand-typed deep link looks like. The screen says so plainly
/// rather than spinning forever.
nonisolated enum BirdDetailUiState: Equatable {
  case loading
  case ready(SpeciesWithMedia)
  case notFound
}

/// The bird page's transport state — what the play button and the sonogram's playhead read.
///
/// Held apart from ``BirdDetailUiState`` because it changes many times a second while the clip
/// plays, where the page's content changes once; folding the two together would rebuild the whole
/// page on every tick.
nonisolated struct Playback: Equatable {
  var isPlaying = false
  /// How far through the reference clip, `0...1`.
  var progress: Double = 0
}

/// The bird page's state holder.
///
/// Takes the slug rather than a `SpeciesWithMedia` so the screen is reachable by address
/// alone: every tab pushes `Route.birdDetail(speciesId:)`, and none of them has to be
/// holding the row already.
@MainActor
@Observable
final class BirdDetailViewModel {

  private(set) var uiState: BirdDetailUiState = .loading
  private(set) var playback = Playback()

  private let speciesId: String
  private let birdCatalog: any BirdCatalogRepository
  private let player: any AudioClipPlayer

  /// Samples ``AudioClipPlayer/progress`` at the screen's cadence while a clip plays. The
  /// player holds the true position; this decides how often the playhead moves.
  private var tickerTask: Task<Void, Never>?

  /// ~30 Hz — smooth enough for a playhead sweeping a ten-second clip, cheap enough to run
  /// on the main actor.
  private static let tickInterval: Duration = .milliseconds(33)

  init(
    speciesId: String,
    birdCatalog: any BirdCatalogRepository,
    player: any AudioClipPlayer = SystemAudioClipPlayer()
  ) {
    self.speciesId = speciesId
    self.birdCatalog = birdCatalog
    self.player = player
    player.onFinish = { [weak self] in self?.finishPlayback() }
  }

  /// The clip the play button plays — the primary song or call, once the page is ready.
  var referenceAudio: SpeciesMedia? {
    if case .ready(let bird) = uiState { bird.referenceAudio } else { nil }
  }

  /// The spectrogram drawn under the transport, where the guide bundled one.
  var sonogram: SpeciesMedia? {
    if case .ready(let bird) = uiState { bird.sonogram } else { nil }
  }

  /// Driven by `.task` on the view, so the load starts when the screen appears and is
  /// cancelled with it.
  func load() async {
    do {
      let bird = try await birdCatalog.findById(speciesId)
      uiState = bird.map(BirdDetailUiState.ready) ?? .notFound
    } catch is CancellationError {
      // The screen went away mid-query. Leaving the state alone means coming back
      // shows the placeholder again rather than a stale "not in the guide".
    } catch {
      uiState = .notFound
    }
  }

  /// Play the reference clip, or pause it if it is already playing. A page with no bundled
  /// vocalization has no play button, so this is a no-op there.
  func togglePlayback() {
    guard let audio = referenceAudio else { return }
    if playback.isPlaying {
      player.pause()
      playback.isPlaying = false // hold position; toggling again resumes it
    } else {
      player.play(audio)
      playback.isPlaying = true
      startTicker()
    }
  }

  /// Move the play position to `progress` (`0...1`) — the sonogram's scrub. Works whether the
  /// clip is playing, paused, or has never started: when it plays on, the ticker carries the
  /// playhead from the new spot; when it does not, the spot waits there for the next play.
  func seek(to progress: Double) {
    guard let audio = referenceAudio else { return }
    let clamped = min(max(progress, 0), 1)
    player.seek(audio, to: clamped)
    playback.progress = clamped
  }

  /// Silences the clip and resets the transport — called when the screen goes away, so a
  /// call does not keep playing over the page the user moved on to.
  func stopPlayback() {
    player.stop()
    tickerTask?.cancel()
    tickerTask = nil
    playback = Playback()
  }

  /// The clip reached its own end: rewind the transport so the play button offers it again
  /// from the top rather than sitting spent at the finish line.
  private func finishPlayback() {
    tickerTask?.cancel()
    tickerTask = nil
    playback = Playback()
  }

  private func startTicker() {
    tickerTask?.cancel()
    tickerTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, self.player.isPlaying else { break }
        self.playback.progress = self.player.progress
        try? await Task.sleep(for: Self.tickInterval)
      }
    }
  }
}
