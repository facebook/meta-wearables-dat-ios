/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyScreen.swift
//  birdspotter
//

import SwiftUI

/// Identify — the two ways to put a name to a bird, once the app has the access they need.
///
/// The page is all-or-nothing. Until camera, microphone, and location are all granted it is a
/// single access gate: each permission's status, and the one tap that turns it on — inline the
/// first time, then off to Settings. The moment the last one is granted the gate gives way to
/// the two cards: a step-by-step questionnaire that narrows the bundled guide, and a real-time
/// flow over the camera and mic (the glasses a hands-free bonus, never a requirement).
///
/// The wizard brings its own state when pushed onto the tab's stack (owned by `ContentView`);
/// the real-time flow comes up as a `.fullScreenCover` over the whole shell. The permission
/// state, though, is this screen's, so it has an ``IdentifyViewModel`` — refreshed on every
/// return to the foreground, since Settings is where a status changes.
struct IdentifyScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.scenePhase) private var scenePhase

  @State private var model: IdentifyViewModel

  // The real-time cover's presented flag. Local `@State`: a modal that covers the shell is
  // this screen's own affair, because `.fullScreenCover` clears the tab bar on its own.
  @State private var isRealtimePresented = false

  // A voice launch's standing request — set by the shell, which is what hears "Hey Meta,
  // open BirdSpotter", and cleared here when the cover it raised falls. A binding rather
  // than local state because the request outlives neither party alone: the shell hears
  // it, this screen is what can act on it.
  @Binding private var startOnGlasses: Bool

  // Permissions we have already raised the system prompt for this session. A second tap on one
  // still not granted means the prompt won't show again, so we route to Settings instead.
  @State private var promptedThisSession: Set<Permission> = []

  /// The real-time session, handed to the cover when it is raised. The app's, not this
  /// screen's: it is built once in the composition root, so a session a voice launch started
  /// while the phone was in a pocket is the same one the cover shows when it comes up.
  private let realtime: RealtimeViewModel

  init(
    permissions: any PermissionsController,
    realtime: RealtimeViewModel,
    startOnGlasses: Binding<Bool> = .constant(false)
  ) {
    _model = State(initialValue: IdentifyViewModel(permissions: permissions))
    _startOnGlasses = startOnGlasses
    self.realtime = realtime
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        titleArea

        if model.uiState.allGranted {
          NavigationLink(value: Route.identifyWizard) {
            StepByStepCard()
          }
          .buttonStyle(.plain)
          .padding(.top, theme.space.section)

          Button {
            isRealtimePresented = true
          } label: {
            RealtimeCard()
          }
          .buttonStyle(.plain)
          .padding(.top, theme.space.separate)
        } else {
          AccessGate(uiState: model.uiState, onEnable: enable)
            .padding(.top, theme.space.section)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.page)
    }
    .background(theme.colors.paper)
    .toolbar(.hidden, for: .navigationBar)
    .fullScreenCover(
      isPresented: $isRealtimePresented,
      // The request belongs to the launch, not to the screen: however the cover
      // falls, the next open starts from a clean ask.
      onDismiss: { startOnGlasses = false }
    ) {
      RealtimeScreen(model: realtime)
    }
    // A voice launch raises the cover the way a tap on the card does — on arrival when
    // this screen is already up, and on the way in when the launch is what composed it.
    // The session itself is already started by then: the shell starts it on the glasses
    // the moment the launch lands, and the cover only shows it.
    .onChange(of: startOnGlasses) { _, requested in
      if requested { isRealtimePresented = true }
    }
    .onAppear {
      if startOnGlasses { isRealtimePresented = true }
    }
    // Settings is a round trip out of the app; coming back is when a granted/denied flip
    // becomes visible, so re-read the moment the scene is active again.
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refresh() }
    }
  }

  /// Eyebrow over a headline, no chrome above it — the same opening Explore makes.
  private var titleArea: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Identify", color: theme.colors.gilt)
      Text("What bird was that?")
        .font(theme.type.display)
        .foregroundStyle(theme.colors.textPrimary)
    }
  }

  /// The tap on an Access row that needs enabling: raise the prompt the first time, then — once
  /// the OS will not show it again — hand off to Settings.
  private func enable(_ permission: Permission) {
    if promptedThisSession.contains(permission) {
      model.openSettings()
      return
    }
    promptedThisSession.insert(permission)
    Task {
      _ = await PermissionRequest.access(to: permission)
      model.refresh()
    }
  }
}

/// The wizard's front door: three questions against the bundled guide, fully offline.
private struct StepByStepCard: View {
  @Environment(\.theme) private var theme

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: 0) {
        PlateLabel(text: "Step by Step", color: theme.colors.verdigris)
        Text("Answer three quick questions.")
          .font(theme.type.title)
          .foregroundStyle(theme.colors.textPrimary)
          .padding(.top, theme.space.related)
        Text("Size, colors, and what it was doing — the guide narrows to the birds that match.")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
          .padding(.top, theme.space.snug)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.space.cardInset)
    }
  }
}

/// The real-time flow's front door. The mic is the way in; the camera and the glasses are both
/// optional.
///
/// **No "Preview" plate.** It was hedging from when the session was half-built, and it stopped
/// being true — the session records, identifies, and writes an outing. A card that apologises
/// for itself in gilt is the first thing an audience reads on the tab this demo is *about*.
private struct RealtimeCard: View {
  @Environment(\.theme) private var theme

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: 0) {
        PlateLabel(text: "Real-Time", color: theme.colors.verdigris)
        Text("Start listening.")
          .font(theme.type.title)
          .foregroundStyle(theme.colors.textPrimary)
          .padding(.top, theme.space.related)
        Text("The mic runs while you watch. Take a photo, say what you see, and it all lands on one timeline.")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
          .padding(.top, theme.space.snug)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.space.cardInset)
    }
  }
}

/// The access gate: the whole page until every permission is granted. A line of why, then one
/// row per permission — each reading its status and, when it is not granted, offering the one
/// tap that enables it.
private struct AccessGate: View {
  @Environment(\.theme) private var theme
  let uiState: IdentifyUiState
  let onEnable: (Permission) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Turn on camera, microphone, and location to start identifying birds.")
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.bottom, theme.space.separate)
      CardSurface {
        VStack(spacing: 0) {
          PermissionRow(name: "Camera", status: uiState.cameraStatus) { onEnable(.camera) }
          HairlineRule()
          PermissionRow(name: "Microphone", status: uiState.microphoneStatus) { onEnable(.microphone) }
          HairlineRule()
          PermissionRow(name: "Location", status: uiState.locationStatus) { onEnable(.location) }
        }
      }
    }
  }
}

/// One permission's line: its name, and either a quiet "On" or a verdigris "Enable" that takes
/// the tap. A granted row is settled — it does not invite a tap it has nothing to do with.
private struct PermissionRow: View {
  @Environment(\.theme) private var theme
  let name: String
  let status: PermissionStatus
  let onEnable: () -> Void

  private var granted: Bool { status == .granted }

  var body: some View {
    if granted {
      row
    } else {
      Button(action: onEnable) { row }
        .buttonStyle(.plain)
    }
  }

  private var row: some View {
    HStack {
      Text(name)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
      Spacer()
      PlateLabel(
        text: granted ? "On" : "Enable",
        color: granted ? theme.colors.textFaint : theme.colors.verdigris
      )
    }
    .padding(.horizontal, theme.space.cardInset)
    .padding(.vertical, theme.space.related)
    .contentShape(.rect)
  }
}

#Preview("Access gate") {
  NavigationStack {
    IdentifyScreen(
      permissions: PreviewPermissions(locationGranted: false),
      realtime: previewRealtimeViewModel()
    )
  }
  .birdSpotterTheme()
}

#Preview("Granted") {
  NavigationStack {
    IdentifyScreen(
      permissions: PreviewPermissions(locationGranted: true),
      realtime: previewRealtimeViewModel()
    )
  }
  .birdSpotterTheme()
}

/// Preview stand-in. `locationGranted` flips the last permission so the same preview shows the
/// gate (something still to grant) or the two cards (all granted).
private struct PreviewPermissions: PermissionsController {
  let locationGranted: Bool
  func status(_ permission: Permission) -> PermissionStatus {
    switch permission {
    case .camera, .microphone: .granted
    case .location: locationGranted ? .granted : .notDetermined
    }
  }
  func openAppSettings() {}
}
