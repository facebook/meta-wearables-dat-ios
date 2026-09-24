/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyViewModel.swift
//  birdspotter
//

import Foundation

/// What the Identify landing renders: the three permission statuses, and the single gate they
/// open. The page is all-or-nothing — until every permission is granted it is the access gate
/// and nothing else; once they all are, the gate gives way to the two ways in.
struct IdentifyUiState {
  var cameraStatus: PermissionStatus = .notDetermined
  var microphoneStatus: PermissionStatus = .notDetermined
  var locationStatus: PermissionStatus = .notDetermined

  /// True only when camera, mic, and location are all granted. The wizard needs location for
  /// its where-stamp and the live flow needs camera and mic; the tab opens once it has all
  /// three, and shows the access gate until then.
  var allGranted: Bool {
    cameraStatus == .granted && microphoneStatus == .granted && locationStatus == .granted
  }

  func status(of permission: Permission) -> PermissionStatus {
    switch permission {
    case .camera: cameraStatus
    case .microphone: microphoneStatus
    case .location: locationStatus
    }
  }
}

/// Drives the Identify landing: it reads permission status and re-reads it whenever the screen
/// might have gone stale (first appearance, and every return to the foreground — a trip to
/// Settings is exactly how a status flips under us).
///
/// Requesting the system prompt is not here — that is the part that does not mirror, so the
/// screen owns it via ``PermissionRequest``. The view model only reads and routes to Settings.
@MainActor
@Observable
final class IdentifyViewModel {

  private(set) var uiState = IdentifyUiState()

  private let permissions: any PermissionsController

  init(permissions: any PermissionsController) {
    self.permissions = permissions
    refresh()
  }

  /// Re-reads all three statuses from the OS.
  func refresh() {
    uiState.cameraStatus = permissions.status(.camera)
    uiState.microphoneStatus = permissions.status(.microphone)
    uiState.locationStatus = permissions.status(.location)
  }

  /// Sends the user to this app's page in Settings — the way back from a standing denial.
  func openSettings() {
    permissions.openAppSettings()
  }
}
