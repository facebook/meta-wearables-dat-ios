/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  AudioCaptureSource.swift
//  birdspotter
//

import Foundation

/// The one sample rate the app records at, whichever microphone it is holding.
///
/// 16 kHz mono is the narrowest format the glasses' camera stream will carry, and the phone is
/// converted to the *same* rather than kept wide. That is a demo decision as much as a
/// technical one: a sonogram drawn from full-bandwidth phone audio is visibly taller and busier
/// than the same bird heard through the glasses, so matching the format means switching sources
/// changes the pill and nothing else on screen.
///
/// The ceiling that follows is **8 kHz** — half the sample rate, which takes in the fundamentals of
/// almost every songbird. Recording wider would buy harmonics the strip has no room to draw.
nonisolated let captureSampleRate = 16000

/// A slice of mono audio, normalised to −1..1.
///
/// Floats rather than the raw PCM buffers the SDK hands over: everything downstream — the
/// window, the transform, the magnitudes — is arithmetic, and converting once at the source beats
/// converting in every consumer.
nonisolated struct AudioChunk: Sendable {
  let samples: [Float]
  var sampleRate: Int = captureSampleRate

  /// Which microphone this slice came out of.
  ///
  /// **On the chunk rather than on the source**, because ``FailoverAudioSource`` is one
  /// stream whose answer changes halfway through a session, and `kind` is a constant. The
  /// pill reads the latest one, so what the screen claims is always a fact about audio that
  /// has actually arrived — never about a microphone that has merely been asked for.
  var source: CaptureSourceKind = .phone
}

/// Why a session has no sound.
///
/// The same three answers ``CameraPreviewError`` gives, for the same reason — they said no, there
/// is nothing to listen with, or something else took the microphone.
nonisolated enum AudioCaptureError: Error, Equatable, Sendable {
  /// Microphone permission is not granted. The Identify gate should have caught this first.
  case accessDenied

  /// No microphone to open — no route, or the glasses session is not up.
  case unavailable

  /// The microphone was opened and then lost: another app took it, or the session dropped.
  case interrupted
}

/// A live microphone, as one cold stream of sample slices — the spine a real-time session is built
/// on.
///
/// The twin of ``CameraPreviewSource``, deliberately: same shape, same lifecycle, same
/// ``CaptureSourceKind``, so the glasses' microphone drops in over DAT's camera stream exactly the
/// way a `GlassesPreviewSource` will over its frames. The session holds both and never stops holding this one — a
/// viewfinder can be closed, but a session that stopped listening is not a session.
///
/// Cold, per the architecture contract: iterating starts the microphone and cancelling stops it.
/// The stream fails with an ``AudioCaptureError``; it does not finish on its own.
nonisolated protocol AudioCaptureSource: Sendable {

  /// Which microphone this is — what the session's source pill reads.
  var kind: CaptureSourceKind { get }

  /// Sample slices until the iteration ends. Cold: iterating is what opens the mic.
  func audioStream() -> AsyncThrowingStream<AudioChunk, Error>
}
