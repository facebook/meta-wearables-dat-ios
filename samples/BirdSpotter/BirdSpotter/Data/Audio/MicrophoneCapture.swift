/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MicrophoneCapture.swift
//  birdspotter
//

import AVFoundation
import Foundation

/// The engine behind the phone's live microphone stream.
///
/// **The phone's input and nothing else.** The glasses' microphone does not come through the audio
/// session at all — it arrives on the DAT camera stream (see ``GlassesMicrophoneSource``) — so this
/// class never names a port and never has to refuse one. What it asks the session for is whatever
/// the phone would use on its own, which is the built-in microphone.
///
/// `@unchecked Sendable` covers the same ground it does in `PhoneCameraPreviewSource`: the tap
/// callback arrives on AVFoundation's own thread and everything it touches — the converter, the
/// target format — is either immutable or owned by that callback alone.
///
/// **Opening runs on ``queue``, not on the caller.** `AsyncThrowingStream`'s builder runs where
/// the stream is *made*, which is the session's `@MainActor` — and activating an
/// `AVAudioSession` tears down and rebuilds the audio route, which routinely takes the better
/// part of a second. Left on the main thread that is the whole cover sitting frozen on a tap of
/// Start Listening. The camera reached the same conclusion for `startRunning()`; the queue is
/// serial, so a `stop()` racing an unfinished `start()` still runs after it.
nonisolated final class MicrophoneCapture: NSObject, @unchecked Sendable {

  private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
  /// **One queue for every capture, not one each.** A session that closes the microphone and
  /// opens it again in the same breath mutates the one shared `AVAudioSession` twice — on
  /// per-instance queues the dying capture's `setActive(false)` can land *after* the next engine
  /// has started, silencing it without an error for anyone to hear. `stop()` is enqueued at
  /// termination time, before the next open can be asked for, so a single serial queue makes
  /// every reopening teardown-then-bring-up.
  private static let queue = DispatchQueue(label: "com.pixelandtexel.birdspotter.microphone")
  private let engine = AVAudioEngine()

  /// The one format the app records in, whatever the hardware hands over.
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Double(captureSampleRate),
    channels: 1,
    interleaved: false
  )

  private var converter: AVAudioConverter?

  init(continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
    self.continuation = continuation
    super.init()
  }

  func start() {
    Self.queue.async { [self] in open() }
  }

  func stop() {
    Self.queue.async { [self] in
      NotificationCenter.default.removeObserver(self)
      engine.inputNode.removeTap(onBus: 0)
      if engine.isRunning { engine.stop() }
      // Politeness: whatever was playing before the session opened gets to resume.
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  /// Everything that blocks: the audio session and the engine.
  private func open() {
    guard let targetFormat else {
      continuation.finish(throwing: AudioCaptureError.unavailable)
      return
    }

    let session = AVAudioSession.sharedInstance()
    do {
      // `.measurement` turns off the processing chain iOS otherwise applies to a recording
      // — automatic gain, noise suppression, the things that make a voice memo sound better
      // and a bird call look wrong.
      //
      // **`.playAndRecord` rather than `.record`, because a session has to be able to
      // answer out loud.** Under `.record` the app is muted for as long as the capture is
      // open, and an identification with a spoken line attached would be silently dropped
      // by the category rather than by any rule anybody wrote — see ``SpokenOutput``. It
      // changes nothing about the recording: the processing chain is `mode`'s business, and
      // `.measurement` is unmoved.
      //
      // **`.allowBluetoothA2DP` and never `.allowBluetoothHFP`.** The media profile has no
      // microphone in it, so the option can only ever reach the *output* — it is what lets a
      // line reach a pair of glasses while the phone does the listening, and it cannot make
      // this stream hear through anything. The hands-free option is not passive: with it set
      // and a headset connected, the system's *default* input becomes the headset, and a
      // "phone" stream would quietly hear through the glasses at a fraction of this rate.
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP])
      try session.setActive(true)
      try session.setPreferredInput(nil)
    } catch {
      continuation.finish(throwing: AudioCaptureError.unavailable)
      return
    }

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    // A zero sample rate is the simulator with no input, and the honest answer to it is "there
    // is nothing to listen with" rather than an engine that starts and never speaks.
    guard inputFormat.sampleRate > 0,
      let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    else {
      continuation.finish(throwing: AudioCaptureError.unavailable)
      return
    }
    self.converter = converter

    // Unlike the camera, an interruption here *is* terminal: AVFoundation stops the engine for
    // a phone call and does not start it again, so riding it out would leave a session that
    // looks live and hears nothing.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sessionInterrupted),
      name: AVAudioSession.interruptionNotification,
      object: session
    )

    input.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { [weak self] buffer, _ in
      self?.deliver(buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      continuation.finish(throwing: AudioCaptureError.unavailable)
    }
  }

  /// Resamples one tap buffer and hands the samples on.
  private func deliver(_ buffer: AVAudioPCMBuffer) {
    guard let converter, let targetFormat else { return }

    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

    // The converter pulls rather than takes, because a sample-rate change means input and
    // output frame counts differ. One buffer in, then `.noDataNow` to say that is all there is
    // this time round.
    var supplied = false
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return buffer
    }

    guard error == nil, let samples = converted.floatChannelData?[0] else { return }
    let count = Int(converted.frameLength)
    guard count > 0 else { return }

    let raw = UnsafeBufferPointer(start: samples, count: count)
    continuation.yield(
      AudioChunk(samples: raw.map { $0 * Self.gain }, source: .phone)
    )
  }

  /// How much the phone's samples are lifted before anything downstream sees them — about
  /// +9.5 dB.
  ///
  /// **This exists because ``open()`` asks for `.measurement`, and it is not a way of walking that
  /// back.** Measurement mode is what turns off the processing chain iOS otherwise applies to a
  /// recording — automatic gain among it — because that chain is tuned to make a voice memo sound
  /// good and it makes a bird call *look* wrong on a spectrogram. What it costs is level: with AGC
  /// off, a bird two gardens away sits far enough down the scale that the strip draws it as floor.
  /// A flat multiplier buys the level back without any of the processing coming with it — the
  /// picture is the same shape, drawn higher up the dB scale. Enough that an unprocessed phone
  /// microphone reads at the height an AGC-assisted one arrives at, and short of the point where
  /// room noise starts to draw.
  ///
  /// Nothing clips as a result of this. ``WavCodec`` clamps at encode, and the analyzer's dB scale
  /// tops out at zero, so a loud sample that this pushes past full scale is bounded twice over
  /// before it reaches either the file or the strip.
  ///
  /// **The number differs between the platforms because the microphones do; the seam is here on
  /// both so that stays one decision in one named place rather than a magic multiply in a tap
  /// callback.**
  private static let gain: Float = 3

  @objc private func sessionInterrupted(_ notification: Notification) {
    guard
      let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .began
    else { return }
    continuation.finish(throwing: AudioCaptureError.interrupted)
  }
}

/// Frames per tap. The engine delivers at the hardware's rate, so this is a request rather than a
/// promise — a few hundred milliseconds either way changes nothing downstream, since the analyzer
/// buffers whatever it is given.
private let tapFrames: AVAudioFrameCount = 4096
