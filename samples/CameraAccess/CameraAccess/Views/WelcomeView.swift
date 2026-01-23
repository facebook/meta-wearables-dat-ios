/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// WelcomeView.swift
//
// Initial welcome screen displayed when the app launches and the user is not registered.
// Introduces the user to Reality Hack before proceeding to the registration flow.
//

import SwiftUI

struct WelcomeView: View {
  let onContinue: () -> Void

  var body: some View {
    ZStack {
      Color.white.edgesIgnoringSafeArea(.all)

      VStack(spacing: 12) {
        Spacer()

        Image(.cameraAccessIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)

        VStack(spacing: 16) {
          Text("Welcome to Reality Hack")
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)

          Text("Get ready to connect your Meta glasses and experience augmented reality like never before.")
            .font(.system(size: 15))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)

        Spacer()

        CustomButton(
          title: "Continue to Registration",
          style: .primary,
          isDisabled: false
        ) {
          onContinue()
        }
      }
      .padding(.all, 24)
    }
  }
}
