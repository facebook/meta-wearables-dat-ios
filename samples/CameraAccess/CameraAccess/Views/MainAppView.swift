/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MainAppView.swift
//
// Central navigation hub that displays different views based on DAT SDK registration and device states.
// When unregistered, shows the registration flow. When registered, shows the device selection screen
// for choosing which Meta wearable device to stream from.
//

import MWDATCore
import SwiftUI

struct MainAppView: View {
  let wearables: WearablesInterface
  @ObservedObject private var viewModel: WearablesViewModel
  @State private var showingRegistration: Bool = false
  @State private var hasCompletedGettingStarted: Bool = false

  init(wearables: WearablesInterface, viewModel: WearablesViewModel) {
    self.wearables = wearables
    self.viewModel = viewModel
  }

  var body: some View {
    if viewModel.registrationState == .registered || viewModel.hasMockDevice {
      if hasCompletedGettingStarted {
        // Show streaming view (permission already granted)
        StreamSessionView(wearables: wearables, wearablesVM: viewModel)
      } else {
        // Show getting started page to request camera permission
        GettingStartedView(wearables: wearables, wearablesVM: viewModel) {
          hasCompletedGettingStarted = true
        }
      }
    } else if showingRegistration {
      // Show registration/onboarding flow
      HomeScreenView(viewModel: viewModel) {
        showingRegistration = false
      }
    } else {
      // Show welcome screen
      WelcomeView {
        showingRegistration = true
      }
    }
  }
}
