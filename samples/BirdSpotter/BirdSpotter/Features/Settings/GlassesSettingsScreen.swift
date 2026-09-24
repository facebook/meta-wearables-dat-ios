/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesSettingsScreen.swift
//  birdspotter
//

import MWDATCore
import SwiftUI

/// Meta AI Glasses — where the link stands, pushed from the Settings row once registration
/// has happened.
///
/// Four readings and three raises. The readings (``GlassesSettingsViewModel``) are the
/// registration state, the glasses Meta AI lists, and DAT's two grants — camera and
/// microphone. The raises are those two grant flows and unlinking — all handed to the Meta
/// AI app, all landing their outcome back in the readings, and all here in the screen
/// rather than the view model — raising a system flow belongs to the thing on screen (the
/// divergence ``PermissionsController`` documents).
struct GlassesSettingsScreen: View {
  @Environment(\.theme) private var theme
  @State private var model: GlassesSettingsViewModel

  init(glassesSession: any GlassesSessionRepository) {
    _model = State(initialValue: GlassesSettingsViewModel(glassesSession: glassesSession))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.section) {
        statusSection
        speechSection
        cameraSection
        displaySection
        linkSection
        footnote
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Meta AI Glasses")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.observe() }
  }

  private var statusSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Status", color: theme.colors.gilt)

      statusRow(label: "Registration", value: registrationValue)
      statusRow(
        label: "Glasses",
        value: model.deviceInfo?.name ?? "None found",
        support: glassesSupport
      )
      if model.deviceInfo != nil {
        statusRow(label: "Worn", value: wornValue)
        statusRow(label: "Battery", value: batteryValue)
        statusRow(label: "Temperature", value: thermalValue, support: thermalSupport)
      }
      accessRow(
        title: "Camera access",
        access: model.cameraAccess,
        permission: .camera,
        support: "What the live session photographs through"
      )
      accessRow(
        title: "Microphone access",
        access: model.microphoneAccess,
        permission: .microphone,
        support: "Meta AI's grant for the glasses' microphones — recording still "
          + "takes the Bluetooth headset route"
      )
    }
  }

  /// The wear and battery rows read the snapshot the link fills in, so with the pair
  /// unreachable both read "—" — which is the truth about what the phone can know, and
  /// the Glasses row above already says why.
  private var wornValue: String {
    switch model.deviceInfo?.isWorn {
    case .some(true): "On the face"
    case .some(false): "Taken off"
    case .none: "—"
    }
  }

  /// A percent only when there is a reading — unknown is "—", never 0%. Charging rides
  /// the same row: it answers the question the number raises.
  private var batteryValue: String {
    let charging = model.deviceInfo?.isCharging == true
    guard let level = model.deviceInfo?.batteryLevel else {
      return charging ? "Charging" : "—"
    }
    return charging ? "\(level)% · charging" : "\(level)%"
  }

  /// Heat, in the wearer's words rather than the SDK's ladder.
  ///
  /// **"Normal" is a real answer and worth printing.** Heat is the one reading here that
  /// is read *because* something already went wrong — a run that throttled, a session
  /// that ended itself — and a row that only appears when hot cannot answer the question
  /// "was it the heat?" with a no. The support line below carries the consequence, so
  /// the ordinary case stays one quiet word.
  private var thermalValue: String {
    switch model.deviceInfo?.thermal {
    case .nominal: "Normal"
    case .elevated: "Warm"
    case .critical: "Too hot"
    case nil: "—"
    }
  }

  /// Only the grades that cost something explain themselves.
  private var thermalSupport: String? {
    switch model.deviceInfo?.thermal {
    case .elevated: "The glasses may slow the camera down to cool off"
    case .critical: "Sessions will stop until they cool — give them a few minutes off"
    case .nominal, nil: nil
    }
  }

  /// Why the glasses cannot be reached, most actionable answer first.
  ///
  /// **A version mismatch outranks "not in range"**, because it is the one that looks
  /// identical from the outside and sends someone hunting for a Bluetooth fault they do
  /// not have: DAT pins Meta AI app and firmware versions on both ends, and glasses that
  /// are on, paired and inches away will still never link with either behind.
  ///
  /// What the link turns on, and nothing more: folding and range are what drop it — the
  /// hinge cuts Bluetooth. Wear and battery have their own rows off the same snapshot;
  /// this line only ever explains an unreachable pair.
  private var glassesSupport: String? {
    guard let device = model.deviceInfo else { return nil }
    switch device.compatibility {
    case .deviceUpdateRequired:
      return "Your glasses need a firmware update — check them in the Meta AI app"
    case .sdkUpdateRequired:
      return "These glasses are newer than this app's Meta SDK — that one is ours to fix"
    case .unknown:
      // Never negotiated: a pair DAT has actually reached reports its compatibility,
      // so `unknown` alongside a dead link means the two have never spoken at all.
      // Developer Mode is the usual reason — it is **per pair of glasses**, it is not
      // the same switch as the one in the Meta AI app's own settings, and a firmware
      // update silently turns it back off.
      return device.isAvailable
        ? nil
        : "Meta AI lists these but they have never answered — check Developer Mode is on for this pair in the Meta AI app"
    case .compatible:
      return device.isAvailable
        ? nil
        : "Not reachable right now — folding them or going out of range drops the link"
    }
  }

  private var registrationValue: String {
    switch model.registrationState {
    case .registered: "Linked"
    case .registering: "Waiting on Meta AI"
    case .available: "Not linked"
    case .unavailable: "Meta AI unreachable"
    case nil: "—"
    }
  }

  /// The two rows with an action on them: Meta AI's grants, given through the Meta AI app.
  /// `Allow` raises the grant flow; a grant that already happened is just read out.
  ///
  /// **The row always reads its state, and the action sits under it** rather than in the
  /// value column. A permission is a status first — the column stays a column, so
  /// Registration, Glasses and the two grants can be read straight down without one of
  /// them answering with a button instead of a word.
  ///
  /// **`Unknown` is offered no button, and says why instead.** DAT reads the grant off a
  /// connected pair, so with the glasses linked but not connected there is nothing to
  /// ask and nothing to answer — an `Allow` here raises a flow that cannot succeed, and
  /// reading the unreadable state as "Not asked" told the wearer they had never granted
  /// something they had. The support line carries the one action that helps, the same
  /// way the Glasses row above it explains an unreachable pair rather than merely
  /// reporting one.
  private func accessRow(
    title: String,
    access: GlassesAccess?,
    permission: GlassesPermission,
    support: String
  ) -> some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      HStack(spacing: theme.space.related) {
        VStack(alignment: .leading) {
          Text(title)
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text(
            access == .unknown
              ? "Meta AI can only answer this over a live link — connect your glasses"
              : support
          )
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
        }
        Spacer()
        Text(accessValue(access))
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
      }

      switch access {
      case .denied:
        // Denied covers the never-asked case too — DAT has no not-determined to
        // tell them apart, and `Allow` is the right offer for both.
        ActionButton(title: "Allow") {
          // The result payload is not read — the view model re-asks instead, so
          // the row can never disagree with a grant that arrived some other way.
          Task {
            _ = try? await Wearables.shared.requestPermission(permission.datPermission)
            await model.refreshAccess()
          }
        }
      case .granted, .unknown, nil:
        EmptyView()
      }
    }
  }

  private func accessValue(_ access: GlassesAccess?) -> String {
    switch access {
    case .granted: "Granted"
    case .denied: "Denied"
    case .unknown: "Unknown"
    case nil: "—"
    }
  }

  /// The one reading on this screen that cannot be taken without opening a session, so it is a
  /// door rather than a row. Speech is the only capability the app uses that some pairs simply
  /// do not have, and nothing above tells them apart — see ``SpeechTestViewModel``.
  private var speechSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Speech", color: theme.colors.gilt)

      NavigationLink(value: Route.speechTest) {
        DisclosureRow {
          Text("Test ASR")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Opens a session and prints what the glasses hear")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// The door to the shutter: a sub-screen that opens a session, takes one photograph at
  /// settings chosen on the spot, and prints what the crossing cost. A measuring
  /// instrument — see ``GlassesCameraViewModel``.
  private var cameraSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Camera", color: theme.colors.gilt)

      NavigationLink(value: Route.glassesCamera) {
        DisclosureRow {
          Text("Camera")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Takes one photo at a chosen size and quality, and times the crossing")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// The hand-cranked door to the panel: a sub-screen that opens a session and puts any
  /// bird's card up on cue — a demo control, not a feature.
  private var displaySection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Display", color: theme.colors.gilt)

      NavigationLink(value: Route.glassesDisplay) {
        DisclosureRow {
          Text("Display Screen")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Puts any bird's card on the glasses and holds it there")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// Unlinking, and what it costs — the caption first, then the plate.
  ///
  /// **Destructive rather than secondary.** This is the only control in the app that
  /// takes the glasses away, and until now it wore the same weight as the two status
  /// rows above it: a headline and a caption, tappable only if you happened to try. The
  /// consequence belongs above the button where it is read *before* the tap, not inside
  /// it, which is also what lets the plate carry the one line that matters.
  private var linkSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Link", color: theme.colors.gilt)

      Text("Settings goes back to the set-up card. Relinking is the same handshake again.")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)

      ActionButton(title: "Unlink from Meta AI", tone: .destructive) {
        Task { try? await Wearables.shared.startUnregistration() }
      }
    }
  }

  private var footnote: some View {
    Text(
      "BirdSpotter appears under Developer mode apps in Meta AI → App connections; "
        + "registration and both grants live there."
    )
    .font(theme.type.label)
    .foregroundStyle(theme.colors.textSecondary)
  }

  private func statusRow(label: String, value: String, support: String? = nil) -> some View {
    HStack(spacing: theme.space.related) {
      VStack(alignment: .leading) {
        Text(label)
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
        if let support {
          Text(support)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      Spacer()
      Text(value)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }
}

/// Answers like a *linked* phone with one pair Meta AI lists, reachable or not, and
/// whatever the grants read as while it is — the shared ``PreviewGlassesSession`` is the
/// never-registered fixture and cannot show this screen's states.
private struct PreviewLinkedGlassesSession: GlassesSessionRepository {
  let isReachable: Bool
  let camera: GlassesAccess
  let microphone: GlassesAccess

  func registrationStateStream() -> AsyncStream<GlassesRegistrationState> {
    AsyncStream { continuation in
      continuation.yield(.registered)
      continuation.finish()
    }
  }
  func deviceInfoStream() -> AsyncStream<GlassesDeviceInfo?> {
    AsyncStream(GlassesDeviceInfo?.self) { continuation in
      continuation.yield(
        GlassesDeviceInfo(
          name: "Chris's Ray-Ban Meta",
          isAvailable: isReachable,
          compatibility: .compatible,
          isWorn: isReachable ? true : nil,
          batteryLevel: isReachable ? 82 : nil,
          isCharging: isReachable ? false : nil,
          thermal: isReachable ? .nominal : nil
        )
      )
      continuation.finish()
    }
  }
  func sessionStream() -> AsyncThrowingStream<GlassesSessionState, Error> {
    AsyncThrowingStream { $0.finish() }
  }
  func access(_ permission: GlassesPermission) async -> GlassesAccess {
    switch permission {
    case .camera: camera
    case .microphone: microphone
    }
  }
}

/// Linked, a pair on the link, the camera already given and the microphone still to give —
/// the grant rows in both of the states they answer in.
#Preview("Connected") {
  NavigationStack {
    GlassesSettingsScreen(
      glassesSession: PreviewLinkedGlassesSession(
        isReachable: true,
        camera: .granted,
        microphone: .denied
      )
    )
  }
  .birdSpotterTheme()
}

/// Linked, but nothing on the link — the state that used to read "Not asked" and offer an
/// `Allow` that could not succeed. Every row now explains the same one blocker.
#Preview("Disconnected") {
  NavigationStack {
    GlassesSettingsScreen(
      glassesSession: PreviewLinkedGlassesSession(
        isReachable: false,
        camera: .unknown,
        microphone: .unknown
      )
    )
  }
  .birdSpotterTheme()
}
