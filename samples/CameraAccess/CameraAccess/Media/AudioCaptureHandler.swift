/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import UIKit
import os

/// Writes the glasses-mic (Bluetooth HFP) audio track for a recording: owns the audio
/// `AVAssetWriterInput` and `AudioInputHandler`, encodes AAC, and gap-fills silence
/// across interruptions to keep the track aligned with the timeline.
/// Thread-safe via `OSAllocatedUnfairLock`, which guards the non-Sendable state.
final class AudioCaptureHandler: Sendable {
  /// AAC output configuration for the audio track.
  private static let audioSampleRate = 44_100.0
  private static let audioBitRate = 192_000
  /// Silence gap-fill uses 1024-sample buffers, the AAC frame size.
  private static let silenceSamplesPerBuffer = 1024
  /// Backoff between gap-fill append retries when the input isn't ready yet.
  private static let silenceRetryDelayNanos: UInt64 = 1_000_000
  /// Cap on consecutive not-ready retries before abandoning the gap fill, so a
  /// permanently not-ready input (e.g. a writer that has failed) can't busy-wait forever.
  private static let maxConsecutiveNotReadyRetries = 200
  /// A track is "streaming" if it wrote within this many seconds.
  private static let streamingStalenessSeconds = 2.0

  private static let logger = Logger(subsystem: "com.meta.wearables.CameraAccess", category: "AudioCapture")

  /// Outcome of attempting to append one gap-fill silence buffer.
  private enum SilenceFillOutcome {
    case appended
    case notReady
    case finished
  }

  private let recordingStartTime: Date
  /// Fired once at capture start (and on a mid-recording glasses drop) when the glasses HFP mic
  /// isn't available, so the app can reflect that the recording is video-only.
  private let onGlassesAudioUnavailable: @Sendable () -> Void

  private struct State {
    var audioInput: AVAssetWriterInput
    var audioInputHandler: AudioInputHandler
    var lastAudioWriteTime: Date?
    var lastAudioPresentationTime: CMTime = .zero
    var audioFormat: AudioStreamBasicDescription?
    // Set true by stop() so a late buffer can't append after markAsFinished().
    var isFinished: Bool = false
  }

  private let state: OSAllocatedUnfairLock<State>

  var isAudioStreaming: Bool {
    let lastWrite = state.withLockUnchecked { $0.lastAudioWriteTime }
    guard let lastWrite else { return false }
    return Date().timeIntervalSince(lastWrite) < Self.streamingStalenessSeconds
  }

  init(
    writer: AVAssetWriter,
    recordingStartTime: Date,
    onGlassesAudioUnavailable: @escaping @Sendable () -> Void
  ) {
    self.recordingStartTime = recordingStartTime
    self.onGlassesAudioUnavailable = onGlassesAudioUnavailable

    let audioInput = Self.createAudioWriterInput()
    self.state = OSAllocatedUnfairLock(
      uncheckedState: State(
        audioInput: audioInput,
        audioInputHandler: AudioInputHandler()
      ))

    if writer.canAdd(audioInput) {
      writer.add(audioInput)
    } else {
      Self.logger.error("Couldn't add audio input to asset writer")
    }
  }

  func start() {
    // Snapshot the handler, then drive it outside the lock: it installs the tap, whose
    // callback re-enters this lock via processAudioBuffer — holding the lock would deadlock.
    let handler = state.withLockUnchecked { $0.audioInputHandler }
    handler.setCallbacks(
      onAudioBuffer: { [weak self] audioData, numSamples, format in
        self?.processAudioBuffer(audioData: audioData, numSamples: numSamples, format: format)
      },
      onInterruptionResume: { [weak self] in
        guard let self else { return }
        Task {
          await self.fillSilenceForInterruption()
        }
      },
      onGlassesAudioUnavailable: onGlassesAudioUnavailable
    )
    handler.setup()
    handler.setupInput()
    handler.startListening()
  }

  func stop() {
    // Tear down outside the lock (engine.stop() can flush a last tap callback that
    // re-enters it). Then set isFinished under the append lock, so no late buffer
    // appends after markAsFinished().
    let handler = state.withLockUnchecked { $0.audioInputHandler }
    handler.stopListening()
    handler.cleanup()
    state.withLockUnchecked { state in
      state.isFinished = true
      state.audioInput.markAsFinished()
    }
  }

  // MARK: - Audio Frame Handling

  private func processAudioBuffer(audioData: [Float], numSamples: Int, format: AudioStreamBasicDescription) {
    // Anchor presentation time to wall-clock elapsed (not a sample count) so silence
    // gap-fill and resumed mic audio share one origin and stay aligned across an
    // interruption. A sample count advances only on real samples, so the resumed audio
    // would land before the fill and overlap it.
    let currentTime = CMTime(
      seconds: Date().timeIntervalSince(recordingStartTime),
      preferredTimescale: CMTimeScale(format.mSampleRate)
    )

    let sampleBuffer = Self.createAudioSampleBuffer(
      from: audioData,
      numSamples: numSamples,
      format: format,
      presentationTime: currentTime
    )

    // Append under the same lock as markAsFinished(), so no late buffer fails the writer.
    state.withLockUnchecked { state in
      if state.audioFormat == nil {
        state.audioFormat = format
      }
      guard !state.isFinished, let sampleBuffer, state.audioInput.isReadyForMoreMediaData else { return }
      if state.audioInput.append(sampleBuffer) {
        state.lastAudioWriteTime = Date()
        state.lastAudioPresentationTime = currentTime
      }
    }
  }

  private func fillSilenceForInterruption() async {
    let (format, lastPresentationTime) = state.withLockUnchecked { state in
      (state.audioFormat, state.lastAudioPresentationTime)
    }

    guard let format, lastPresentationTime != .zero else {
      return
    }

    let currentExpectedTime = Date().timeIntervalSince(recordingStartTime)
    let lastWrittenTime = lastPresentationTime.seconds
    let interruptionDuration = currentExpectedTime - lastWrittenTime

    guard interruptionDuration > 0 else { return }

    let sampleRate = format.mSampleRate
    let samplesPerBuffer = Self.silenceSamplesPerBuffer
    let bufferDuration = Double(samplesPerBuffer) / sampleRate
    let silenceBufferCount = Int(ceil(interruptionDuration / bufferDuration))

    var currentTime = lastPresentationTime.seconds
    var buffersWritten = 0
    var consecutiveNotReady = 0

    while buffersWritten < silenceBufferCount {
      let presentationTime = CMTime(seconds: currentTime, preferredTimescale: CMTimeScale(sampleRate))
      let silenceBuffer = [Float](repeating: 0.0, count: samplesPerBuffer)

      guard
        let sampleBuffer = Self.createAudioSampleBuffer(
          from: silenceBuffer,
          numSamples: samplesPerBuffer,
          format: format,
          presentationTime: presentationTime
        )
      else {
        // Couldn't build this silence buffer; skip the slot so we can't loop forever.
        currentTime += bufferDuration
        buffersWritten += 1
        continue
      }

      // Re-check readiness and honor the result under the append lock, so the timeline
      // advances only on a real append — advancing on a no-op would desync the gap fill.
      let outcome = state.withLockUnchecked { state -> SilenceFillOutcome in
        guard !state.isFinished else { return .finished }
        guard state.audioInput.isReadyForMoreMediaData else { return .notReady }
        return state.audioInput.append(sampleBuffer) ? .appended : .notReady
      }

      switch outcome {
      case .finished:
        return
      case .notReady:
        consecutiveNotReady += 1
        if consecutiveNotReady >= Self.maxConsecutiveNotReadyRetries {
          Self.logger.error("Audio input stayed not-ready for \(consecutiveNotReady) retries; abandoning silence fill")
          return
        }
        try? await Task.sleep(nanoseconds: Self.silenceRetryDelayNanos)
      case .appended:
        consecutiveNotReady = 0
        currentTime += bufferDuration
        buffersWritten += 1
      }
    }

    state.withLockUnchecked { state in
      state.lastAudioPresentationTime = CMTime(seconds: currentTime, preferredTimescale: CMTimeScale(sampleRate))
    }
  }

  // MARK: - Static Helpers

  private static func createAudioWriterInput() -> AVAssetWriterInput {
    let audioSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: audioSampleRate,
      AVEncoderBitRateKey: audioBitRate,
    ]

    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
    input.expectsMediaDataInRealTime = true
    return input
  }

  private static func createAudioSampleBuffer(
    from buffer: [Float],
    numSamples: Int,
    format: AudioStreamBasicDescription,
    presentationTime: CMTime
  ) -> CMSampleBuffer? {
    var formatCopy = format
    var formatDescription: CMFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      asbd: &formatCopy,
      layoutSize: 0,
      layout: nil,
      magicCookieSize: 0,
      magicCookie: nil,
      extensions: nil,
      formatDescriptionOut: &formatDescription
    )

    guard status == noErr, let formatDesc = formatDescription else {
      return nil
    }

    let dataSize = numSamples * Int(format.mBytesPerFrame)
    var blockBuffer: CMBlockBuffer?

    guard
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: dataSize,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: dataSize,
        flags: 0,
        blockBufferOut: &blockBuffer
      ) == noErr, let blockBuf = blockBuffer
    else {
      return nil
    }

    let copyResult = buffer.withUnsafeBytes { bufferPointer -> OSStatus in
      guard let baseAddress = bufferPointer.baseAddress else {
        return -1
      }
      return CMBlockBufferReplaceDataBytes(
        with: baseAddress,
        blockBuffer: blockBuf,
        offsetIntoDestination: 0,
        dataLength: dataSize
      )
    }

    guard copyResult == noErr else {
      return nil
    }

    let sampleDuration = CMTime(value: CMTimeValue(numSamples), timescale: CMTimeScale(format.mSampleRate))
    var sampleTiming = CMSampleTimingInfo(
      duration: sampleDuration,
      presentationTimeStamp: presentationTime,
      decodeTimeStamp: CMTime.invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let createStatus = CMSampleBufferCreate(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuf,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: formatDesc,
      sampleCount: numSamples,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &sampleTiming,
      sampleSizeEntryCount: 0,
      sampleSizeArray: nil,
      sampleBufferOut: &sampleBuffer
    )

    guard createStatus == noErr else {
      return nil
    }

    return sampleBuffer
  }
}
