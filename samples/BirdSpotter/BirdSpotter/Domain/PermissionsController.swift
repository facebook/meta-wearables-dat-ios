/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PermissionsController.swift
//  birdspotter
//

import Foundation

/// A capability the app asks the OS for. Three of them gate the Identify tab: the phone
/// `camera` and `microphone` behind the real-time flow, and `location` behind the
/// questionnaire's where-stamp.
nonisolated enum Permission: Sendable {
  case camera
  case microphone
  case location
}

/// Where the user stands on a ``Permission``. `notDetermined` is "never asked"; `denied` covers
/// both a refusal and an OS restriction. Only `granted` opens a gate.
///
/// The two are not always distinguishable, and need not be: the Identify tab treats everything
/// that is not `granted` as "needs enabling" and escalates a tap to Settings only after a
/// prompt changed nothing. See the Platform notes.
nonisolated enum PermissionStatus: Sendable {
  case granted
  case denied
  case notDetermined
}

/// The OS permission surface the Identify tab reads to decide what it may offer.
///
/// Two questions only — *what is the status?* and *take me to Settings to change it* — because
/// those are the parts that mirror.
///
/// **Requesting the system prompt is deliberately not here.** It is the one piece the
/// architecture note calls un-mirrorable — raising the dialog is bound to whatever is on screen
/// — so the Identify screen owns its own request path. See the Platform notes.
@MainActor
protocol PermissionsController {
  /// The current status of `permission`, read fresh from the OS on each call.
  func status(_ permission: Permission) -> PermissionStatus

  /// Opens this app's page in the system Settings app — the only way back from `denied`.
  func openAppSettings()
}
