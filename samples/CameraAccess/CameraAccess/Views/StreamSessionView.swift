/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI

enum SessionPage {
  case ready      // NonStreamView - waiting to start
  case active     // StreamView - session in progress
  case dashboard  // DashboardView - post-session report
}

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @State private var currentPage: SessionPage = .ready

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    ZStack {
      switch currentPage {
      case .ready:
        // Pre-study setup view with start button
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel)
          .onReceive(viewModel.$isStudySessionActive) { isActive in
            if isActive {
              withAnimation {
                currentPage = .active
              }
            }
          }
        
      case .active:
        // Study session in progress
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, onSessionEnd: {
          withAnimation {
            currentPage = .dashboard
          }
        })
        
      case .dashboard:
        // Post-session dashboard
        DashboardView(onBack: {
          withAnimation {
            currentPage = .ready
          }
        })
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
