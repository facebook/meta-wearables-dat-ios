/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceButton.swift
//  birdspotter
//

import SwiftUI

/// The floating way into the mock panel: the glasses glyph in a dark capsule, wearing a
/// vermilion dot so it reads as *simulated* from across the room.
///
/// **Small, and out of the way by design.** It floats over every screen in the app while the
/// kit is on, so it has to be the least of what is on screen: one glyph, one capsule, at the
/// same depth every other piece of chrome laid over a picture in this app uses
/// (``StopControl``'s ink at 0.6). The dot is the honesty affordance — the same reason the
/// Settings section is labelled *Demo / Developer* — so nobody watching mistakes a simulated
/// pair for the real thing.
///
/// A tap opens the panel. A press-and-hold picks the button up, a drag carries it, and
/// letting go pins it where it was left, remembered across launches through
/// ``MockDeviceSettingsStore``. Hold-then-drag rather than a plain drag, so a thumb that
/// brushes past it on the way to something else does not move it.
struct MockDeviceButton: View {
  @Environment(\.theme) private var theme

  /// Where the button sits, in fractions of `bounds`.
  let position: MockDeviceButtonPosition
  /// The area the button may be dragged over — the whole overlay.
  let bounds: CGSize
  let onTap: () -> Void
  let onMove: (MockDeviceButtonPosition) -> Void
  /// Where the button actually is on screen, for the window's hit test.
  let onFrameChange: (CGRect) -> Void

  /// The drag in flight — the offset from where the button was pinned.
  @State private var dragOffset: CGSize = .zero
  @State private var isLifted = false

  /// The lift, armed on touch-down and cancelled on touch-up: a finger that is still down
  /// when it fires has been holding, and the button is picked up.
  @State private var lift: Task<Void, Never>?
  @State private var isPressed = false

  var body: some View {
    let pinned = pinnedPoint
    let center = CGPoint(x: pinned.x + dragOffset.width, y: pinned.y + dragOffset.height)

    ZStack(alignment: .topTrailing) {
      Image(glyph: theme.glyphs.glasses)
        .foregroundStyle(theme.colors.paper)
        .frame(width: mockButtonGlyphSize, height: mockButtonGlyphSize)
        .padding(theme.space.snug)
        .background(theme.colors.ink.opacity(mockButtonGroundOpacity), in: .capsule)

      Circle()
        .fill(theme.colors.vermilion)
        .frame(width: mockButtonDotSize, height: mockButtonDotSize)
    }
    .scaleEffect(isLifted ? mockButtonLiftedScale : 1)
    .animation(.easeOut(duration: 0.12), value: isLifted)
    // **Before `.position`, deliberately.** A positioned view takes the whole space it is
    // offered and places its child inside it, so a frame read after it is the screen —
    // and a window told the button is the screen swallows every touch in the app.
    .onGeometryChange(for: CGRect.self) { proxy in
      proxy.frame(in: .global)
    } action: { frame in
      onFrameChange(frame)
    }
    // One gesture, not two racing: the hold-then-drag if the press lasts, the tap if it
    // does not. A tap and a hold on the same view as separate gestures leave the tap to
    // lose whenever the finger lingers, which on a button this small is often.
    .gesture(pressGesture)
    .position(center)
    .accessibilityLabel("Mock device controls")
    .accessibilityHint("Double-tap to open. Press and hold, then drag to move.")
  }

  /// One gesture for both things a finger can do here, told apart by time rather than by
  /// composing a tap with a long press — composed, the two race, and on a button this
  /// small the tap loses whenever the finger lingers.
  ///
  /// Touch-down arms ``lift``. If the finger is still down when it fires, the button is
  /// picked up and every move after that carries it; touch-up then pins it. If the finger
  /// comes up first, and did not travel, it was a tap.
  private var pressGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        if !isPressed {
          isPressed = true
          lift = Task { @MainActor in
            try? await Task.sleep(for: .seconds(mockButtonHoldSeconds))
            guard !Task.isCancelled, isPressed else { return }
            isLifted = true
          }
        }
        if isLifted {
          dragOffset = value.translation
        }
      }
      .onEnded { value in
        lift?.cancel()
        lift = nil
        defer {
          isPressed = false
          isLifted = false
          dragOffset = .zero
        }
        if isLifted {
          let landed = CGPoint(
            x: pinnedPoint.x + value.translation.width,
            y: pinnedPoint.y + value.translation.height
          )
          onMove(MockDeviceButton.pin(landed, in: bounds))
        } else if abs(value.translation.width) < mockButtonTapSlop,
          abs(value.translation.height) < mockButtonTapSlop
        {
          onTap()
        }
      }
  }

  private var pinnedPoint: CGPoint {
    CGPoint(x: position.x * bounds.width, y: position.y * bounds.height)
  }

  /// Where a dropped button is pinned: the point it was dropped at, kept far enough inside
  /// the bounds that the whole button stays on screen.
  static func pin(_ point: CGPoint, in bounds: CGSize) -> MockDeviceButtonPosition {
    guard bounds.width > 0, bounds.height > 0 else { return .initial }
    let inset = mockButtonSize / 2 + BirdSpotterSpacing().separate
    let x = min(max(point.x, inset), bounds.width - inset) / bounds.width
    let y = min(max(point.y, inset), bounds.height - inset) / bounds.height
    return MockDeviceButtonPosition(x: x, y: y)
  }
}

/// The glyph's box, and what the capsule adds around it — together the button's footprint.
private let mockButtonGlyphSize: CGFloat = 20
let mockButtonSize: CGFloat = mockButtonGlyphSize + BirdSpotterSpacing().snug * 2

/// The dot: small enough to sit on the capsule's shoulder, big enough to be red from a
/// distance.
private let mockButtonDotSize: CGFloat = 8

/// How dark the capsule is — the one depth this app gives chrome laid over a picture.
private let mockButtonGroundOpacity: Double = 0.6

/// How long a press has to be before it lifts the button rather than opening the panel.
private let mockButtonHoldSeconds: Double = 0.35

/// How far a finger may travel and still have tapped.
private let mockButtonTapSlop: CGFloat = 10

/// How much a lifted button grows — enough to say *picked up*, not enough to hide what is under it.
private let mockButtonLiftedScale: CGFloat = 1.15

#Preview("Button") {
  GeometryReader { proxy in
    MockDeviceButton(
      position: .initial,
      bounds: proxy.size,
      onTap: {},
      onMove: { _ in },
      onFrameChange: { _ in }
    )
  }
  .birdSpotterTheme()
}
