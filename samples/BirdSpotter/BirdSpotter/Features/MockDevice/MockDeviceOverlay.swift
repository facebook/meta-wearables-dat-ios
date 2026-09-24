/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceOverlay.swift
//  birdspotter
//

import SwiftUI
import UIKit

/// What floats over the whole app while the mock is on: the button, or — once it is tapped —
/// the panel of controls in its place.
///
/// Nothing at all while the kit is off, which is the common case: the overlay is installed
/// once at launch and stays, and switching the mock off in Settings simply empties it.
struct MockDeviceOverlay: View {
  let model: MockDeviceViewModel
  let settings: MockDeviceSettingsStore
  let gate: MockDeviceOverlayGate

  @State private var isPanelOpen = false
  @State private var position: MockDeviceButtonPosition

  init(model: MockDeviceViewModel, settings: MockDeviceSettingsStore, gate: MockDeviceOverlayGate) {
    self.model = model
    self.settings = settings
    self.gate = gate
    _position = State(initialValue: settings.buttonPosition)
  }

  var body: some View {
    ZStack {
      if model.uiState.isEnabled {
        if isPanelOpen {
          MockDeviceScreen(model: model) {
            isPanelOpen = false
          }
          .transition(.opacity)
        } else {
          // The button roams the whole screen, safe areas included — it is chrome
          // over chrome, and a corner under the home indicator is a fine place to
          // park it.
          GeometryReader { proxy in
            MockDeviceButton(
              position: position,
              bounds: proxy.size,
              onTap: { isPanelOpen = true },
              onMove: { moved in
                position = moved
                settings.buttonPosition = moved
              },
              onFrameChange: { frame in gate.buttonFrame = frame }
            )
          }
          .ignoresSafeArea()
        }
      }
    }
    // The whole window, always: the panel has to be offered the screen to fill it, and a
    // stack sized to a small button would be a small panel.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeInOut(duration: 0.18), value: isPanelOpen)
    .task { await model.observe() }
    .onChange(of: isPanelOpen) { _, isOpen in
      BirdLog.debug(.glasses, "mock device — panel \(isOpen ? "opened" : "closed")")
      gate.isPanelOpen = isOpen
      if isOpen { gate.buttonFrame = .zero }
    }
    .onChange(of: model.uiState.isEnabled) { _, isEnabled in
      guard !isEnabled else { return }
      isPanelOpen = false
      gate.buttonFrame = .zero
    }
  }
}

/// What the overlay window needs to know to decide whether a touch is its own: whether the
/// panel is open (then everything is), and otherwise where the button is (then only that is).
///
/// A plain class rather than state on the view because the window asks in `hitTest`, which
/// is UIKit's moment and not SwiftUI's.
@MainActor
final class MockDeviceOverlayGate {
  var isPanelOpen = false
  var buttonFrame: CGRect = .zero
}

/// The window the overlay lives in — its own, above the app's, so it floats over every screen
/// the app can show, including the covers and sheets the main window presents over itself.
///
/// **Passes touches through by default.** A window catches every touch that lands on it, and
/// this one covers the whole screen; it hands back `nil` for anything that is not the button
/// or the open panel, and the touch falls through to the app underneath as if the window were
/// not there.
@MainActor
final class MockDeviceOverlayWindow: UIWindow {
  let gate = MockDeviceOverlayGate()

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    // A little outside the drawn capsule too: the button is small, and a touch that
    // lands on its edge should lift it rather than fall through to the screen.
    let wanted =
      gate.isPanelOpen
      || gate.buttonFrame.insetBy(dx: -mockButtonHitSlop, dy: -mockButtonHitSlop).contains(point)
    guard wanted else { return nil }
    return super.hitTest(point, with: event)
  }
}

/// Installs the overlay window over the app's scene, once.
///
/// Called from the shell when it appears, because that is the first moment a window scene
/// exists to attach to; the app's own `init` runs before any scene does.
@MainActor
enum MockDeviceOverlayHost {
  private static var window: MockDeviceOverlayWindow?

  static func install(mockDevice: any MockDeviceRepository, settings: MockDeviceSettingsStore) {
    guard window == nil else { return }
    guard
      let scene = UIApplication.shared.connectedScenes
        .lazy
        .compactMap({ $0 as? UIWindowScene })
        .first
    else {
      BirdLog.error(.glasses, "mock device — no window scene to overlay")
      return
    }

    let overlay = MockDeviceOverlayWindow(windowScene: scene)
    // Above alerts: the panel is a developer's instrument and should not be covered by
    // the app's own dialogs while it is being used.
    overlay.windowLevel = .alert + 1
    overlay.backgroundColor = .clear

    let root = UIHostingController(
      rootView: MockDeviceOverlay(
        model: MockDeviceViewModel(mockDevice: mockDevice),
        settings: settings,
        gate: overlay.gate
      )
      // No ground: the theme's paper would cover the whole app. The panel paints its own.
      .birdSpotterTheme(paintsGround: false)
    )
    root.view.backgroundColor = .clear
    overlay.rootViewController = root
    overlay.isHidden = false
    window = overlay
  }
}

/// How far outside the drawn button a touch still counts as the button's.
private let mockButtonHitSlop: CGFloat = 8
