/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesSettingsViewModel.swift
//  birdspotter
//

import Foundation

/// What the glasses settings screen reports: where registration stands, which glasses Meta
/// AI knows about, and whether each of Meta AI's grants can be read and has been given.
///
/// All reads. The raises — the grant flows, unlinking — live in the screen, because raising
/// either is bound to whatever is on screen; see ``SettingsViewModel`` for the same split and
/// ``PermissionsController`` for the rule it follows.
@MainActor
@Observable
final class GlassesSettingsViewModel {

  private let glassesSession: any GlassesSessionRepository

  /// Where registration stands — `nil` until the first reading lands.
  private(set) var registrationState: GlassesRegistrationState?

  /// The first pair Meta AI lists — `nil` while unread, and `nil` when there are none.
  private(set) var deviceInfo: GlassesDeviceInfo?

  /// Where the DAT camera grant stands — `nil` until the first check answers.
  ///
  /// **Re-read whenever the link changes**, not once at construction. DAT can only read
  /// the grant off a connected pair, so the answer for the same phone and the same Meta
  /// AI account is genuinely different before and after the glasses connect. Asking once
  /// left the row stuck on whatever was true at the moment the screen opened — which is
  /// why connecting the glasses appeared to do nothing until the app was restarted.
  private(set) var cameraAccess: GlassesAccess?

  /// Where the DAT microphone grant stands, on the same terms as ``cameraAccess``.
  private(set) var microphoneAccess: GlassesAccess?

  init(glassesSession: any GlassesSessionRepository) {
    self.glassesSession = glassesSession
  }

  /// Follows everything the screen shows, for as long as the screen is up — one
  /// structured group, so leaving the screen cancels both.
  ///
  /// **The grants are not a third task.** They are read by ``observeDevice()``, off the
  /// link changes that decide whether they can be read at all — one reader, in one order,
  /// rather than an opening read racing the first device reading for the last word.
  func observe() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.observeRegistration() }
      group.addTask { await self.observeDevice() }
    }
  }

  /// Asks again, for every grant the screen shows. They are given in the Meta AI app, off
  /// in another process, so there is no stream to follow — the screen calls this when one
  /// of its grant flows returns, and the link itself drives the rest.
  ///
  /// **Both are re-read whichever flow returned.** Meta AI shows the grants together, so
  /// somebody sent there to allow the microphone can allow the camera on the same screen,
  /// and a row that only re-read the grant it raised would go on reporting the other one
  /// stale.
  func refreshAccess() async {
    cameraAccess = await glassesSession.access(.camera)
    microphoneAccess = await glassesSession.access(.microphone)
  }

  private func observeRegistration() async {
    for await state in glassesSession.registrationStateStream() {
      registrationState = state
    }
  }

  private func observeDevice() async {
    /// Reachability as last read, `nil` before the first reading — so the opening
    /// emission always counts as a change and the row gets an answer.
    var lastReachable: Bool?
    // docs:glasses-device-info:begin
    for await device in glassesSession.deviceInfoStream() {
      deviceInfo = device
      // Reachability changing either way is the moment the grants become readable —
      // or stop being. Reachability, not the whole device: a pair that renames
      // itself is not news to a permission, so only a change in `isAvailable` counts.
      let reachable = device?.isAvailable == true
      if reachable != lastReachable {
        lastReachable = reachable
        await refreshAccess()
      }
    }
    // docs:glasses-device-info:end
  }
}
