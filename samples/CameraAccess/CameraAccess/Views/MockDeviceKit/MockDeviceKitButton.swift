/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MockDeviceKitButton.swift
//
// Specialized button component for mock device controls in the debug interface.
//

#if DEBUG

import SwiftUI

struct MockDeviceKitButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  var backgroundColor: Color
  var foregroundColor: Color = .white
  var isFullWidth: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundColor(foregroundColor.opacity(isEnabled ? 1.0 : 0.6))
      .padding(.horizontal)
      .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: 44)
      .background(backgroundColor.opacity(isEnabled ? 1.0 : 0.4))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .opacity(configuration.isPressed ? 0.8 : 1.0)
  }
}

struct MockDeviceKitButton: View {
  enum Style {
    case primary
    case destructive

    var backgroundColor: Color {
      switch self {
      case .primary:
        return .appPrimary
      case .destructive:
        return .red
      }
    }
  }

  let title: String
  let style: Style
  let expandsHorizontally: Bool
  let disabled: Bool
  let action: () -> Void

  init(_ title: String, style: Style = .primary, expandsHorizontally: Bool = true, disabled: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.style = style
    self.expandsHorizontally = expandsHorizontally
    self.disabled = disabled
    self.action = action
  }

  var body: some View {
    Button(title) {
      action()
    }
    .buttonStyle(
      MockDeviceKitButtonStyle(
        backgroundColor: style.backgroundColor,
        isFullWidth: expandsHorizontally
      )
    )
    .disabled(disabled)
  }
}

#endif
