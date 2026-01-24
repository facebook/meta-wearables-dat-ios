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

enum AppFlowPage {
  case splash
  case onboarding
  case welcome
  case registration
  case gettingStarted
  case session
}

struct MainAppView: View {
  let wearables: WearablesInterface
  @ObservedObject private var viewModel: WearablesViewModel
  @State private var currentPage: AppFlowPage = .splash

  init(wearables: WearablesInterface, viewModel: WearablesViewModel) {
    self.wearables = wearables
    self.viewModel = viewModel
  }
  
  // Check if user is already registered
  private var isRegistered: Bool {
    viewModel.registrationState == .registered || viewModel.hasMockDevice
  }

  var body: some View {
    ZStack {
      // Background
      Color.black.ignoresSafeArea()
      
      // Content based on current page
      switch currentPage {
      case .splash:
        SplashView2 {
          withAnimation {
            // Always go to onboarding first
            currentPage = .onboarding
          }
        }
        
      case .onboarding:
        OnboardingView {
          withAnimation {
            // After onboarding, check if already registered
            if isRegistered {
              // Skip straight to getting started if already registered
              currentPage = .gettingStarted
            } else {
              currentPage = .welcome
            }
          }
        }
        
      case .welcome:
        WelcomeView {
          withAnimation {
            // If already registered, skip registration
            if isRegistered {
              currentPage = .gettingStarted
            } else {
              currentPage = .registration
            }
          }
        }
        
      case .registration:
        HomeScreenView(viewModel: viewModel) {
          withAnimation {
            currentPage = .gettingStarted
          }
        }
        
      case .gettingStarted:
        GettingStartedView(wearables: wearables, wearablesVM: viewModel) {
          withAnimation {
            currentPage = .session
          }
        }
        
      case .session:
        StreamSessionView(wearables: wearables, wearablesVM: viewModel)
      }
    }
    .preferredColorScheme(.dark)
    // Auto-navigate when registration state changes
    .onChange(of: viewModel.registrationState) { oldState, newState in
      // If user becomes registered while on registration page, move forward
      if newState == .registered && currentPage == .registration {
        withAnimation {
          currentPage = .gettingStarted
        }
      }
      // If user becomes registered while on welcome page, skip registration
      if newState == .registered && currentPage == .welcome {
        withAnimation {
          currentPage = .gettingStarted
        }
      }
    }
  }
}
