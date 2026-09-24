/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemAudioClipPlayer.swift
//  birdspotter
//

import AVFoundation
import Foundation

/// The ``AudioClipPlayer`` the app ships: `AVAudioPlayer` over a file the ``CatalogAssetStore``
/// resolves from the bundle.
///
/// The mirror is ``AudioClipPlayer``, not this class — the engine and the audio session are exactly
/// the platform plumbing the architecture note keeps idiomatic. The one behaviour both encapsulate:
/// `play` after a clip has finished replays it from the top (here by rewinding `currentTime`;
/// `MediaPlayer.start()` rewinds itself), so the play button means the same thing on both sides.
@MainActor
final class SystemAudioClipPlayer: NSObject, AudioClipPlayer {

  var onFinish: (() -> Void)?

  var isPlaying: Bool { player?.isPlaying ?? false }

  var progress: Double {
    guard let player, player.duration > 0 else { return 0 }
    return min(max(player.currentTime / player.duration, 0), 1)
  }

  private let assets: CatalogAssetStore
  private var player: AVAudioPlayer?
  /// Which clip `player` holds, so ``play(_:)`` can tell "resume this" from "load that".
  private var loadedMediaId: String?

  /// `nonisolated` so it can be a default argument on `BirdDetailViewModel.init` and be
  /// built in a SwiftUI `View.init` — both of which evaluate their default expressions
  /// outside the main actor. Only the immutable `assets` is stored here; every member that
  /// touches the engine stays main-actor isolated.
  nonisolated init(assets: CatalogAssetStore = CatalogAssetStore()) {
    self.assets = assets
    super.init()
  }

  func play(_ media: SpeciesMedia) {
    // `ensureLoaded` hands back the clip already loaded — at wherever pause or a scrub left
    // it, or 0 after it finished — or a fresh one cued to the top.
    ensureLoaded(media)?.play()
  }

  func seek(_ media: SpeciesMedia, to progress: Double) {
    guard let engine = ensureLoaded(media) else { return }
    engine.currentTime = min(max(progress, 0), 1) * engine.duration
  }

  /// The player for `media`: the one already loaded, keeping its position, or a freshly
  /// loaded and prepared one cued to the top. Never starts playback — the caller decides,
  /// so a scrub can position a clip that then waits, paused, for the play button.
  private func ensureLoaded(_ media: SpeciesMedia) -> AVAudioPlayer? {
    if let player, loadedMediaId == media.id { return player }

    guard let url = assets.url(for: media) else { return nil }

    // A bird page has one voice and this app only ever plays it back — never records —
    // so it sets the playback category once, which also makes the call audible on a
    // phone switched to silent, the way a field guide's play button is expected to be.
    try? AVAudioSession.sharedInstance().setCategory(.playback)
    try? AVAudioSession.sharedInstance().setActive(true)

    guard let engine = try? AVAudioPlayer(contentsOf: url) else { return nil }
    engine.delegate = self
    engine.prepareToPlay()
    player = engine
    loadedMediaId = media.id
    return engine
  }

  func pause() {
    player?.pause()
  }

  func stop() {
    player?.stop()
    player = nil
    loadedMediaId = nil
  }
}

extension SystemAudioClipPlayer: AVAudioPlayerDelegate {
  /// Called by AVFoundation off the main actor. Rewinds so the next `play` starts the clip
  /// over rather than resuming at its end, then hands back to the view model on the main
  /// actor. A user-driven `stop()` never routes through here — AVAudioPlayer does not call
  /// this for a manual stop — so `onFinish` stays a natural-end signal.
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      self.player?.currentTime = 0
      self.onFinish?()
    }
  }
}
