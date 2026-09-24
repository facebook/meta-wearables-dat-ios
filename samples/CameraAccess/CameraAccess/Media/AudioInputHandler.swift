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

/// Drives the glasses microphone over Bluetooth HFP: engine setup, forcing the glasses HFP
/// route as the input, interruption and app-lifecycle handling. Audio is captured only when
/// the glasses HFP mic is the active input — the phone mic is never used, even as a fallback.
/// Thread-safe via `OSAllocatedUnfairLock`.
///
/// Locking discipline: the lock guards state only. Every `AVAudioEngine` /
/// `AVAudioSession` call runs *outside* the lock — they can invoke the tap callback
/// synchronously, which re-enters the non-recursive lock. Pattern throughout:
/// snapshot under the lock, release, then touch AVFoundation.
final class AudioInputHandler: Sendable {
  /// Tap buffer size in frames. 1024 is a standard low-latency capture quantum.
  private static let tapBufferSize: AVAudioFrameCount = 1024

  private static let logger = Logger(subsystem: "com.meta.wearables.CameraAccess", category: "AudioInput")

  private struct State {
    var audioEngine = AVAudioEngine()
    var interruptionObserver: NSObjectProtocol?
    var routeChangeObserver: NSObjectProtocol?
    var mediaServicesResetObserver: NSObjectProtocol?
    var foregroundObserver: NSObjectProtocol?
    var isListening: Bool = false
    var wasListeningBeforeInterruption: Bool = false
    var isBluetoothConnected: Bool = false
    var onAudioBuffer: (@Sendable ([Float], Int, AudioStreamBasicDescription) -> Void)?
    var onInterruptionResume: (() -> Void)?
    // Fired when a configure pass finds no glasses HFP mic, so the app can reflect mic-off.
    var onGlassesAudioUnavailable: (@Sendable () -> Void)?
  }

  private let state = OSAllocatedUnfairLock(uncheckedState: State())

  init() {}

  func setup() {
    setupInterruptionHandling()
    setupAppLifecycleObservers()
  }

  func setCallbacks(
    onAudioBuffer: @escaping @Sendable ([Float], Int, AudioStreamBasicDescription) -> Void,
    onInterruptionResume: @escaping () -> Void,
    onGlassesAudioUnavailable: @escaping @Sendable () -> Void
  ) {
    state.withLockUnchecked { state in
      state.onAudioBuffer = onAudioBuffer
      state.onInterruptionResume = onInterruptionResume
      state.onGlassesAudioUnavailable = onGlassesAudioUnavailable
    }
  }

  func cleanup() {
    state.withLockUnchecked { state in
      for observer in [
        state.interruptionObserver,
        state.routeChangeObserver,
        state.mediaServicesResetObserver,
        state.foregroundObserver,
      ] {
        if let observer {
          NotificationCenter.default.removeObserver(observer)
        }
      }
      state.interruptionObserver = nil
      state.routeChangeObserver = nil
      state.mediaServicesResetObserver = nil
      state.foregroundObserver = nil
    }
  }

  func setupInput() {
    configureBluetooth()
  }

  func startListening() {
    // Claim the transition under the lock, then start the engine outside it.
    let engine: AVAudioEngine? = state.withLockUnchecked { state in
      guard !state.isListening else { return nil }
      state.isListening = true
      return state.audioEngine
    }
    guard let engine else { return }

    do {
      try engine.start()
    } catch {
      // Roll back so a later attempt can retry; surface the failure for debugging.
      state.withLockUnchecked { $0.isListening = false }
      Self.logger.error("Audio engine failed to start: \(error.localizedDescription)")
    }
  }

  func stopListening() {
    let engine: AVAudioEngine? = state.withLockUnchecked { state in
      guard state.isListening else { return nil }
      state.isListening = false
      state.wasListeningBeforeInterruption = false
      return state.audioEngine
    }
    guard let engine else { return }

    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    // Terminal stop: deactivate the shared session we claimed in configureBluetooth()
    // so other apps' audio can resume (.notifyOthersOnDeactivation prompts them).
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Self.logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
    }
  }

  // MARK: - Notification Setup

  private func setupInterruptionHandling() {
    state.withLockUnchecked { state in
      state.interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] notification in
        guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
          return
        }

        var shouldResume = false
        if type == .ended,
          let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
        {
          let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
          shouldResume = options.contains(.shouldResume)
        }

        self?.handleInterruption(type: type, shouldResume: shouldResume)
      }

      state.routeChangeObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] notification in
        guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
          return
        }

        self?.handleRouteChange(reason: reason)
      }

      state.mediaServicesResetObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] _ in
        self?.attemptAudioReset()
      }
    }
  }

  private func setupAppLifecycleObservers() {
    state.withLockUnchecked { state in
      state.foregroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.handleAppWillEnterForeground()
      }
    }
  }

  // MARK: - Event Handlers

  private func handleInterruption(type: AVAudioSession.InterruptionType, shouldResume: Bool) {
    switch type {
    case .began:
      // Pause (don't stop) so the tap stays installed; resume restarts the engine.
      let engine: AVAudioEngine? = state.withLockUnchecked { state in
        state.wasListeningBeforeInterruption = state.isListening
        return state.isListening ? state.audioEngine : nil
      }
      engine?.pause()

    case .ended:
      let shouldResumeAudio = state.withLockUnchecked { $0.wasListeningBeforeInterruption }
      if shouldResumeAudio {
        resumeAudioInput()
      }

    @unknown default:
      break
    }
  }

  private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
    switch reason {
    case .newDeviceAvailable, .oldDeviceUnavailable:
      // The glasses connected or dropped. While capturing, re-run the full configure path so
      // we re-select the glasses HFP mic — or fall back to video-only — but never the phone
      // mic. `attemptAudioReset()` reconfigures and re-gates the tap; `configureBluetooth()`
      // then reports availability. These reasons come from hardware, not our own config
      // calls, so there's no reconfigure loop.
      let isListening = state.withLockUnchecked { $0.isListening }
      if isListening {
        attemptAudioReset()
      } else {
        updateBluetoothStatus()
      }
    case .categoryChange, .override, .wakeFromSleep, .routeConfigurationChange:
      updateBluetoothStatus()
    case .unknown, .noSuitableRouteForCategory:
      break
    @unknown default:
      break
    }
  }

  private func resumeAudioInput() {
    let (bluetoothConnected, resumeCallback) = state.withLockUnchecked { state in
      (state.isBluetoothConnected, state.onInterruptionResume)
    }

    if !bluetoothConnected {
      // attemptAudioReset() restarts the engine if it was listening, so don't also
      // call startListening() here — that would double-start it.
      attemptAudioReset()
    } else {
      // Paused, not stopped (isListening still true): resume directly, since
      // startListening() guards on !isListening.
      let engine: AVAudioEngine = state.withLockUnchecked { $0.audioEngine }
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        state.withLockUnchecked { $0.isListening = true }
      } catch {
        Self.logger.error("Failed to resume audio input: \(error.localizedDescription)")
      }
    }

    resumeCallback?()
  }

  private func handleAppWillEnterForeground() {
    let bluetoothConnected = state.withLockUnchecked { $0.isBluetoothConnected }

    if !bluetoothConnected {
      attemptAudioReset()
    }
  }

  private func attemptAudioReset() {
    let (wasListening, engine) = state.withLockUnchecked { state -> (Bool, AVAudioEngine) in
      let wasListening = state.isListening
      state.isListening = false
      return (wasListening, state.audioEngine)
    }

    if engine.isRunning {
      engine.stop()
    }
    engine.inputNode.removeTap(onBus: 0)

    configureBluetooth()

    if wasListening {
      startListening()
    }
  }

  private func updateBluetoothStatus() {
    let audioSession = AVAudioSession.sharedInstance()
    let inputPort = audioSession.currentRoute.inputs.first(where: { $0.portType == .bluetoothHFP })

    state.withLockUnchecked { $0.isBluetoothConnected = inputPort != nil }
  }

  private func notifyGlassesAudioUnavailable() {
    let callback = state.withLockUnchecked { $0.onGlassesAudioUnavailable }
    callback?()
  }

  private func configureBluetooth() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothHFP, .mixWithOthers])
      try audioSession.setActive(true)
      // Force the glasses' Bluetooth HFP mic as the input so recorded audio comes from the
      // glasses, never the phone. `.allowBluetoothHFP` is what surfaces the HFP input here.
      if let glassesInput = audioSession.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
        try audioSession.setPreferredInput(glassesInput)
      }
    } catch {
      Self.logger.error("Failed to configure audio session: \(error.localizedDescription)")
      state.withLockUnchecked { $0.isBluetoothConnected = false }
      notifyGlassesAudioUnavailable()
      return
    }

    // Capture only when the glasses HFP mic is the active input. If it isn't, install no tap
    // and record video-only — the phone mic is never used, even as a fallback.
    let glassesActive = audioSession.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }

    // Snapshot under the lock, then install the tap outside it — installTap can fire
    // the callback synchronously, re-entering the lock and deadlocking.
    let inputNode = state.withLockUnchecked { state -> AVAudioInputNode in
      state.isBluetoothConnected = glassesActive
      return state.audioEngine.inputNode
    }
    let callback = state.withLockUnchecked { $0.onAudioBuffer }

    if glassesActive, let callback {
      setupAudioEngineTap(inputNode: inputNode, onAudioBuffer: callback)
    }
    if !glassesActive {
      // No glasses HFP mic → recording video-only; tell the app so it can reflect mic-off.
      notifyGlassesAudioUnavailable()
    }
  }

  private nonisolated func setupAudioEngineTap(
    inputNode: AVAudioInputNode,
    onAudioBuffer: @escaping @Sendable ([Float], Int, AudioStreamBasicDescription) -> Void
  ) {
    let format = inputNode.inputFormat(forBus: 0)

    // A device with no usable microphone — a simulator/CI host with no audio input, or a
    // user who denied mic permission — reports a zero format. installTap() with a zero
    // format throws an uncaught AVAudioEngine exception that crashes the app, so skip the
    // tap and record video-only instead.
    guard format.sampleRate > 0, format.channelCount > 0 else {
      Self.logger.error(
        "No usable audio input (sampleRate=\(format.sampleRate), channels=\(format.channelCount)); recording without audio"
      )
      return
    }

    inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { buffer, _ in
      guard let channelData = buffer.floatChannelData?[0] else { return }
      let frameCount = Int(buffer.frameLength)
      let audioData = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
      let bufferFormat = buffer.format.streamDescription.pointee

      onAudioBuffer(audioData, frameCount, bufferFormat)
    }
  }
}
