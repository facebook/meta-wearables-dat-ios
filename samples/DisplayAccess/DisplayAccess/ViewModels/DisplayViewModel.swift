/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// DisplayViewModel.swift
//
// Manages the display session lifecycle: attaching to a display-capable device,
// sending views, and detaching. Uses DSPN's pending action pattern so that
// tapping "play" auto-attaches and sends the view once the display is ready.
//

import MWDATCore
import MWDATDisplay
import Observation
import SwiftUI

@MainActor
protocol DisplayDeviceSession: AnyObject {
  func stateStream() -> AsyncStream<DeviceSessionState>
  func errorStream() -> AsyncStream<DeviceSessionError>
  func start() throws(DeviceSessionError)
  func stop()
  func addDisplay() throws(DeviceSessionError) -> Display
}

extension DeviceSession: DisplayDeviceSession {}

@Observable
@MainActor
class DisplayViewModel {
  var isConnected: Bool = false
  private(set) var isSending: Bool = false
  private(set) var lastSentPreviewDeviceIdentifier: DeviceIdentifier?
  var errorMessage: String?
  var requiresDATAppUpdate: Bool = false

  @ObservationIgnored private let wearables: WearablesInterface
  @ObservationIgnored private let createSession: (DeviceSelector) throws -> any DisplayDeviceSession
  @ObservationIgnored private let waitForDisplayReadinessDeadline: @MainActor @Sendable () async throws -> Void
  @ObservationIgnored private var defaultDeviceSelector: DeviceSelector
  @ObservationIgnored private var deviceSession: (any DisplayDeviceSession)?
  @ObservationIgnored private var display: Display?
  @ObservationIgnored private var stateListenerToken: AnyListenerToken?
  @ObservationIgnored private var coreStateTask: Task<Void, Never>?
  @ObservationIgnored private var sessionErrorTask: Task<Void, Never>?
  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var displayReadinessTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateContinuation: AsyncStream<DisplayState>.Continuation?
  @ObservationIgnored private var pendingAction: (() async -> Void)?
  @ObservationIgnored private var activeDeviceIdentifier: DeviceIdentifier?

  init(
    wearables: WearablesInterface,
    defaultDeviceSelector: DeviceSelector? = nil,
    createSession: ((DeviceSelector) throws -> any DisplayDeviceSession)? = nil,
    waitForDisplayReadinessDeadline: @MainActor @Sendable @escaping () async throws -> Void = {
      try await Task.sleep(for: .seconds(10))
    }
  ) {
    self.wearables = wearables
    self.waitForDisplayReadinessDeadline = waitForDisplayReadinessDeadline
    self.defaultDeviceSelector =
      defaultDeviceSelector
      ?? AutoDeviceSelector(
        wearables: wearables,
        filter: { $0.supportsDisplay() }
      )
    self.createSession =
      createSession ?? { deviceSelector in
        try wearables.createSession(deviceSelector: deviceSelector)
      }
    observeRegistration()
  }

  isolated deinit {
    stateListenerToken = nil
    coreStateTask?.cancel()
    sessionErrorTask?.cancel()
    registrationTask?.cancel()
    displayReadinessTimeoutTask?.cancel()
    displayStateTask?.cancel()
  }

  // MARK: - Registration Observation

  private func observeRegistration() {
    registrationTask = Task { [weak self] in
      guard let wearables = self?.wearables else { return }
      for await state in wearables.registrationStateStream() {
        guard let self, !Task.isCancelled else { return }
        if state == .available || state == .unavailable {
          self.resetDisplaySession()
        }
      }
    }
  }

  private func resetDisplaySession() {
    detachFromDisplay()
    defaultDeviceSelector = AutoDeviceSelector(
      wearables: wearables,
      filter: { $0.supportsDisplay() }
    )
  }

  // MARK: - Public API

  /// Sends a display view to the glasses. Auto-attaches if not connected;
  /// the view is queued and sent once the display session is ready.
  func send(
    _ view: some DisplayableView,
    deviceIdentifier: DeviceIdentifier? = nil
  ) async {
    guard !isSending else { return }
    isSending = true
    errorMessage = nil

    if let display, isConnected {
      let targetDeviceIdentifier = deviceIdentifier ?? activeDeviceIdentifier
      if targetDeviceIdentifier != nil {
        lastSentPreviewDeviceIdentifier = nil
      }
      await doSend(view, on: display, targetDeviceIdentifier: targetDeviceIdentifier)
      return
    }

    if display != nil {
      do {
        try await stopSession()
      } catch {
        isSending = false
        return
      }
      isSending = true
    }

    if deviceIdentifier != nil {
      lastSentPreviewDeviceIdentifier = nil
    }

    // Store as pending action — will fire once display is ready
    let sendableView = view
    pendingAction = { [weak self] in
      guard let self, let cap = self.display else { return }
      await self.doSend(
        sendableView,
        on: cap,
        targetDeviceIdentifier: deviceIdentifier
      )
    }

    await attachToDisplay(deviceIdentifier: deviceIdentifier)
  }

  private func doSend(
    _ view: some DisplayableView,
    on capability: Display,
    targetDeviceIdentifier: DeviceIdentifier?
  ) async {
    defer { isSending = false }

    do {
      try await capability.send(view)
      if let targetDeviceIdentifier {
        lastSentPreviewDeviceIdentifier = targetDeviceIdentifier
      }
    } catch {
      if targetDeviceIdentifier != nil {
        lastSentPreviewDeviceIdentifier = nil
      }
      let message = (error as? DisplayError)?.description ?? error.localizedDescription
      errorMessage = message
    }
  }

  // MARK: - Session Management

  func attachToDisplay(deviceIdentifier: DeviceIdentifier? = nil) async {
    guard display == nil else { return }

    do {
      let deviceSelector: DeviceSelector =
        if let deviceIdentifier {
          SpecificDeviceSelector(device: deviceIdentifier)
        } else {
          defaultDeviceSelector
        }
      let devSession = try createSession(deviceSelector)
      activeDeviceIdentifier = deviceIdentifier
      deviceSession = devSession

      let stateStream = devSession.stateStream()
      let errorStream = devSession.errorStream()
      coreStateTask = Task { [weak self] in
        for await sessionState in stateStream {
          guard let self, !Task.isCancelled else { return }
          switch sessionState {
          case .started:
            self.requiresDATAppUpdate = false
            await self.setupDisplay(on: devSession)
          case .stopping:
            self.isConnected = false
          case .stopped:
            self.finishSessionTeardown()
          case .starting, .idle, .paused:
            break
          @unknown default:
            break
          }
        }
        guard let self, !Task.isCancelled else { return }
        self.finishSessionTeardown()
      }
      sessionErrorTask = Task { [weak self] in
        for await error in errorStream {
          guard let self, !Task.isCancelled else { return }
          self.handleSessionError(error)
        }
      }

      startDisplayReadinessTimeout(for: devSession)
      try devSession.start()
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      clearSessionState()
      requiresDATAppUpdate = true
      errorMessage = DeviceSessionError.datAppOnTheGlassesUpdateRequired.localizedDescription
    } catch {
      clearSessionState()
      requiresDATAppUpdate = false
      errorMessage = "Failed to create session: \(error.localizedDescription)"
    }
  }

  private func setupDisplay(on devSession: any DisplayDeviceSession) async {
    guard display == nil else { return }

    do {
      let capability = try devSession.addDisplay()

      let (stateStream, continuation) = AsyncStream.makeStream(of: DisplayState.self)
      displayStateContinuation = continuation
      stateListenerToken = capability.statePublisher.listen { state in
        continuation.yield(state)
      }

      displayStateTask = Task { [weak self] in
        for await state in stateStream {
          guard let self, !Task.isCancelled else { return }
          switch state {
          case .starting:
            break
          case .started:
            self.finishDisplayReadinessWait()
            self.isConnected = true
            // Execute pending action now that display is ready
            if let action = self.pendingAction {
              self.pendingAction = nil
              await action()
            }
          case .stopping:
            self.isConnected = false
          case .stopped:
            self.isConnected = false
            self.stateListenerToken = nil
            self.displayStateContinuation?.finish()
            self.displayStateContinuation = nil
            self.display = nil
            self.deviceSession?.stop()
            self.displayStateTask = nil
          }
        }
      }

      capability.start()
      display = capability
    } catch {
      devSession.stop()
      clearSessionState()
      errorMessage = "Failed to start display: \(error.localizedDescription)"
    }
  }

  private func startDisplayReadinessTimeout(for session: any DisplayDeviceSession) {
    displayReadinessTimeoutTask?.cancel()
    let waitForDeadline = waitForDisplayReadinessDeadline
    displayReadinessTimeoutTask = Task { [weak self] in
      do {
        try await waitForDeadline()
      } catch {
        return
      }
      guard let self else { return }
      guard self.deviceSession === session else { return }
      self.displayReadinessTimeoutTask = nil
      session.stop()
      self.clearSessionState()
      self.errorMessage = "Timed out waiting for the display to become ready."
    }
  }

  private func finishDisplayReadinessWait() {
    displayReadinessTimeoutTask?.cancel()
    displayReadinessTimeoutTask = nil
  }

  // MARK: - Car Maintenance

  func sendCarMaintenanceTutorialList(deviceIdentifier: DeviceIdentifier? = nil) async {
    await send(
      CarMaintenanceDisplay.tutorialList { [weak self] index in
        Task { @MainActor in
          await self?.sendCarMaintenanceTutorialDetail(tutorialIndex: index)
        }
      },
      deviceIdentifier: deviceIdentifier
    )
  }

  func sendCarMaintenanceTutorialDetail(tutorialIndex: Int) async {
    await send(
      CarMaintenanceDisplay.tutorialDetail(
        tutorialIndex: tutorialIndex,
        onBack: { [weak self] in
          Task { @MainActor in
            await self?.sendCarMaintenanceTutorialList()
          }
        },
        onStart: { [weak self] in
          Task { @MainActor in
            await self?.sendCarMaintenanceTutorialStep(tutorialIndex: tutorialIndex, stepIndex: 0)
          }
        }
      )
    )
  }

  func sendTutorialVideo(tutorialIndex: Int, stepIndex: Int) async {
    await send(CarMaintenanceDisplay.tutorialVideo())
    display?.onPlaybackEvent = { [weak self] event in
      if event.type == .ended {
        Task { @MainActor [weak self] in
          self?.display?.onPlaybackEvent = nil
          await self?.sendCarMaintenanceTutorialStep(
            tutorialIndex: tutorialIndex,
            stepIndex: stepIndex
          )
        }
      }
    }
  }

  func sendCarMaintenanceTutorialStep(tutorialIndex: Int, stepIndex: Int) async {
    let isLastStep = stepIndex == CarMaintenanceDisplay.tutorials[tutorialIndex].steps.count - 1
    await send(
      CarMaintenanceDisplay.tutorialStep(
        tutorialIndex: tutorialIndex,
        stepIndex: stepIndex,
        onPrevious: { [weak self] in
          Task { @MainActor in
            if stepIndex == 0 {
              await self?.sendCarMaintenanceTutorialDetail(tutorialIndex: tutorialIndex)
            } else {
              await self?.sendCarMaintenanceTutorialStep(
                tutorialIndex: tutorialIndex,
                stepIndex: stepIndex - 1
              )
            }
          }
        },
        onNext: { [weak self] in
          Task { @MainActor in
            if isLastStep {
              await self?.sendCarMaintenanceTutorialList()
            } else {
              await self?.sendCarMaintenanceTutorialStep(
                tutorialIndex: tutorialIndex,
                stepIndex: stepIndex + 1
              )
            }
          }
        },
        onWatchVideo: { [weak self] in
          Task { @MainActor in
            await self?.sendTutorialVideo(tutorialIndex: tutorialIndex, stepIndex: stepIndex)
          }
        }
      )
    )
  }

  func detachFromDisplay() {
    if let display {
      display.stop()
    } else {
      deviceSession?.stop()
    }
  }

  func stopSession() async throws {
    pendingAction = nil
    errorMessage = nil
    guard let deviceSession else {
      clearSessionState()
      return
    }

    let stateStream = deviceSession.stateStream()
    detachFromDisplay()

    for await state in stateStream {
      try Task.checkCancellation()
      guard state == .stopped else { continue }
      finishSessionTeardown()
      return
    }

    try Task.checkCancellation()
    finishSessionTeardown()
  }

  private func finishSessionTeardown() {
    clearSessionState()
  }

  private func clearSessionState() {
    isConnected = false
    isSending = false
    lastSentPreviewDeviceIdentifier = nil
    activeDeviceIdentifier = nil
    pendingAction = nil
    finishDisplayReadinessWait()
    displayStateTask?.cancel()
    displayStateTask = nil
    displayStateContinuation?.finish()
    displayStateContinuation = nil
    stateListenerToken = nil
    display = nil
    sessionErrorTask?.cancel()
    sessionErrorTask = nil
    deviceSession = nil
    coreStateTask?.cancel()
    coreStateTask = nil
  }

  private func handleSessionError(_ error: DeviceSessionError) {
    isSending = false
    if activeDeviceIdentifier != nil {
      lastSentPreviewDeviceIdentifier = nil
    }
    requiresDATAppUpdate = error == .datAppOnTheGlassesUpdateRequired
    errorMessage = error.localizedDescription
  }
}
