/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesSpeechRepository.swift
//  birdspotter
//

import Foundation

/// Something the wearer said, as the glasses' own recogniser heard it.
///
/// **Text and nothing else crosses the link.** The recognition happens on the glasses; no audio
/// ever reaches the phone, which is why this carries no samples, no timing and no route — and why
/// opening it costs the wearer's spoken answers nothing, unlike a microphone the app has to take
/// for itself.
nonisolated struct Transcription: Equatable, Sendable {
  /// What was heard, partial or whole.
  let text: String

  /// Whether the utterance is over. Results arrive partial-then-final: the same sentence lands
  /// several times as it develops, and exactly once with this set.
  let isFinal: Bool

  /// How sure the recogniser is, `0.0`–`1.0`, or `nil` when it will not say.
  ///
  /// Optional at the source and therefore optional here — a reading nobody can check is worse
  /// than no reading, and the recogniser reports its own absence rather than guessing.
  let confidence: Float?

  init(text: String, isFinal: Bool, confidence: Float? = nil) {
    self.text = text
    self.isFinal = isFinal
    self.confidence = confidence
  }
}

/// Where the glasses' recogniser is — the reading that tells *nobody spoke* apart from *nothing is
/// listening*.
///
/// **The two are identical from the transcripts alone**, and only one of them is worth chasing. A
/// pair whose recogniser never came up produces exactly the same silence as a quiet room, which is
/// the failure this app has been bitten by on every other capability the session holds.
nonisolated enum GlassesSpeechState: Equatable, Sendable {
  /// Nothing has asked yet — no session, or one that has not reached its senses.
  case idle

  /// Asked for, and warming up.
  case starting

  /// Live: what is said now is what will be heard.
  case listening

  /// It was listening and is not now — a link that went away, or a session that ended.
  case stopped

  /// This pair has no on-device recogniser, or the capability refused to attach. Terminal for
  /// the run: nothing about it will change while these glasses are the glasses.
  case unavailable
}

/// What the wearer says, for as long as a session is listening.
///
/// **The stream is scoped to a running session, not to a recogniser of its own.** The speech
/// capability rides the device session the way the camera and the buttons do, so there is nothing
/// to open here and nothing to close: subscribing registers interest, and transcripts arrive while
/// a session is up and holds the capability. Subscribing with no session running is not an error —
/// it is simply quiet, which is the honest reading of a pair of glasses nobody is wearing.
///
/// **There is no phone-side stand-in, deliberately.** This app transcribes with the glasses or
/// not at all: the recognition runs where the wearer's voice already is, and a fallback onto
/// the phone's own recogniser would have to take the microphone off the ambient lane to do it —
/// trading the feature that is running for the feature that is not. No glasses, no
/// transcription, and the screens above say so rather than quietly substituting a different
/// instrument.
///
/// **The stream reports what was heard and never failures.** Why nothing is arriving is
/// ``speechStateStream()``'s to answer, and the session's own state answers the rest.
nonisolated protocol GlassesSpeechRepository: Sendable {
  /// Cold stream of what the wearer says, partial then final. Cancelling unsubscribes.
  func transcriptionStream() -> AsyncStream<Transcription>

  /// Cold stream of where the recogniser is. Replays its current reading to a new subscriber, so
  /// a screen that arrives mid-session is told the truth rather than left waiting for a change.
  func speechStateStream() -> AsyncStream<GlassesSpeechState>
}
