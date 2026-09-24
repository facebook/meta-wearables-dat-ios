/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  AudioClipPlayer.swift
//  birdspotter
//

import Foundation

/// Plays one bundled catalog vocalization at a time — the surface the bird page's play
/// button drives.
///
/// A player, not a repository: it holds transport (a clip is loaded, playing, or paused)
/// rather than answering queries, so it sits beside the catalog it plays from. The protocol is
/// the mirrored surface; the engine behind it — `AVAudioPlayer` — is audio-session plumbing the
/// architecture note keeps idiomatic.
///
/// Progress is a value the caller samples, not a stream. A play button wants the position at
/// the screen's own cadence, so ``BirdDetailViewModel`` reads ``progress`` on a ticker while
/// ``isPlaying`` rather than the player pushing a value every frame — which keeps the surface
/// a plain getter on both platforms instead of an `AsyncStream` on one and a `Flow` on the
/// other for a thing neither app needs to buffer.
@MainActor
protocol AudioClipPlayer: AnyObject {
  /// True between ``play(_:)`` and the clip ending, being paused, or being stopped.
  var isPlaying: Bool { get }

  /// How far through the loaded clip, `0...1`. Zero when nothing is loaded.
  var progress: Double { get }

  /// Called on the main actor when the clip reaches its end on its own — never for
  /// ``pause()`` or ``stop()``. The view model returns its transport to the start here.
  var onFinish: (() -> Void)? { get set }

  /// Plays `media`. Resumes from position when this same clip is loaded and paused; loads
  /// and starts from the top otherwise. A missing or unreadable asset is a no-op — a
  /// dropped recording leaves the card silent, the way a dropped photo leaves it without an
  /// image, rather than taking the screen down.
  func play(_ media: SpeciesMedia)

  /// Moves the play position to `progress` (`0...1`) of `media` — the sonogram's scrub. Loads
  /// and prepares the clip if it is not the one already loaded, so a scrub before the first
  /// play leaves the clip cued there for ``play(_:)`` to start from. Leaves the engine
  /// playing if it was playing and paused if it was paused.
  func seek(_ media: SpeciesMedia, to progress: Double)

  /// Holds position. ``play(_:)`` with the same clip resumes from here.
  func pause()

  /// Stops and unloads, returning ``progress`` to zero.
  func stop()
}
