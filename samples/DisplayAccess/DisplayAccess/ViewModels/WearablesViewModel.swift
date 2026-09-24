/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// WearablesViewModel.swift
//
// View model managing DAT SDK registration, device state, and per-device link
// state listeners. Each connected device gets a DeviceItemState that tracks
// its link state in real time via addLinkStateListener.
//

import Foundation
import MWDATCore
import MWDATMockDevice
import OSLog
import Observation
import SwiftUI

private let phonePreviewDeviceName = "Phone preview"

enum DeveloperPreviewMode: CaseIterable, Hashable, Identifiable {
  case chrome
  case inApp

  var id: Self { self }
}

enum PhonePreviewError: LocalizedError {
  case deviceReadinessTimedOut

  var errorDescription: String? {
    switch self {
    case .deviceReadinessTimedOut:
      "Timed out waiting for the phone preview device to connect."
    }
  }
}

@MainActor
protocol PhonePreviewManaging {
  func enable()
  func pairGlasses() throws -> PhonePreviewDevice
  func waitUntilDeviceIsReady(_ deviceIdentifier: DeviceIdentifier) async throws
  func startChromePreviewServer() async throws -> UInt16
  func stopChromePreviewServer() async
  func disable()
}

@MainActor
struct PhonePreviewDevice {
  let deviceIdentifier: DeviceIdentifier
  let display: any MockDisplayKit
  let powerOn: () -> Void
  let don: () -> Void
  let unpair: () -> Void
}

@MainActor
final class LivePhonePreviewManager: PhonePreviewManaging {
  private let mockDeviceKit: MockDeviceKitInterface
  private let wearables: WearablesInterface

  init(
    mockDeviceKit: MockDeviceKitInterface,
    wearables: WearablesInterface
  ) {
    self.mockDeviceKit = mockDeviceKit
    self.wearables = wearables
  }

  convenience init() {
    self.init(
      mockDeviceKit: MockDeviceKit.shared,
      wearables: Wearables.shared
    )
  }

  func enable() {
    mockDeviceKit.enable()
  }

  func pairGlasses() throws -> PhonePreviewDevice {
    let device = try mockDeviceKit.pairGlasses(model: .metaRayBanDisplay)
    return PhonePreviewDevice(
      deviceIdentifier: device.deviceIdentifier,
      display: device.services.display,
      powerOn: device.powerOn,
      don: device.don,
      unpair: { [mockDeviceKit] in mockDeviceKit.unpairDevice(device) }
    )
  }

  func waitUntilDeviceIsReady(_ deviceIdentifier: DeviceIdentifier) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))

    while !isDeviceReady(deviceIdentifier) {
      guard clock.now < deadline else {
        throw PhonePreviewError.deviceReadinessTimedOut
      }
      try await clock.sleep(for: .milliseconds(50))
    }
  }

  private func isDeviceReady(_ deviceIdentifier: DeviceIdentifier) -> Bool {
    guard let device = wearables.deviceForIdentifier(deviceIdentifier) else {
      return false
    }
    return device.linkState == .connected
      && device.compatibility() == .compatible
  }

  func startChromePreviewServer() async throws -> UInt16 {
    try await mockDeviceKit.startTestServer(port: 9000)
  }

  func stopChromePreviewServer() async {
    await mockDeviceKit.stopTestServer()
  }

  func disable() {
    mockDeviceKit.disable()
  }
}

@Observable
@MainActor
final class PhonePreviewViewModel {
  private(set) var developerPreviewMode: DeveloperPreviewMode?
  private(set) var isChanging = false
  private(set) var display: (any MockDisplayKit)?
  private(set) var deviceIdentifier: DeviceIdentifier?
  private(set) var chromePreviewURL: URL?

  var isEnabled: Bool { device != nil }
  var inAppPreviewDisplay: (any MockDisplayKit)? {
    developerPreviewMode == .inApp ? display : nil
  }

  @ObservationIgnored private let manager: any PhonePreviewManaging
  @ObservationIgnored private var device: PhonePreviewDevice?

  init(manager: any PhonePreviewManaging) {
    self.manager = manager
  }

  convenience init() {
    self.init(manager: LivePhonePreviewManager())
  }

  func setDeveloperPreviewMode(
    _ mode: DeveloperPreviewMode?,
    stopDisplaySession: @escaping @MainActor () async throws -> Void
  ) async throws -> Bool {
    guard !isChanging else { return false }
    guard mode != developerPreviewMode || !isPrepared(mode) else { return true }
    isChanging = true
    defer { isChanging = false }

    try await stopDisplaySession()

    switch mode {
    case nil:
      await stopChromePreviewIfNeeded()
      disablePhonePreviewIfNeeded()
      developerPreviewMode = nil
    case .inApp:
      await stopChromePreviewIfNeeded()
      try await enablePhonePreviewIfNeeded()
      developerPreviewMode = .inApp
    case .chrome:
      try await enablePhonePreviewIfNeeded()
      do {
        try await startChromePreviewIfNeeded()
        developerPreviewMode = .chrome
      } catch {
        disablePhonePreviewIfNeeded()
        developerPreviewMode = nil
        throw error
      }
    }

    return true
  }

  private func isPrepared(_ mode: DeveloperPreviewMode?) -> Bool {
    switch mode {
    case nil:
      return device == nil && chromePreviewURL == nil
    case .inApp:
      return device != nil && chromePreviewURL == nil
    case .chrome:
      return device != nil && chromePreviewURL != nil
    }
  }

  private func enablePhonePreviewIfNeeded() async throws {
    guard device == nil else { return }

    manager.enable()
    var pairedDevice: PhonePreviewDevice?
    do {
      let device = try manager.pairGlasses()
      pairedDevice = device
      device.powerOn()
      device.don()
      try await manager.waitUntilDeviceIsReady(device.deviceIdentifier)
      self.device = device
      deviceIdentifier = device.deviceIdentifier
      display = device.display
    } catch {
      pairedDevice?.unpair()
      clearDevice()
      manager.disable()
      throw error
    }
  }

  private func startChromePreviewIfNeeded() async throws {
    guard chromePreviewURL == nil else { return }
    let port = try await manager.startChromePreviewServer()
    guard let url = makeChromePreviewURL(port: port) else {
      await manager.stopChromePreviewServer()
      throw URLError(.badURL)
    }
    chromePreviewURL = url
  }

  private func stopChromePreviewIfNeeded() async {
    guard chromePreviewURL != nil else { return }
    await manager.stopChromePreviewServer()
    chromePreviewURL = nil
  }

  private func makeChromePreviewURL(port: UInt16) -> URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    components.path = "/"
    return components.url
  }

  private func disablePhonePreviewIfNeeded() {
    guard device != nil else { return }
    device?.unpair()
    clearDevice()
    manager.disable()
  }

  private func clearDevice() {
    device = nil
    deviceIdentifier = nil
    display = nil
    chromePreviewURL = nil
  }
}

// MARK: - DeviceItemState

@Observable
@MainActor
class DeviceItemState: Identifiable {
  let identifier: DeviceIdentifier
  var linkState: LinkState
  var compatibility: Compatibility
  var deviceName: String
  var deviceTypeValue: String
  var isPhonePreview: Bool

  @ObservationIgnored private var linkStateToken: AnyListenerToken?

  nonisolated var id: DeviceIdentifier { identifier }

  init(device: Device, isPhonePreview: Bool = false) {
    self.identifier = device.identifier
    self.isPhonePreview = isPhonePreview
    self.deviceName = isPhonePreview ? phonePreviewDeviceName : device.nameOrId()
    self.deviceTypeValue = device.deviceType().rawValue
    self.linkState = device.linkState
    self.compatibility = device.compatibility()

    linkStateToken = device.addLinkStateListener { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.linkState = device.linkState
        self.compatibility = device.compatibility()
        if !self.isPhonePreview {
          self.deviceName = device.nameOrId()
        }
      }
    }
  }
}

// MARK: - WearablesViewModel

@Observable
@MainActor
class WearablesViewModel {
  private static let logger = Logger(
    subsystem: "com.meta.wearables.DisplayAccess",
    category: "PhonePreview"
  )

  var deviceItemStates: [DeviceItemState] = []
  var registrationState: RegistrationState
  var showError: Bool = false
  var errorMessage: String = ""
  var requiresFirmwareUpdate: Bool = false
  var developerPreviewErrorMessage: String?
  let phonePreview: PhonePreviewViewModel

  var developerPreviewMode: DeveloperPreviewMode? { phonePreview.developerPreviewMode }
  var isDeveloperPreviewChanging: Bool { phonePreview.isChanging }
  var chromePreviewURL: URL? { phonePreview.chromePreviewURL }
  var phonePreviewDisplay: (any MockDisplayKit)? { phonePreview.inAppPreviewDisplay }
  var phonePreviewDeviceIdentifier: DeviceIdentifier? { phonePreview.deviceIdentifier }

  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var deviceStreamTask: Task<Void, Never>?
  private var deviceCompatibility: [DeviceIdentifier: Compatibility] = [:]
  private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]
  let wearables: WearablesInterface

  init(
    wearables: WearablesInterface,
    phonePreview: PhonePreviewViewModel
  ) {
    self.wearables = wearables
    self.registrationState = wearables.registrationState
    self.phonePreview = phonePreview
    observeWearables()
  }

  convenience init(wearables: WearablesInterface) {
    self.init(
      wearables: wearables,
      phonePreview: PhonePreviewViewModel()
    )
  }

  private func observeWearables() {
    deviceStreamTask = Task { [weak self] in
      guard let wearables = self?.wearables else { return }
      for await deviceIds in wearables.devicesStream() {
        guard let self else { return }
        self.deviceItemStates = deviceIds.compactMap { deviceId in
          guard let device = wearables.deviceForIdentifier(deviceId) else { return nil }
          let isPhonePreview = deviceId == self.phonePreview.deviceIdentifier
          return DeviceItemState(device: device, isPhonePreview: isPhonePreview)
        }
        self.monitorDeviceCompatibility(deviceIds: deviceIds)
      }
    }

    registrationTask = Task { [weak self] in
      guard let wearables = self?.wearables else { return }
      for await state in wearables.registrationStateStream() {
        guard let self else { return }
        self.registrationState = state
      }
    }
  }

  isolated deinit {
    registrationTask?.cancel()
    deviceStreamTask?.cancel()
    for token in compatibilityListenerTokens.values {
      Task { await token.cancel() }
    }
  }

  func connectGlasses() async {
    guard registrationState != .registering else { return }
    do {
      try await wearables.startRegistration()
    } catch {
      showError(error.description)
    }
  }

  func disconnectGlasses() async {
    do {
      try await wearables.startUnregistration()
    } catch {
      showError(error.description)
    }
  }

  func openFirmwareUpdate() {
    Task {
      do {
        try await wearables.openFirmwareUpdate()
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  func openDATGlassesAppUpdate() {
    Task {
      do {
        try await wearables.openDATGlassesAppUpdate()
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  func showError(_ error: String) {
    errorMessage = error
    showError = true
  }

  func dismissError() {
    showError = false
  }

  func setDeveloperPreviewMode(
    _ mode: DeveloperPreviewMode?,
    stopDisplaySession: @escaping @MainActor () async throws -> Void
  ) async -> Bool {
    developerPreviewErrorMessage = nil
    do {
      return try await phonePreview.setDeveloperPreviewMode(
        mode,
        stopDisplaySession: stopDisplaySession
      )
    } catch {
      Self.logger.error(
        "Failed to update developer preview: \(error.localizedDescription, privacy: .public)"
      )
      developerPreviewErrorMessage = error.localizedDescription
      return false
    }
  }

  /// Keeps firmware update state in sync with the current device list.
  /// Compatibility listeners are tied to `Device` instances, so they must be
  /// canceled when an identifier leaves the stream and recreated if it returns.
  private func monitorDeviceCompatibility(deviceIds: [DeviceIdentifier]) {
    let deviceSet = Set(deviceIds)
    let removedDeviceIds = compatibilityListenerTokens.keys.filter { !deviceSet.contains($0) }

    // The devices stream only emits identifiers. Cancel removed listener tokens
    // explicitly so a forgotten and rediscovered device gets a fresh listener.
    for deviceId in removedDeviceIds {
      if let token = compatibilityListenerTokens.removeValue(forKey: deviceId) {
        Task { await token.cancel() }
      }
      deviceCompatibility[deviceId] = nil
    }
    updateRequiresFirmwareUpdate()

    // Add listeners only for new identifiers; existing tokens keep reporting
    // compatibility changes until the identifier leaves the device stream.
    for deviceId in deviceIds {
      guard compatibilityListenerTokens[deviceId] == nil else { continue }
      guard let device = wearables.deviceForIdentifier(deviceId) else { continue }
      deviceCompatibility[deviceId] = device.compatibility()
      updateRequiresFirmwareUpdate()

      let token = device.addCompatibilityListener { [weak self] compatibility in
        Task { [weak self] in
          await self?.handleCompatibilityChange(compatibility, deviceId: deviceId)
        }
      }
      compatibilityListenerTokens[deviceId] = token
    }
  }

  private func updateRequiresFirmwareUpdate() {
    requiresFirmwareUpdate = deviceCompatibility.values.contains(.deviceUpdateRequired)
  }

  private func handleCompatibilityChange(
    _ compatibility: Compatibility,
    deviceId: DeviceIdentifier
  ) {
    deviceCompatibility[deviceId] = compatibility
    deviceItemStates.first { $0.identifier == deviceId }?.compatibility = compatibility
    updateRequiresFirmwareUpdate()
  }
}
