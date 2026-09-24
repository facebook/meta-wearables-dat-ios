/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SettingsViewModel.swift
//  birdspotter
//

import Foundation

/// What Settings knows about the glasses: where registration stands, so the screen offers
/// the right doorway — the set-up card before the handshake, the glasses row after it.
/// Plus the one thing Settings can do to the Journal: empty it.
///
/// Raising the handshake itself is the screen's job, not this class's: handing off to Meta AI
/// is bound to whatever is on screen — the same un-mirrorable seam ``PermissionsController``
/// documents — so the raise stays beside the card.
@MainActor
@Observable
final class SettingsViewModel {

  private let glassesSession: any GlassesSessionRepository
  private let journal: any JournalRepository
  private let mockDevice: any MockDeviceRepository

  /// Where registration stands — `nil` until the first reading lands, and the screen
  /// offers nothing about glasses over a `nil`: flashing the set-up card at someone who
  /// is already linked would be worse than a beat of silence.
  private(set) var registrationState: GlassesRegistrationState?

  /// Set while the sweep is running, so the confirmed delete cannot be started twice and
  /// the button can say what it is doing.
  private(set) var isDeletingJournal = false

  /// Whether the Mock Device Kit is standing in for the real SDK.
  ///
  /// **Offered in every registration state, deliberately.** The mock is the thing you
  /// reach for *without* glasses, so its switch cannot live behind the glasses row that
  /// only registration unlocks — it sits in the Demo / Developer section, which is always
  /// there.
  private(set) var isMockDeviceEnabled = false

  /// Set while the flip is in flight, so the switch cannot be thrown twice into the wait.
  private(set) var isMockDeviceFlipping = false

  init(
    glassesSession: any GlassesSessionRepository,
    journal: any JournalRepository,
    mockDevice: any MockDeviceRepository
  ) {
    self.glassesSession = glassesSession
    self.journal = journal
    self.mockDevice = mockDevice
    isMockDeviceEnabled = mockDevice.isEnabled
  }

  /// Follows registration and the mock's switch for as long as the screen is up. Cold, per
  /// the architecture contract: the screen's `.task` is the subscription's whole life.
  func observe() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { @MainActor [self] in
        for await state in glassesSession.registrationStateStream() {
          registrationState = state
        }
      }
      group.addTask { @MainActor [self] in
        for await isEnabled in mockDevice.isEnabledStream() {
          isMockDeviceEnabled = isEnabled
        }
      }
    }
  }

  /// Flips the mock. The kit ends any running session first, which is why this takes a
  /// beat and why the switch is held during it.
  func setMockDeviceEnabled(_ enabled: Bool) async {
    guard !isMockDeviceFlipping, enabled != isMockDeviceEnabled else { return }
    isMockDeviceFlipping = true
    defer { isMockDeviceFlipping = false }
    await mockDevice.setEnabled(enabled)
  }

  /// Empties the Journal. Called only from behind the screen's confirmation — nothing
  /// here asks a second time.
  ///
  /// A failure is swallowed on purpose: the Journal is a local store with nothing to
  /// retry against, and the screen behind this one is already showing whatever survived.
  func deleteAllJournalData() async {
    guard !isDeletingJournal else { return }
    isDeletingJournal = true
    defer { isDeletingJournal = false }
    try? await journal.deleteAll()
  }
}
