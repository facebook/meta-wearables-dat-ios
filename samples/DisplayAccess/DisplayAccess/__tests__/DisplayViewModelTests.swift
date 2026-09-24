/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import DisplayAccessSwift
import Foundation
@_spi(Testing) import MWDATCore
import MWDATDisplay
import Testing

private final class StubWearables: WearablesInterface, Sendable {
  let registrationState: RegistrationState = .available
  let devices: [DeviceIdentifier] = []

  func addRegistrationStateListener(
    _ listener: @Sendable @escaping (RegistrationState) -> Void
  ) -> AnyListenerToken {
    fatalError("Not used by these tests")
  }

  func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { $0.finish() }
  }

  func startRegistration() async throws(RegistrationError) {
    fatalError("Not used by these tests")
  }

  func handleUrl(_ url: URL) async throws(WearablesHandleURLError) -> Bool {
    fatalError("Not used by these tests")
  }

  func startUnregistration() async throws(UnregistrationError) {
    fatalError("Not used by these tests")
  }

  func openFirmwareUpdate() async throws(NavigationError) {
    fatalError("Not used by these tests")
  }

  func openDATGlassesAppUpdate() async throws(NavigationError) {
    fatalError("Not used by these tests")
  }

  func addDevicesListener(
    _ listener: @Sendable @escaping ([DeviceIdentifier]) -> Void
  ) -> AnyListenerToken {
    fatalError("Not used by these tests")
  }

  func devicesStream() -> AsyncStream<[DeviceIdentifier]> {
    AsyncStream { $0.finish() }
  }

  func deviceForIdentifier(_ identifier: DeviceIdentifier) -> Device? {
    nil
  }

  func checkPermissionStatus(
    _ permission: Permission
  ) async throws(PermissionError) -> PermissionStatus {
    fatalError("Not used by these tests")
  }

  func requestPermission(
    _ permission: Permission
  ) async throws(PermissionError) -> PermissionStatus {
    fatalError("Not used by these tests")
  }

  func createSession(
    deviceSelector: DeviceSelector
  ) throws(DeviceSessionError) -> DeviceSession {
    fatalError("Not used by these tests")
  }
}

@MainActor
private final class StalledDisplayDeviceSession: DisplayDeviceSession {
  private let states: AsyncStream<DeviceSessionState>
  private let stateContinuation: AsyncStream<DeviceSessionState>.Continuation
  private let errors: AsyncStream<DeviceSessionError>
  private let errorContinuation: AsyncStream<DeviceSessionError>.Continuation
  private(set) var didStop = false

  init() {
    (states, stateContinuation) = AsyncStream.makeStream(of: DeviceSessionState.self)
    (errors, errorContinuation) = AsyncStream.makeStream(of: DeviceSessionError.self)
  }

  func stateStream() -> AsyncStream<DeviceSessionState> {
    states
  }

  func errorStream() -> AsyncStream<DeviceSessionError> {
    errors
  }

  func start() throws(DeviceSessionError) {}

  func stop() {
    didStop = true
    stateContinuation.finish()
    errorContinuation.finish()
  }

  func addDisplay() throws(DeviceSessionError) -> Display {
    throw .sessionIdle
  }
}

@Suite
@MainActor
struct DisplayViewModelTests {
  @Test
  func phonePreviewTryItTargetsPairedDevice() async {
    var selectedDevice: DeviceIdentifier?
    let sut = DisplayViewModel(
      wearables: StubWearables(),
      createSession: { selector in
        selectedDevice = selector.activeDevice
        throw DeviceSessionError.noEligibleDevice
      }
    )

    await sut.sendCarMaintenanceTutorialList(deviceIdentifier: "phone-preview")

    #expect(selectedDevice == "phone-preview")
    #expect(!sut.isSending)
    #expect(sut.lastSentPreviewDeviceIdentifier == nil)
  }

  @Test
  func tryItWithoutPhonePreviewKeepsAutoSelection() async {
    var usesAutoSelector = false
    let sut = DisplayViewModel(
      wearables: StubWearables(),
      createSession: { selector in
        usesAutoSelector = selector is AutoDeviceSelector
        throw DeviceSessionError.noEligibleDevice
      }
    )

    await sut.sendCarMaintenanceTutorialList()

    #expect(usesAutoSelector)
  }

  @Test
  func tryItWithoutPhonePreviewUsesRetainedDefaultSelector() async {
    let retainedSelector = SpecificDeviceSelector(device: "glasses")
    var selectedDevice: DeviceIdentifier?
    let sut = DisplayViewModel(
      wearables: StubWearables(),
      defaultDeviceSelector: retainedSelector,
      createSession: { selector in
        selectedDevice = selector.activeDevice
        throw DeviceSessionError.noEligibleDevice
      }
    )

    await sut.sendCarMaintenanceTutorialList()

    #expect(selectedDevice == "glasses")
  }

  @Test
  func stopSessionWaitsForDeviceSessionToStop() async throws {
    let deviceSession = DeviceSession.makeStartedFake()
    let sut = DisplayViewModel(
      wearables: StubWearables(),
      createSession: { _ in deviceSession }
    )
    await sut.attachToDisplay()

    try await sut.stopSession()

    #expect(deviceSession.state == .stopped)
    #expect(!sut.isSending)
    #expect(sut.lastSentPreviewDeviceIdentifier == nil)
  }

  @Test
  func stalledSessionReleasesPendingSendAfterDeadline() async {
    let deviceSession = StalledDisplayDeviceSession()
    let sut = DisplayViewModel(
      wearables: StubWearables(),
      createSession: { _ in deviceSession },
      waitForDisplayReadinessDeadline: {}
    )

    await sut.sendCarMaintenanceTutorialList()
    for _ in 0..<10 {
      await Task.yield()
    }

    #expect(!sut.isSending)
    #expect(deviceSession.didStop)
    #expect(sut.errorMessage == "Timed out waiting for the display to become ready.")
  }
}
