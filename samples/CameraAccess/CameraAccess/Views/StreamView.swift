/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var sessionManager = StudySessionManager.shared
  var onSessionEnd: () -> Void

  var body: some View {
    ZStack {
      // Black background
      Color.black
        .edgesIgnoringSafeArea(.all)

      VStack {
        Spacer()
        
        // Study in progress message
        VStack(spacing: 16) {
          Image(.cameraAccessIcon)
            .resizable()
            .renderingMode(.template)
            .foregroundColor(.white)
            .aspectRatio(contentMode: .fit)
            .frame(width: 80)
          
          Text("Studying in progress")
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
          
          // Study cycle status
          Text(viewModel.studyCycleStatusText)
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.7))
            .multilineTextAlignment(.center)
          
          // Photo capture and upload stats
          HStack(spacing: 16) {
            VStack(spacing: 4) {
              Text("\(viewModel.photoCaptureCount)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
              Text("Captured")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            }
            
            VStack(spacing: 4) {
              Text("\(sessionManager.uploadSuccessCount)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.green)
              Text("Uploaded")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            }
            
            if sessionManager.uploadFailureCount > 0 {
              VStack(spacing: 4) {
                Text("\(sessionManager.uploadFailureCount)")
                  .font(.system(size: 24, weight: .bold))
                  .foregroundColor(.red)
                Text("Failed")
                  .font(.system(size: 12))
                  .foregroundColor(.white.opacity(0.5))
              }
            }
          }
          .padding(.top, 8)
          
          // Latest analysis result
          if let analysis = sessionManager.lastAnalysis {
            VStack(spacing: 8) {
              Divider()
                .background(Color.white.opacity(0.3))
                .padding(.vertical, 8)
              
              if let topic = analysis.topic {
                HStack {
                  Text("Topic:")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                  Text(topic)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                }
              }
              
              if let subtopic = analysis.subtopic {
                Text(subtopic)
                  .font(.system(size: 12))
                  .foregroundColor(.white.opacity(0.6))
                  .multilineTextAlignment(.center)
              }
              
              if let isStudying = analysis.is_studying {
                HStack(spacing: 6) {
                  Circle()
                    .fill(isStudying ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                  Text(isStudying ? "Studying detected" : "Not studying")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                }
              }
            }
            .padding(.horizontal, 16)
          }
          
          // Connection and upload status
          VStack(spacing: 4) {
            // Server connection status
            HStack(spacing: 6) {
              Circle()
                .fill(sessionManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
              Text(sessionManager.isConnected ? "Connected to server" : "Not connected to server")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            }
            
            // Last upload status
            if let lastSuccess = sessionManager.lastUploadSuccess {
              HStack(spacing: 6) {
                Image(systemName: lastSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                  .foregroundColor(lastSuccess ? .green : .red)
                  .font(.system(size: 14))
                Text(lastSuccess ? "Last upload successful" : "Last upload failed")
                  .font(.system(size: 12))
                  .foregroundColor(.white.opacity(0.6))
              }
            }
            
            // Error message if any
            if let error = sessionManager.lastError {
              Text(error)
                .font(.system(size: 10))
                .foregroundColor(.red.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }
          }
          .padding(.top, 4)
        }
        
        Spacer()

        // End studying button at the bottom
        CustomButton(
          title: "End studying",
          style: .destructive,
          isDisabled: false
        ) {
          Task {
            await viewModel.stopStudySession()
            onSessionEnd()
          }
        }
      }
      .padding(.all, 24)
    }
  }
}
