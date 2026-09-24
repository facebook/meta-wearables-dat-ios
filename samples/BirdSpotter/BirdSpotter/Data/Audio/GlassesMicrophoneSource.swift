/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesMicrophoneSource.swift
//  birdspotter
//

import Foundation

/// The glasses' microphone as an ``AudioCaptureSource``.
///
/// **It rides the camera stream.** DAT carries the glasses' microphone as audio on the same
/// stream that wakes the camera, so there is no audio route to select and no audio session to
/// share: the samples arrive from the SDK already the glasses', at the 16 kHz mono the stream was
/// asked for, and ``DatGlassesSessionRepository`` turns them into ``AudioChunk``s. This class is
/// the lease on that feed and nothing more.
///
/// The consequence the platform's own audio stack used to hide is that **the phone and the
/// glasses are now two independent microphones.** Opening one no longer closes the other, and a
/// line spoken while the glasses listen goes out over the media profile at full bandwidth.
///
/// Fails with ``AudioCaptureError/unavailable`` when there is nothing to hear — no session, a
/// session opened without Meta AI's microphone grant, or a stream that never delivers a first
/// buffer inside ``firstChunkPatience`` — which is the signal ``FailoverAudioSource`` needs to keep
/// the phone.
nonisolated final class GlassesMicrophoneSource: AudioCaptureSource {

  let kind = CaptureSourceKind.glasses

  private let link: DatGlassesSessionRepository

  init(link: DatGlassesSessionRepository) {
    self.link = link
  }

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      let heard = HeardFlag()
      let task = Task { [link] in
        // **A stream that never speaks is not a microphone.** A session can be up with
        // audio on its configuration and still hand over nothing — the grant read one way
        // and the glasses another — and from up here that is indistinguishable from a
        // quiet room. The failover only moves on a failure, so the silence is made into
        // one.
        let watchdog = Task {
          try? await Task.sleep(for: firstChunkPatience)
          guard !Task.isCancelled, !heard.isSet else { return }
          BirdLog.warning(.audio, "the glasses' microphone never delivered a first buffer")
          continuation.finish(throwing: AudioCaptureError.unavailable)
        }
        defer { watchdog.cancel() }
        do {
          for try await chunk in link.audioChunksFromActiveSession() {
            heard.set()
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// How long a freshly opened glasses stream gets to deliver its first buffer before it is given
/// up on — see ``GlassesMicrophoneSource``. Generous, because giving up too early is a pair of
/// glasses that looks like it has no microphone, and waiting too long only delays a fallback the
/// phone is ready for.
private nonisolated let firstChunkPatience = Duration.seconds(5)

/// Whether a stream has delivered anything yet, readable from the watchdog while the reader
/// writes it.
private nonisolated final class HeardFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isSet: Bool { lock.withLock { value } }

  func set() { lock.withLock { value = true } }
}
