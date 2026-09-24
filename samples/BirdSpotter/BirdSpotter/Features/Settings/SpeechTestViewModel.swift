/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeechTestViewModel.swift
//  birdspotter
//

import Foundation

/// What the ASR test screen shows.
nonisolated struct SpeechTestUiState: Equatable, Sendable {
  /// Whether a session has been asked for and not yet hung up on.
  var isRunning: Bool = false

  /// Where the session is — `nil` before the first reading.
  var sessionState: GlassesSessionState?

  /// Where the recogniser is, which is the reading the screen exists for.
  var speechState: GlassesSpeechState = .idle

  /// The utterance in progress, or `nil` between them.
  var partial: String?

  /// Finished utterances, newest first.
  var heard: [Transcription] = []

  /// Why the run ended, when it ended badly.
  var failure: String?
}

extension SpeechTestUiState {
  /// One transcript folded into what is on screen: a partial replaces the line in progress, a
  /// final closes it and joins the list.
  ///
  /// **Both are kept, unlike anywhere else in the app.** A matcher downstream would read finals
  /// only — a partial containing an authored prompt would fire an answer mid-sentence — but the
  /// partial cadence is exactly what this screen is for: how fast they arrive, and how much of a
  /// sentence has to be said before the recogniser commits to it.
  ///
  /// A function of the state rather than a method on the view model, so the mirrored tests can
  /// pin the folding without a screen under it — the same seam
  /// ``RealtimeViewModel/deliver(answer:sessionKey:)`` keeps.
  func hearing(_ transcription: Transcription) -> SpeechTestUiState {
    var next = self
    if transcription.isFinal {
      next.partial = nil
      next.heard = Array(([transcription] + heard).prefix(heardLimit))
    } else {
      next.partial = transcription.text
    }
    return next
  }
}

/// How many finished utterances the screen keeps. A test run is read from the top and nobody
/// scrolls to the bottom of one; the log has every line either way.
private nonisolated let heardLimit = 50

/// A session opened for one purpose: to find out whether these glasses transcribe, and what they
/// hear when they do.
///
/// **A diagnostic, not a feature.** Nothing here identifies a bird, matches a preset or records
/// anything — it starts a session, attaches nothing of its own, and prints what the recogniser
/// sends. The three questions it answers are the three that only hardware can:
///
/// 1. does the speech capability attach on this pair at all — `unavailable` says no;
/// 2. does it reach `listening`, and how long after the session does;
/// 3. what the transcripts actually look like — partial cadence, punctuation, casing, confidence —
///    which is what a matcher downstream has to be written against.
///
/// The session comes up the ordinary way, through ``GlassesSessionRepository/sessionStream()``:
/// the recogniser rides a running session, so there is no shorter path to one, and running the
/// ordinary path is also what makes a failure here mean something about the app people will
/// actually use.
@MainActor
@Observable
final class SpeechTestViewModel {

  private let glassesSession: any GlassesSessionRepository
  private let glassesSpeech: any GlassesSpeechRepository

  private(set) var uiState = SpeechTestUiState()

  /// The run: the session's lease, and the two subscriptions that live inside it.
  private var run: Task<Void, Never>?

  init(
    glassesSession: any GlassesSessionRepository,
    glassesSpeech: any GlassesSpeechRepository
  ) {
    self.glassesSession = glassesSession
    self.glassesSpeech = glassesSpeech
  }

  /// Opens a session and starts printing. Idempotent — a second tap on a running test is a tap
  /// nobody meant, and restarting the link underneath one would look like the very instability
  /// this screen is here to rule out.
  func start() {
    guard run == nil else { return }
    uiState = SpeechTestUiState(isRunning: true)
    run = Task { [weak self] in
      await self?.listen()
      self?.run = nil
    }
  }

  /// Hangs up. The readings stay on screen: the run that just ended is the thing being read, and
  /// clearing it at the moment somebody stops to look at it would be the wrong instinct.
  func stop() {
    run?.cancel()
    run = nil
    uiState.isRunning = false
  }

  /// The run itself: the session held open, and the recogniser read for as long as it is.
  ///
  /// The two subscriptions are children of the same group as the session's own, so hanging up
  /// takes them with it — the same lease every other consumer of these streams holds.
  private func listen() async {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { [glassesSpeech] in
          for await state in glassesSpeech.speechStateStream() {
            await MainActor.run { self.uiState.speechState = state }
          }
        }
        group.addTask { [glassesSpeech] in
          for await heard in glassesSpeech.transcriptionStream() {
            await MainActor.run { self.uiState = self.uiState.hearing(heard) }
          }
        }
        group.addTask { [glassesSession] in
          for try await state in glassesSession.sessionStream() {
            await MainActor.run { self.uiState.sessionState = state }
          }
        }
        // The session is the run: when it ends, so does the test, and the two readers
        // above it have nothing left to read.
        try await group.next()
        group.cancelAll()
      }
      // A session that ends of its own accord — a doff, a fold, a long press — is not a
      // failure, and the switch should go back to offering another run.
      uiState.isRunning = false
    } catch is CancellationError {
      return
    } catch {
      BirdLog.error(.glasses, "ASR test — the session ended in failure", error)
      uiState.isRunning = false
      uiState.failure = Self.parting(for: error)
    }
  }

  /// Why the run ended, in a line. The same two answers the realtime screen gives, because they
  /// are the only two the app can tell apart — and the log line beside this one carries the rest.
  private static func parting(for error: Error) -> String {
    if case GlassesError.glassesUpdateRequired = error {
      return "Your glasses need a firmware update — check them in the Meta AI app"
    }
    return "The glasses session ended — check they are connected and try again"
  }
}
