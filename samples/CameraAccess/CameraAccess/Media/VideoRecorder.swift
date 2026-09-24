/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMedia
import os

/// Outcome of finalizing a recording: a finished file, nothing recorded, or a
/// writer failure the caller can surface to the user.
enum RecordingStopResult {
  case completed(URL)
  case noRecording
  case failed
}

/// Records the glasses camera stream to a `.mov` in the temporary directory. Owns
/// the `AVAssetWriter` and delegates compressed video to `VideoCaptureHandler` and
/// (when enabled) glasses-mic (Bluetooth HFP) audio to `AudioCaptureHandler` on the same writer.
/// Thread-safe via `OSAllocatedUnfairLock`, which guards the non-Sendable AVFoundation state.
final class VideoRecorder: Sendable {
  private struct State {
    var assetWriter: AVAssetWriter?
    var audioCaptureHandler: AudioCaptureHandler?
    var videoCaptureHandler: VideoCaptureHandler?
    var outputURL: URL?
    var recordingStartTime: Date?
    var isRecording: Bool = false
    // Recording is gated by the shutter: frames are written only while this is true.
    var shouldAcceptNewFrames: Bool = false
    // Whether to record glasses-microphone (Bluetooth HFP) audio alongside video.
    var includeAudio: Bool = true
    // Forwarded to the audio handler; fires when the glasses mic isn't available at capture.
    var onGlassesAudioUnavailable: (@Sendable () -> Void)?
  }

  private let state = OSAllocatedUnfairLock(uncheckedState: State())

  private static let logger = Logger(subsystem: "com.meta.wearables.CameraAccess", category: "Recording")

  var isRecording: Bool {
    state.withLockUnchecked { $0.isRecording }
  }

  /// Wall-clock time the recording actually began (first written frame), or nil when
  /// not recording. Drives the on-screen timer so it counts continuously, including
  /// through a stream pause.
  var recordingStartDate: Date? {
    state.withLockUnchecked { $0.recordingStartTime }
  }

  var isAudioStreaming: Bool {
    state.withLockUnchecked { $0.audioCaptureHandler?.isAudioStreaming ?? false }
  }

  var isVideoStreaming: Bool {
    state.withLockUnchecked { $0.videoCaptureHandler?.isVideoStreaming ?? false }
  }

  init() {}

  // MARK: - Recording Control

  /// Stops accepting frames so the recording can be finalized.
  func prepareToStop() {
    state.withLockUnchecked { $0.shouldAcceptNewFrames = false }
  }

  /// Allows the next frame to auto-start a new recording, recording glasses-mic (Bluetooth
  /// HFP) audio alongside video when `includeAudio` is true. `onGlassesAudioUnavailable` fires
  /// if the glasses mic isn't available at capture, so the caller can reflect mic-off.
  func prepareToStart(
    includeAudio: Bool,
    onGlassesAudioUnavailable: @escaping @Sendable () -> Void
  ) {
    state.withLockUnchecked {
      $0.shouldAcceptNewFrames = true
      $0.includeAudio = includeAudio
      $0.onGlassesAudioUnavailable = onGlassesAudioUnavailable
    }
  }

  private func startRecording(with sampleBuffer: CMSampleBuffer, includeAudio: Bool) {
    let (shouldAccept, alreadyRecording) = state.withLockUnchecked { state in
      (state.shouldAcceptNewFrames, state.isRecording)
    }

    guard shouldAccept, !alreadyRecording else {
      return
    }

    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return
    }

    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    let width = Int(dimensions.width)
    let height = Int(dimensions.height)

    guard width > 0, height > 0 else { return }

    let timestamp = Date().timeIntervalSince1970
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording_\(timestamp).mov")

    do {
      let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

      let startTime = Date()

      let videoHandler = VideoCaptureHandler(writer: writer, width: width, height: height, sourceFormatHint: formatDescription)

      var audioHandler: AudioCaptureHandler?
      if includeAudio {
        let noopUnavailable: @Sendable () -> Void = {}
        let onGlassesAudioUnavailable =
          state.withLockUnchecked { $0.onGlassesAudioUnavailable } ?? noopUnavailable
        audioHandler = AudioCaptureHandler(
          writer: writer,
          recordingStartTime: startTime,
          onGlassesAudioUnavailable: onGlassesAudioUnavailable
        )
      }

      if writer.startWriting() {
        writer.startSession(atSourceTime: .zero)

        state.withLockUnchecked { state in
          state.assetWriter = writer
          state.videoCaptureHandler = videoHandler
          state.audioCaptureHandler = audioHandler
          state.outputURL = url
          state.recordingStartTime = startTime
          state.isRecording = true
        }

        videoHandler.start()
        audioHandler?.start()
      } else {
        Self.logger.error("Asset writer failed to start writing")
        cleanup()
      }
    } catch {
      Self.logger.error("Failed to create asset writer: \(error.localizedDescription)")
      cleanup()
    }
  }

  /// Finalizes the recording: `.completed(url)`, `.noRecording`, or `.failed`. Returns
  /// the result directly (rather than stashing the URL) to avoid a read race.
  func stopRecording() async -> RecordingStopResult {
    let (shouldStop, url, videoHandler, audioHandler, writer) = state.withLockUnchecked { state -> (Bool, URL?, VideoCaptureHandler?, AudioCaptureHandler?, AVAssetWriter?) in
      guard state.isRecording else {
        return (false, nil, nil, nil, nil)
      }
      // Clear both flags atomically so a late frame can't auto-start a new recording
      // while this one finalizes.
      state.isRecording = false
      state.shouldAcceptNewFrames = false
      return (true, state.outputURL, state.videoCaptureHandler, state.audioCaptureHandler, state.assetWriter)
    }

    guard shouldStop else { return .noRecording }

    // Finish inputs under the same lock the frame thread appends on, so no late append
    // slips through to fail the writer. finishWriting() flushes the queue — no drain
    // delay, since passthrough appends are synchronous.
    videoHandler?.stop()
    audioHandler?.stop()

    guard let writer, let url else {
      cleanup()
      return .noRecording
    }

    await writer.finishWriting()
    let completed = writer.status == .completed
    if !completed {
      Self.logger.error("Asset writer did not finish cleanly (status: \(writer.status.rawValue))")
    }
    // Clear only if a newer recording hasn't replaced this one (a quick stop→start can).
    state.withLockUnchecked { state in
      guard state.assetWriter === writer else { return }
      state.assetWriter = nil
      state.videoCaptureHandler = nil
      state.audioCaptureHandler = nil
      state.outputURL = nil
      state.recordingStartTime = nil
    }
    return completed ? .completed(url) : .failed
  }

  // MARK: - Video Frame Handling

  func appendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
    // Start on the first keyframe (IDR) so the video track opens on a decodable frame;
    // leading P-frames otherwise play back black.
    if !isRecording {
      let (shouldAccept, includeAudio) = state.withLockUnchecked { ($0.shouldAcceptNewFrames, $0.includeAudio) }
      guard shouldAccept, sampleBuffer.isHEVCKeyframe() else { return }
      startRecording(with: sampleBuffer, includeAudio: includeAudio)
    }
    let videoHandler = state.withLockUnchecked { $0.videoCaptureHandler }
    videoHandler?.appendVideoFrame(sampleBuffer)
  }

  // MARK: - Helpers

  private func cleanup() {
    state.withLockUnchecked { state in
      state.assetWriter = nil
      state.videoCaptureHandler = nil
      state.audioCaptureHandler = nil
      state.outputURL = nil
      state.recordingStartTime = nil
      // Stop accepting frames so a failed start doesn't retry on every frame.
      state.shouldAcceptNewFrames = false
    }
  }
}
