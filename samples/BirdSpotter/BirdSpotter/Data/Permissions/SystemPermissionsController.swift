/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemPermissionsController.swift
//  birdspotter
//

import AVFoundation
import CoreLocation
import Foundation
import UIKit

/// The ``PermissionsController`` the app ships: AVFoundation for camera and microphone,
/// CoreLocation for location, and `UIApplication` for the trip to Settings.
///
/// The mirror is ``PermissionsController`` — status and the Settings escape hatch — not this class.
///
/// Requesting the system prompt is **not** on the protocol (see its doc); here it is the
/// ``PermissionRequest`` helper below, which the Identify screen calls directly. This
/// divergence is one the architecture rules allow by name: the shape is shared, the way each
/// platform raises the prompt is not.
@MainActor
final class SystemPermissionsController: PermissionsController {

  /// Held rather than created per call: CoreLocation reads its authorization off a manager
  /// instance, and one is enough.
  private let locationManager = CLLocationManager()

  func status(_ permission: Permission) -> PermissionStatus {
    switch permission {
    case .camera: AVCaptureDevice.authorizationStatus(for: .video).permissionStatus
    case .microphone: AVCaptureDevice.authorizationStatus(for: .audio).permissionStatus
    case .location: locationManager.authorizationStatus.permissionStatus
    }
  }

  func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

/// The request path — the piece that does not mirror, because raising a system prompt is bound
/// to whatever is on screen. The Identify screen calls this on a row tap.
enum PermissionRequest {
  /// Raises the system prompt for `permission` and answers with the resulting status. A prompt
  /// for something already decided (granted, or denied for good) returns immediately, which is
  /// what lets the screen fall through to Settings when nothing changed.
  @MainActor
  static func access(to permission: Permission) async -> PermissionStatus {
    switch permission {
    case .camera:
      return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
    case .microphone:
      return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
    case .location:
      return await LocationAuthorizationRequest().request()
    }
  }
}

/// Wraps the one authorization API that answers through a delegate rather than an `await`.
/// Retained for the duration of the `request()` call by the caller's local; the first
/// determined callback resumes and it is done.
@MainActor
private final class LocationAuthorizationRequest: NSObject, CLLocationManagerDelegate {

  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<PermissionStatus, Never>?

  func request() async -> PermissionStatus {
    let current = manager.authorizationStatus
    // Only `notDetermined` raises a dialog; anything else is the user's standing answer.
    guard current == .notDetermined else { return current.permissionStatus }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      manager.delegate = self
      manager.requestWhenInUseAuthorization()
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      // Setting the delegate fires this once with the pre-prompt status; wait for the
      // decision before resuming.
      guard manager.authorizationStatus != .notDetermined else { return }
      self.continuation?.resume(returning: manager.authorizationStatus.permissionStatus)
      self.continuation = nil
    }
  }
}

private extension AVAuthorizationStatus {
  var permissionStatus: PermissionStatus {
    switch self {
    case .authorized: .granted
    case .denied, .restricted: .denied
    case .notDetermined: .notDetermined
    @unknown default: .denied
    }
  }
}

private extension CLAuthorizationStatus {
  var permissionStatus: PermissionStatus {
    switch self {
    case .authorizedWhenInUse, .authorizedAlways: .granted
    case .denied, .restricted: .denied
    case .notDetermined: .notDetermined
    @unknown default: .denied
    }
  }
}
