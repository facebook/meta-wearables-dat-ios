/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import DisplayAccessSwift
import Foundation
import MWDATCore
import MWDATMockDevice
import Observation
import Testing
import UIKit

private struct StubDisplayKit: MockDisplayKit {
  func sendClick(identifier: String) -> Bool {
    true
  }

  @MainActor
  func createPreviewView() -> UIView {
    UIView()
  }
}

@MainActor
private final class StubPhonePreviewManager: PhonePreviewManaging {
  enum Event: Equatable {
    case stopSession
    case enable
    case pair
    case powerOn
    case don
    case waitUntilDeviceIsReady
    case startChromeServer
    case stopChromeServer
    case unpair
    case disable
  }

  enum StubError: Error {
    case pairingFailed
    case deviceReadinessTimedOut
    case serverStartFailed
  }

  var events: [Event] = []
  var shouldFailPairing = false
  var shouldFailDeviceReadiness = false
  var shouldFailServerStart = false
  var serverPort: UInt16 = 15556

  func enable() {
    events.append(.enable)
  }

  func pairGlasses() throws -> PhonePreviewDevice {
    events.append(.pair)
    if shouldFailPairing {
      throw StubError.pairingFailed
    }
    return PhonePreviewDevice(
      deviceIdentifier: "phone-preview",
      display: StubDisplayKit(),
      powerOn: { [weak self] in self?.events.append(.powerOn) },
      don: { [weak self] in self?.events.append(.don) },
      unpair: { [weak self] in self?.events.append(.unpair) }
    )
  }

  func waitUntilDeviceIsReady(_ deviceIdentifier: DeviceIdentifier) async throws {
    events.append(.waitUntilDeviceIsReady)
    if shouldFailDeviceReadiness {
      throw StubError.deviceReadinessTimedOut
    }
  }

  func startChromePreviewServer() async throws -> UInt16 {
    events.append(.startChromeServer)
    if shouldFailServerStart {
      throw StubError.serverStartFailed
    }
    return serverPort
  }

  func stopChromePreviewServer() async {
    events.append(.stopChromeServer)
  }

  func disable() {
    events.append(.disable)
  }
}

@Suite
@MainActor
struct PhonePreviewViewModelTests {
  private enum StopError: Error {
    case failed
  }

  @Test
  func enablingInAppPreviewStopsExistingSessionBeforePairing() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)

    try await sut.setDeveloperPreviewMode(.inApp) {
      manager.events.append(.stopSession)
    }

    #expect(
      manager.events == [
        .stopSession,
        .enable,
        .pair,
        .powerOn,
        .don,
        .waitUntilDeviceIsReady,
      ]
    )
    #expect(sut.developerPreviewMode == .inApp)
    #expect(sut.isEnabled)
    #expect(sut.deviceIdentifier == "phone-preview")
    #expect(sut.display != nil)
    #expect(sut.inAppPreviewDisplay != nil)

    manager.events.removeAll()
    let wasAlreadyPrepared = try await sut.setDeveloperPreviewMode(.inApp) {
      manager.events.append(.stopSession)
    }
    #expect(wasAlreadyPrepared)
    #expect(manager.events.isEmpty)
  }

  @Test
  func concurrentDeveloperPreviewTransitionIsRejected() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    let (transitionStarted, transitionStartedContinuation) =
      AsyncStream.makeStream(of: Void.self)
    let (releaseTransition, releaseTransitionContinuation) =
      AsyncStream.makeStream(of: Void.self)
    let transition = Task { @MainActor in
      try await sut.setDeveloperPreviewMode(.inApp) {
        transitionStartedContinuation.yield()
        for await _ in releaseTransition {
          break
        }
      }
    }

    for await _ in transitionStarted {
      break
    }
    let didAcceptConcurrentTransition = try await sut.setDeveloperPreviewMode(nil) {}
    releaseTransitionContinuation.yield()
    releaseTransitionContinuation.finish()
    transitionStartedContinuation.finish()

    #expect(!didAcceptConcurrentTransition)
    #expect(try await transition.value)
  }

  @Test
  func disablingDeveloperPreviewStopsSessionBeforeUnpairing() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    try await sut.setDeveloperPreviewMode(.inApp) {}
    manager.events.removeAll()

    try await sut.setDeveloperPreviewMode(nil) {
      manager.events.append(.stopSession)
    }

    #expect(manager.events == [.stopSession, .unpair, .disable])
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(sut.deviceIdentifier == nil)
    #expect(sut.display == nil)
  }

  @Test
  func enablingChromePreviewCreatesDeviceAndStartsServer() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)

    try await sut.setDeveloperPreviewMode(.chrome) {
      manager.events.append(.stopSession)
    }

    #expect(
      manager.events == [
        .stopSession,
        .enable,
        .pair,
        .powerOn,
        .don,
        .waitUntilDeviceIsReady,
        .startChromeServer,
      ]
    )
    #expect(sut.developerPreviewMode == .chrome)
    #expect(sut.isEnabled)
    #expect(sut.inAppPreviewDisplay == nil)
    #expect(
      sut.chromePreviewURL?.absoluteString
        == "http://127.0.0.1:15556/"
    )
  }

  @Test
  func switchingToInAppPreviewStopsServerAndKeepsDevice() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    try await sut.setDeveloperPreviewMode(.chrome) {}
    manager.events.removeAll()

    try await sut.setDeveloperPreviewMode(.inApp) {
      manager.events.append(.stopSession)
    }

    #expect(manager.events == [.stopSession, .stopChromeServer])
    #expect(sut.developerPreviewMode == .inApp)
    #expect(sut.isEnabled)
    #expect(sut.chromePreviewURL == nil)
    #expect(sut.inAppPreviewDisplay != nil)
  }

  @Test
  func disablingDeveloperPreviewStopsChromeServerBeforeUnpairing() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    try await sut.setDeveloperPreviewMode(.chrome) {}
    manager.events.removeAll()

    try await sut.setDeveloperPreviewMode(nil) {
      manager.events.append(.stopSession)
    }

    #expect(
      manager.events == [
        .stopSession,
        .stopChromeServer,
        .unpair,
        .disable,
      ]
    )
  }

  @Test
  func chromeServerStartFailureRollsBackNewPreviewDevice() async {
    let manager = StubPhonePreviewManager()
    manager.shouldFailServerStart = true
    let sut = PhonePreviewViewModel(manager: manager)

    do {
      try await sut.setDeveloperPreviewMode(.chrome) {
        manager.events.append(.stopSession)
      }
      Issue.record("Expected server start to fail")
    } catch StubPhonePreviewManager.StubError.serverStartFailed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(
      manager.events == [
        .stopSession,
        .enable,
        .pair,
        .powerOn,
        .don,
        .waitUntilDeviceIsReady,
        .startChromeServer,
        .unpair,
        .disable,
      ]
    )
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(!sut.isChanging)
    #expect(sut.chromePreviewURL == nil)
  }

  @Test
  func chromeServerStartFailureClearsExistingPreviewDevice() async {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    try? await sut.setDeveloperPreviewMode(.inApp) {}
    manager.events.removeAll()
    manager.shouldFailServerStart = true

    do {
      try await sut.setDeveloperPreviewMode(.chrome) {
        manager.events.append(.stopSession)
      }
      Issue.record("Expected server start to fail")
    } catch StubPhonePreviewManager.StubError.serverStartFailed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(manager.events == [.stopSession, .startChromeServer, .unpair, .disable])
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(!sut.isChanging)
    #expect(sut.chromePreviewURL == nil)
    #expect(sut.inAppPreviewDisplay == nil)
  }

  @Test
  func pairingFailureDisablesMockDeviceKitAndClearsState() async {
    let manager = StubPhonePreviewManager()
    manager.shouldFailPairing = true
    let sut = PhonePreviewViewModel(manager: manager)

    do {
      try await sut.setDeveloperPreviewMode(.inApp) {
        manager.events.append(.stopSession)
      }
      Issue.record("Expected pairing to fail")
    } catch StubPhonePreviewManager.StubError.pairingFailed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(manager.events == [.stopSession, .enable, .pair, .disable])
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(sut.deviceIdentifier == nil)
    #expect(sut.display == nil)
  }

  @Test
  func deviceReadinessFailureDisablesMockDeviceKitAndClearsState() async {
    let manager = StubPhonePreviewManager()
    manager.shouldFailDeviceReadiness = true
    let sut = PhonePreviewViewModel(manager: manager)

    do {
      try await sut.setDeveloperPreviewMode(.inApp) {
        manager.events.append(.stopSession)
      }
      Issue.record("Expected device readiness to fail")
    } catch StubPhonePreviewManager.StubError.deviceReadinessTimedOut {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(
      manager.events == [
        .stopSession,
        .enable,
        .pair,
        .powerOn,
        .don,
        .waitUntilDeviceIsReady,
        .unpair,
        .disable,
      ]
    )
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(sut.deviceIdentifier == nil)
    #expect(sut.display == nil)
  }

  @Test
  func stopFailureAbortsPairingAndRestoresChangingState() async {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)

    do {
      try await sut.setDeveloperPreviewMode(.inApp) {
        throw StopError.failed
      }
      Issue.record("Expected session stop to fail")
    } catch StopError.failed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(manager.events.isEmpty)
    #expect(!sut.isChanging)
    #expect(sut.developerPreviewMode == nil)
    #expect(!sut.isEnabled)
    #expect(sut.deviceIdentifier == nil)
    #expect(sut.display == nil)
  }

  @Test
  func stopFailurePreservesActivePreviewWhenDisabling() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)
    try await sut.setDeveloperPreviewMode(.inApp) {}
    manager.events.removeAll()

    do {
      try await sut.setDeveloperPreviewMode(nil) {
        throw StopError.failed
      }
      Issue.record("Expected session stop to fail")
    } catch StopError.failed {
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(manager.events.isEmpty)
    #expect(!sut.isChanging)
    #expect(sut.developerPreviewMode == .inApp)
    #expect(sut.isEnabled)
    #expect(sut.deviceIdentifier == "phone-preview")
    #expect(sut.inAppPreviewDisplay != nil)
  }

  @Test
  func failedDeveloperPreviewCanBeRetriedWithoutChangingMode() async throws {
    let manager = StubPhonePreviewManager()
    manager.shouldFailServerStart = true
    let sut = PhonePreviewViewModel(manager: manager)
    try? await sut.setDeveloperPreviewMode(.chrome) {}
    manager.events.removeAll()
    manager.shouldFailServerStart = false

    try await sut.setDeveloperPreviewMode(.chrome) {
      manager.events.append(.stopSession)
    }

    #expect(
      manager.events == [
        .stopSession,
        .enable,
        .pair,
        .powerOn,
        .don,
        .waitUntilDeviceIsReady,
        .startChromeServer,
      ]
    )
    #expect(sut.developerPreviewMode == .chrome)
    #expect(sut.chromePreviewURL != nil)
  }

  @Test
  func previewOutputsParticipateInObservation() async throws {
    let manager = StubPhonePreviewManager()
    let sut = PhonePreviewViewModel(manager: manager)

    try await confirmation("Preview output changed") { outputChanged in
      withObservationTracking {
        _ = sut.developerPreviewMode
        _ = sut.deviceIdentifier
        _ = sut.display
      } onChange: {
        outputChanged()
      }

      try await sut.setDeveloperPreviewMode(.inApp) {}
    }
  }
}
