/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import MWDATCamera
import MWDATCore
import AVFoundation
import SwiftUI

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum StudyCyclePhase {
  case idle
  case streaming
  case capturingPhoto
  case waitingForNextCycle
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false

  var isStreaming: Bool {
    streamingStatus != .stopped
  }
  
  // Study session properties
  @Published var isStudySessionActive: Bool = false
  @Published var studyCyclePhase: StudyCyclePhase = .idle
  @Published var photoCaptureCount: Int = 0
  @Published var countdownToNextCapture: Int = 0
  
  // Study session manager for API calls
  let sessionManager = StudySessionManager.shared
  
  // Audio WebSocket client for streaming audio to/from server
  private var audioWsClient: AudioWsClient?
  @Published var isAudioStreamingActive: Bool = false
  
  // WebSocket URL for audio streaming (same server as image uploads)
  private let audioWsURL = URL(string: "ws://10.29.240.40:7863/ws")!
  
  var studyCycleStatusText: String {
    switch studyCyclePhase {
    case .idle:
      return "Ready to start"
    case .streaming:
      return "Stream active • Monitoring..."
    case .capturingPhoto:
      return "📸 Photo captured!"
    case .waitingForNextCycle:
      return "Stream active • Next capture in \(countdownToNextCapture)s"
    }
  }
  
  private var studyCycleTask: Task<Void, Never>?
  private let captureInterval: Int = 5 // seconds between captures

  // Timer properties
  @Published var activeTimeLimit: StreamTimeLimit = .noLimit
  @Published var remainingTime: TimeInterval = 0

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  private var timerTask: Task<Void, Never>?
  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    // State changes tell us when streaming starts, stops, or encounters issues
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // Each VideoFrame contains the raw camera data that we convert to UIImage
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
        }
      }
    }

    // Subscribe to streaming errors
    // Errors include device disconnection, streaming failures, etc.
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    // PhotoData contains the captured image in the requested format (JPEG/HEIC)
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        // During study session, upload to backend for analysis
        if self.isStudySessionActive {
          self.photoCaptureCount += 1
          print("📸 Study session photo captured! Count: \(self.photoCaptureCount)")
          
          // Fire-and-forget upload to backend
          Task {
            await self.sessionManager.uploadAndAnalyze(imageData: photoData.data)
          }
        } else {
          // Normal photo capture - show preview
          if let uiImage = UIImage(data: photoData.data) {
            self.capturedPhoto = uiImage
            self.showPhotoPreview = true
          }
        }
      }
    }
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.description)")
    }
  }
  
  // MARK: - Study Session Methods
  
  func handleStartStudySession() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      print("📋 Camera permission status: \(status)")
      if status == .granted {
        await startStudySession()
        return
      }
      print("📋 Requesting camera permission...")
      let requestStatus = try await wearables.requestPermission(permission)
      print("📋 Permission request result: \(requestStatus)")
      if requestStatus == .granted {
        await startStudySession()
        return
      }
      showError("Permission denied. Please grant camera access in the Meta AI app.")
    } catch {
      print("❌ Permission error details: \(error)")
      print("❌ Error type: \(type(of: error))")
      // Try to start anyway - the error might be a false positive
      print("⚠️ Attempting to start session despite permission error...")
      await startStudySession()
    }
  }
  
  func startStudySession() async {
    isStudySessionActive = true
    photoCaptureCount = 0
    studyCyclePhase = .streaming
    
    // Start backend session first
    let sessionStarted = await sessionManager.startSession()
    if !sessionStarted {
      print("⚠️ Failed to start backend session, continuing anyway...")
    }
    
    // Start audio WebSocket streaming
    startAudioStreaming()
    
    // Start streaming once and keep it running
    await streamSession.start()
    
    // Wait for streaming to initialize
    try? await Task.sleep(nanoseconds: UInt64(1.5 * Double(NSEC_PER_SEC)))
    
    // Start the photo capture cycle (stream stays running)
    startStudyCycleTask()
  }
  
  private var isStoppingSession: Bool = false
  
  func stopStudySession() async {
    // Prevent double-calling (from button + onDisappear)
    guard !isStoppingSession else {
      print("⚠️ Session already stopping, skipping duplicate call")
      return
    }
    isStoppingSession = true
    
    isStudySessionActive = false
    studyCycleTask?.cancel()
    studyCycleTask = nil
    studyCyclePhase = .idle
    
    // Stop audio WebSocket streaming
    stopAudioStreaming()
    
    // Make sure streaming is stopped
    await streamSession.stop()
    
    // End backend session
    let totalAnalyses = await sessionManager.endSession()
    if let total = totalAnalyses {
      print("✅ Study session ended. Total analyses: \(total)")
    }
    
    isStoppingSession = false
  }
  
  // MARK: - Audio WebSocket Streaming
  
  private func startAudioStreaming() {
    // Get session ID from session manager
    let sessionId = sessionManager.currentSessionId
    
    // Create new client with session ID and start streaming
    audioWsClient = AudioWsClient(wsURL: audioWsURL, sessionId: sessionId)
    audioWsClient?.onRealtimeAIToggled = { [weak self] isOn in
      Task { @MainActor in
        self?.handleRealtimeAIToggle(isOn: isOn)
      }
    }
    audioWsClient?.start()
    isAudioStreamingActive = true
    print("🔊 Audio WebSocket streaming started to: \(audioWsURL)")
    if let sessionId = sessionId {
      print("🔊 Using session_id: \(sessionId)")
    } else {
      print("⚠️ No session_id available for audio streaming")
    }
  }
  
  private func stopAudioStreaming() {
    audioWsClient?.stop()
    audioWsClient = nil
    isAudioStreamingActive = false
    print("🔊 Audio WebSocket streaming stopped")
  }

  private func handleRealtimeAIToggle(isOn: Bool) {
    print("🤖 Realtime AI toggled: \(isOn ? "ON" : "OFF")")
    if isOn {
      pauseStudyCycleTask()
    } else {
      resumeStudyCycleTaskIfNeeded()
    }
  }

  private func pauseStudyCycleTask() {
    print("⏸️ Pausing study cycle task (photo capture loop)")
    studyCycleTask?.cancel()
    studyCycleTask = nil
    if isStudySessionActive {
      studyCyclePhase = .streaming
    }
  }

  private func resumeStudyCycleTaskIfNeeded() {
    guard isStudySessionActive, studyCycleTask == nil else { return }
    print("▶️ Resuming study cycle task (photo capture loop)")
    startStudyCycleTask()
  }

  private func startStudyCycleTask() {
    studyCycleTask?.cancel()
    studyCycleTask = Task { @MainActor [weak self] in
      guard let self else { return }
      
      print("🎥 Streaming started with photo capture every \(self.captureInterval) seconds")
      
      while !Task.isCancelled && self.isStudySessionActive {
        // Capture photo
        self.studyCyclePhase = .capturingPhoto
        self.streamSession.capturePhoto(format: .jpeg)
        print("📸 Capturing photo...")
        
        // Show "Photo captured!" for 1 second
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        
        guard !Task.isCancelled && self.isStudySessionActive else { break }
        
        // Wait for next capture (stream keeps running in background)
        self.studyCyclePhase = .waitingForNextCycle
        for countdown in stride(from: self.captureInterval, to: 0, by: -1) {
          guard !Task.isCancelled && self.isStudySessionActive else { break }
          self.countdownToNextCapture = countdown
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        }
        
        // Back to streaming phase for next capture
        self.studyCyclePhase = .streaming
      }
      
      // Cleanup when study session ends
      self.studyCyclePhase = .idle
      self.isStudySessionActive = false
    }
  }

  func startSession() async {
    // Reset to unlimited time when starting a new stream
    activeTimeLimit = .noLimit
    remainingTime = 0
    stopTimer()

    await streamSession.start()
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    stopTimer()
    await streamSession.stop()
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func setTimeLimit(_ limit: StreamTimeLimit) {
    activeTimeLimit = limit
    remainingTime = limit.durationInSeconds ?? 0

    if limit.isTimeLimited {
      startTimer()
    } else {
      stopTimer()
    }
  }

  func capturePhoto() {
    streamSession.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func startTimer() {
    stopTimer()
    timerTask = Task { @MainActor [weak self] in
      while let self, remainingTime > 0 {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        guard !Task.isCancelled else { break }
        remainingTime -= 1
      }
      if let self, !Task.isCancelled {
        await stopSession()
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}

