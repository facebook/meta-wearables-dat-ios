/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PhoneMicrophoneSource.swift
//  birdspotter
//

import AVFoundation
import Foundation

/// The phone's microphone as an ``AudioCaptureSource`` — the spine of a real-time session until a
/// pair of glasses is connected, and what it falls back to when one disconnects.
///
/// **Converted to 16 kHz at the edge, not left wide.** The hardware gives whatever it gives
/// (48 kHz, usually) and `AVAudioConverter` brings it down to the one format the app records in,
/// so the strip looks the same whether the session is hearing through the phone or through the
/// glasses — see ``captureSampleRate``.
///
/// The engine, the audio session and the resampling all live in ``MicrophoneCapture``. Note that
/// opening sets the shared `AVAudioSession` category to `.playAndRecord`; `SystemAudioClipPlayer`
/// sets `.playback` when it plays a reference call, so the two cannot run at once today. Nothing
/// asks them to yet.
///
/// Cold, and it means it: nothing is opened until someone iterates, and `onTermination` is what
/// stops the engine and hands the audio session back.
nonisolated final class PhoneMicrophoneSource: AudioCaptureSource {

  let kind = CaptureSourceKind.phone

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    AsyncThrowingStream { continuation in
      // The Identify gate should have collected this already, so reaching here unauthorized
      // means access was revoked from Settings while the session was open.
      guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        continuation.finish(throwing: AudioCaptureError.accessDenied)
        return
      }

      let capture = MicrophoneCapture(continuation: continuation)
      continuation.onTermination = { _ in capture.stop() }
      capture.start()
    }
  }
}
