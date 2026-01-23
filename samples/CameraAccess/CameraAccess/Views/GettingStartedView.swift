/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// GettingStartedView.swift
//
// Getting started page shown after connecting glasses.
// Explains camera permissions and requests them before proceeding to streaming.
//

import MWDATCore
import SwiftUI

struct GettingStartedView: View {
  let wearables: WearablesInterface
  @ObservedObject var wearablesVM: WearablesViewModel
  let onContinue: () -> Void
  
  @State private var isRequestingPermission: Bool = false

  var body: some View {
    ZStack {
      Color.white.edgesIgnoringSafeArea(.all)

      VStack(spacing: 12) {
        // Top menu bar
        HStack {
          Spacer()
          Menu {
            Button {
              // TODO: Implement study history view
            } label: {
              Label("View your study history", systemImage: "clock.arrow.circlepath")
            }
            
            Button("Disconnect", role: .destructive) {
              wearablesVM.disconnectGlasses()
            }
            .disabled(wearablesVM.registrationState != .registered)
          } label: {
            Image(systemName: "ellipsis.circle")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(.black)
              .frame(width: 24, height: 24)
          }
        }
        .padding(.top, 8)

        Spacer()

        Image(.cameraAccessIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)

        VStack(spacing: 16) {
          Text("Getting Started")
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 24)

        VStack(spacing: 12) {
          GettingStartedTipItemView(
            resource: .videoIcon,
            text: "First, Camera Access needs permission to use your glasses camera."
          )
          GettingStartedTipItemView(
            resource: .tapIcon,
            text: "Capture photos by tapping the camera button."
          )
          GettingStartedTipItemView(
            resource: .smartGlassesIcon,
            text: "The capture LED lets others know when you're capturing content or going live."
          )
        }
        .padding(.top, 16)

        Spacer()

        VStack(spacing: 20) {
          Text("You'll be redirected to the Meta AI app to grant camera permission.")
            .font(.system(size: 14))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

          CustomButton(
            title: isRequestingPermission ? "Requesting permission..." : "Continue",
            style: .primary,
            isDisabled: isRequestingPermission
          ) {
            Task {
              await requestCameraPermissionAndContinue()
            }
          }
        }
      }
      .padding(.all, 24)
    }
  }
  
  private func requestCameraPermissionAndContinue() async {
    isRequestingPermission = true
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        // Already granted, proceed
        onContinue()
        return
      }
      // Request permission - user will be taken to Meta AI app
      let result = try await wearables.requestPermission(permission)
      if result == .granted {
        onContinue()
      } else {
        wearablesVM.showError("Camera permission is required to stream from your glasses.")
      }
    } catch {
      wearablesVM.showError("Permission error: \(error)")
    }
    isRequestingPermission = false
  }
}

struct GettingStartedTipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.black)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundColor(.gray)
        .fixedSize(horizontal: false, vertical: true)
      
      Spacer()
    }
  }
}
