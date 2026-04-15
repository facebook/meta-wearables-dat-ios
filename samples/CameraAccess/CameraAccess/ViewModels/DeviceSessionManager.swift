/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MWDATCore
import SwiftUI

/// Manages DeviceSession lifecycle with 1:1 device-to-session mapping.
/// Handles device availability monitoring, session creation, and the glasses-side bug workaround.
@MainActor
final class DeviceSessionManager: ObservableObject {
  @Published private(set) var isReady: Bool = false
  @Published private(set) var hasActiveDevice: Bool = false

  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceSession: DeviceSession?
  private var deviceMonitorTask: Task<Void, Never>?
  private var stateObserverTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    startDeviceMonitoring()
  }

  deinit {
    deviceMonitorTask?.cancel()
    stateObserverTask?.cancel()
  }

  /// Returns a ready DeviceSession, creating one if needed.
  /// Waits for the session to reach .started state before returning.
  func getSession() async -> DeviceSession? {
    if let session = deviceSession, session.state == .started {
      // Ensure isReady reflects the actual state
      isReady = true
      return session
    }

    // Session needs to be created or is stopped
    if deviceSession?.state == .stopped {
      deviceSession = nil
    }

    guard deviceSession == nil else {
      // Session exists but not in .started state - wait or return nil
      return nil
    }

    do {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      deviceSession = session

      let stateStream = session.stateStream()
      try session.start()

      // Wait for .started state
      for await state in stateStream {
        if state == .started {
          isReady = true
          startStateObserver(for: session)
          return session
        } else if state == .stopped {
          isReady = false
          deviceSession = nil
          return nil
        }
      }
    } catch {
      isReady = false
      deviceSession = nil
    }
    return nil
  }

  // MARK: - Private

  private func startDeviceMonitoring() {
    deviceMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await device in deviceSelector.activeDeviceStream() {
        hasActiveDevice = device != nil
        if device != nil {
          _ = await getSession()
        } else {
          handleDeviceLost()
        }
      }
    }
  }

  private func startStateObserver(for session: DeviceSession) {
    stateObserverTask?.cancel()
    stateObserverTask = Task { [weak self] in
      for await state in session.stateStream() {
        guard let self else { return }
        if state == .started {
          isReady = true
        } else if state == .stopped {
          // DeviceSession.stopped is terminal - clean up
          isReady = false
          deviceSession = nil
          return
        }
      }
    }
  }

  private func handleDeviceLost() {
    stateObserverTask?.cancel()
    stateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isReady = false
  }
}
