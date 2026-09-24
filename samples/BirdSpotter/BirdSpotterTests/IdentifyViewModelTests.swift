/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The Identify tab's access gate: when the page is the permission wall and when it opens, and
/// that the view model reads status fresh — including the change made in Settings and brought
/// back on the next foreground.
///
/// The gate rule is pure `IdentifyUiState`, so it needs no view model; the read path drives the
/// real `IdentifyViewModel` over a `FakePermissions`. Requesting the system prompt is not
/// tested here: it is the platform plumbing the surface deliberately keeps off
/// `PermissionsController`.
///
/// Scenario names are fixed by the testing-parity rule.
@MainActor
@Suite("IdentifyViewModel")
struct IdentifyViewModelTests {

  // MARK: - The gate

  @Test func allGranted_whenEveryPermissionGranted_isTrue() {
    let state = IdentifyUiState(
      cameraStatus: .granted, microphoneStatus: .granted, locationStatus: .granted
    )

    #expect(state.allGranted)
  }

  @Test func allGranted_whenLocationMissing_isFalse() {
    let state = IdentifyUiState(
      cameraStatus: .granted, microphoneStatus: .granted, locationStatus: .notDetermined
    )

    #expect(!state.allGranted)
  }

  @Test func allGranted_whenCameraMissing_isFalse() {
    let state = IdentifyUiState(
      cameraStatus: .denied, microphoneStatus: .granted, locationStatus: .granted
    )

    #expect(!state.allGranted)
  }

  @Test func allGranted_whenMicrophoneMissing_isFalse() {
    let state = IdentifyUiState(
      cameraStatus: .granted, microphoneStatus: .notDetermined, locationStatus: .granted
    )

    #expect(!state.allGranted)
  }

  // MARK: - Reading status

  @Test func refresh_readsEachPermissionsStatus() {
    let permissions = FakePermissions(camera: .granted, microphone: .denied, location: .notDetermined)
    let model = IdentifyViewModel(permissions: permissions)

    #expect(model.uiState.cameraStatus == .granted)
    #expect(model.uiState.microphoneStatus == .denied)
    #expect(model.uiState.locationStatus == .notDetermined)
  }

  @Test func refresh_picksUpAStatusThatChangedWhileAway() {
    let permissions = FakePermissions(camera: .granted, microphone: .granted, location: .notDetermined)
    let model = IdentifyViewModel(permissions: permissions)
    #expect(!model.uiState.allGranted)

    // The user grants location in Settings and returns; the screen calls refresh on resume.
    permissions.location = .granted
    model.refresh()

    #expect(model.uiState.allGranted)
  }

  @Test func openSettings_isRoutedToTheController() {
    let permissions = FakePermissions()
    let model = IdentifyViewModel(permissions: permissions)

    model.openSettings()

    #expect(permissions.openedSettings)
  }
}

/// The first hand-written fake in the suite: a `PermissionsController` whose answers are set by
/// the test and can change between reads.
@MainActor
private final class FakePermissions: PermissionsController {
  var camera: PermissionStatus
  var microphone: PermissionStatus
  var location: PermissionStatus
  private(set) var openedSettings = false

  init(
    camera: PermissionStatus = .notDetermined,
    microphone: PermissionStatus = .notDetermined,
    location: PermissionStatus = .notDetermined
  ) {
    self.camera = camera
    self.microphone = microphone
    self.location = location
  }

  func status(_ permission: Permission) -> PermissionStatus {
    switch permission {
    case .camera: camera
    case .microphone: microphone
    case .location: location
    }
  }

  func openAppSettings() { openedSettings = true }
}
