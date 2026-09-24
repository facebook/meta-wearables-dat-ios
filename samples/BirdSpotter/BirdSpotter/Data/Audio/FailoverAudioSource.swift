/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FailoverAudioSource.swift
//  birdspotter
//

import Foundation

/// One microphone stream over two real ones, so a session can change its ears without changing
/// its spine.
///
/// **The screen must not learn that failover exists.** This keeps the contract the session was
/// built on — 16 kHz mono, cold, continuous for as long as anyone iterates it — while the
/// actual microphone underneath comes and goes.
///
/// It cannot, though, keep ``kind``. That is a constant on ``AudioCaptureSource`` — *this is the
/// phone microphone* — and a wrapper whose answer changes halfway through a session has no
/// honest value to put there, so it answers with the fallback it always falls back to. **Which
/// microphone is live moves onto the chunk**: ``AudioChunk/source`` carries it, and the pill
/// reads the latest one.
///
/// **The two transitions are asymmetric**, and building them as one thing gets the good half
/// wrong. Coming *back* to the glasses costs nothing, so it is only ever done on request. Losing
/// them costs what it costs — a disconnect is discovered rather than announced — so the phone is
/// reopened the moment the preferred stream fails, without asking anybody. *Never close a working
/// microphone on the promise of a better one; close it on the arrival of one.*
///
/// **Still one microphone at a time.** The ideal in the design doc has both microphones open
/// across the handover, with the phone cut only when the first glasses chunk lands. The glasses
/// now arrive on the camera stream rather than as a route on the phone's own audio session, so
/// the two *can* be open at once — but this class still swaps them, and the handover costs a beat
/// of silence until it learns to overlap them. It is the one place that changes when it does.
///
/// **A phone that will not open is waited for, not given up on.** The session's spine is this
/// stream, and a stream that fails ends the session — which is the wrong answer for the two
/// ways the phone's microphone ordinarily refuses: a session started with the phone locked in a
/// pocket (the platform will not open a recorder from there until the first unlock) and a phone
/// call taking the microphone mid-walk. Both come back on their own, so the stream stays open,
/// empty, and tries the phone again every ``fallbackRetryDelay`` — and the glasses, once asked
/// for, open the moment they are asked, because their microphone is not a recorder at all. The
/// one refusal that is final is the grant being gone.
nonisolated final class FailoverAudioSource: AudioCaptureSource, @unchecked Sendable {

  private let preferred: any AudioCaptureSource
  private let fallback: any AudioCaptureSource
  /// How long a phone that would not open waits before it is tried again — see the type's
  /// doc. Short enough that an unlock is heard within a breath, long enough that a phone
  /// refusing for a whole walk costs nothing worth measuring.
  private let fallbackRetryDelay: Duration

  private let lock = NSLock()
  private var wantsPreferred = false
  /// Wakes the running stream when the request changes. Nil while nobody is listening.
  private var onRequestChanged: (@Sendable () -> Void)?
  /// Where ``preferredLost()`` is fed from. Nil while nobody is listening.
  private var onPreferredLost: AsyncStream<Void>.Continuation?

  /// The fallback's, because that is the one this can always honour. What is actually live is
  /// on each ``AudioChunk``.
  var kind: CaptureSourceKind { fallback.kind }

  init(
    preferred: any AudioCaptureSource,
    fallback: any AudioCaptureSource,
    fallbackRetryDelay: Duration = .seconds(2)
  ) {
    self.preferred = preferred
    self.fallback = fallback
    self.fallbackRetryDelay = fallbackRetryDelay
  }

  /// Says when the preferred microphone was asked for and could not be had, so that whoever
  /// asked can stop waiting for it.
  ///
  /// **Falling back is silent to the stream on purpose, and that silence has to end somewhere.**
  /// The chunks go on arriving and the session never notices, which is the whole point of this
  /// class — but the screen above it asked a question, and *the answer is no* is not something
  /// it can read off a stream that looks exactly as it did before. Without this the request is
  /// outstanding forever: the pill promises a crossing that has already been abandoned.
  ///
  /// It fires on the losing, not on the state — a caller arriving afterwards has missed it,
  /// which is right for something the screen turns into a sentence about what just happened.
  /// One listener at a time, which is the one the run in flight owns.
  func preferredLost() -> AsyncStream<Void> {
    AsyncStream { continuation in
      lock.withLock { onPreferredLost = continuation }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.lock.withLock { self.onPreferredLost = nil }
      }
    }
  }

  /// Ask for the preferred microphone, or hand the session back to the fallback.
  ///
  /// A request, not a promise: the pill only claims the glasses once a chunk has actually come
  /// out of them. Safe to call when no stream is running — the answer is remembered for the
  /// next one.
  func usePreferred(_ wanted: Bool) {
    var changed = false
    let wake: (@Sendable () -> Void)? = lock.withLock {
      guard wantsPreferred != wanted else { return nil }
      wantsPreferred = wanted
      changed = true
      return onRequestChanged
    }
    if changed {
      BirdLog.info(.audio, "microphone requested — \(wanted ? "glasses" : "phone")")
    }
    wake?()
  }

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      let task = Task { [self] in
        defer { lock.withLock { onRequestChanged = nil } }

        while !Task.isCancelled {
          // **A fresh signal for every microphone opened, never one shared across
          // them.** The signal is a stream, and a stream whose reader is cancelled
          // is finished for good — which is exactly what happens to the reader
          // below when the microphone gives out and the group is torn down. One
          // signal shared across the loop was therefore already finished the moment
          // the glasses first failed, and every microphone opened after that
          // returned the instant it was asked for: a loop opening and closing the
          // phone tens of thousands of times a second, the audio queue buried under
          // it, and a session that never heard anything again.
          //
          // Armed *before* the request is read, so a change landing between the
          // read and the open still wakes this microphone rather than the next one.
          let (changes, changed) = AsyncStream.makeStream(of: Void.self)
          lock.withLock { onRequestChanged = { changed.yield(()) } }
          defer { changed.finish() }

          let wanted = lock.withLock { wantsPreferred }
          let source: any AudioCaptureSource = wanted ? preferred : fallback
          // **The line this whole category exists for.** "The session went quiet"
          // and "the session was listening to the wrong microphone the whole time"
          // are the same report from the far side of a room, and this is what
          // separates them afterwards.
          BirdLog.info(.audio, "microphone open — \(source.kind)")

          do {
            // Runs until the request changes underneath it, the microphone gives out,
            // or the whole stream is cancelled.
            try await pump(source, into: continuation, until: changes)
            if Task.isCancelled { break }
            // A clean end means the request changed: go round and open the other one.
            continue
          } catch {
            if Task.isCancelled { break }
            if wanted {
              // The glasses gave out. Discovered, not announced — take the phone
              // back immediately rather than leaving the session deaf.
              BirdLog.warning(
                .audio,
                "glasses microphone gave out — falling back to the phone",
              )
              BirdLog.debug(.audio, "the microphone's own error was \(error)")
              // Said before the phone reopens, so whoever asked for the glasses
              // hears the answer rather than watching chunks arrive and drawing
              // their own conclusion.
              let lost: AsyncStream<Void>.Continuation? = lock.withLock {
                wantsPreferred = false
                return onPreferredLost
              }
              lost?.yield()
              continue
            }
            // The one refusal nothing waits out: the grant is gone, and the
            // Identify gate is where that gets fixed.
            if let refusal = error as? AudioCaptureError, refusal == .accessDenied {
              BirdLog.error(.audio, "the phone microphone is not allowed — the session is deaf", error)
              continuation.finish(throwing: error)
              return
            }
            // Everything else the phone comes back from — see the type's doc. The
            // stream stays open and empty until it does, or until the glasses are
            // asked for, whichever is first.
            BirdLog.warning(.audio, "the phone microphone would not open — waiting to try again")
            BirdLog.debug(.audio, "the microphone's own error was \(error)")
            await waitForRequestChange(orAfter: fallbackRetryDelay)
            continue
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Sleeps until the request changes or `delay` passes, whichever is first — and returns at
  /// once on cancellation, which the loop above reads the moment it resumes.
  ///
  /// Armed with a signal of its own, for the reason the loop arms a fresh one per microphone:
  /// the signal the failed microphone was pumping against is finished for good.
  private func waitForRequestChange(orAfter delay: Duration) async {
    let (changes, changed) = AsyncStream.makeStream(of: Void.self)
    lock.withLock { onRequestChanged = { changed.yield(()) } }
    defer { changed.finish() }
    await withTaskGroup(of: Void.self) { group in
      group.addTask { for await _ in changes { return } }
      group.addTask { try? await Task.sleep(for: delay) }
      await group.next()
      group.cancelAll()
    }
  }

  /// Forwards one source's chunks until it ends, fails, or `changes` fires.
  ///
  /// Returns normally when the request changed; throws what the microphone threw.
  private func pump(
    _ source: any AudioCaptureSource,
    into continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation,
    until changes: AsyncStream<Void>
  ) async throws {
    try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        for try await chunk in source.audioStream() {
          // Stamped here rather than trusted from the source, so the one fact the pill
          // reads is the one this class actually chose.
          continuation.yield(
            AudioChunk(
              samples: chunk.samples,
              sampleRate: chunk.sampleRate,
              source: source.kind
            )
          )
        }
        return false
      }
      group.addTask {
        for await _ in changes { return true }
        return false
      }

      // Whichever finishes first decides; the other is cancelled with the group.
      _ = try await group.next()
      group.cancelAll()
    }
  }
}
