/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MockDeviceCardView.swift
//
// UI component for managing individual mock Meta wearable devices during development.
// This card provides controls for simulating device states (power, wearing, folding)
// and loading mock media content for testing DAT SDK streaming and photo capture features.
// Useful for testing without requiring physical Meta hardware.
//

#if DEBUG

import MWDATMockDevice
import SwiftUI

struct MockDeviceCardView: View {
  @ObservedObject var viewModel: ViewModel
  let onUnpairDevice: () -> Void
  @State private var showingVideoPicker = false
  @State private var showingImagePicker = false
  @State private var expanded = true

  private var isCameraSourceSelected: Bool {
    viewModel.cameraSource == .front || viewModel.cameraSource == .back
  }

  var body: some View {
    CardView {
      VStack(spacing: 0) {
        // Header: device name + unpair, tappable to expand/collapse
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.deviceName)
              .font(.headline)
              .fontWeight(.semibold)
              .foregroundColor(.primary)
              .lineLimit(1)
              .truncationMode(.tail)
            Text(viewModel.id)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }

          Spacer()

          MockDeviceKitButton("Unpair", style: .destructive, expandsHorizontally: false) {
            onUnpairDevice()
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation {
            expanded.toggle()
          }
        }

        // Collapsible content
        if expanded {
          Divider()
            .padding(.vertical, 4)

          VStack(spacing: 8) {
            // Toggle switches
            VStack(spacing: 0) {
              Toggle(
                "Power",
                isOn: Binding(
                  get: { viewModel.isPoweredOn },
                  set: { newValue in
                    if newValue { viewModel.powerOn() } else { viewModel.powerOff() }
                  }
                )
              )
              .frame(height: 36)

              Toggle(
                "Donned",
                isOn: Binding(
                  get: { viewModel.isDonned },
                  set: { newValue in
                    if newValue { viewModel.don() } else { viewModel.doff() }
                  }
                )
              )
              .frame(height: 36)

              Toggle(
                "Unfolded",
                isOn: Binding(
                  get: { viewModel.isUnfolded },
                  set: { newValue in
                    if newValue { viewModel.unfold() } else { viewModel.fold() }
                  }
                )
              )
              .frame(height: 36)
            }

            // Camera source picker
            CameraSourcePicker(
              cameraSource: viewModel.cameraSource,
              hasCameraFeed: viewModel.hasCameraFeed,
              onFrontCamera: { viewModel.setCameraFeed(.front) },
              onBackCamera: { viewModel.setCameraFeed(.back) },
              onVideoFile: { showingVideoPicker = true }
            )
            .sheet(isPresented: $showingVideoPicker) {
              MediaPickerView(mode: .video) { url, _ in
                viewModel.selectVideo(from: url)
              }
            }

            // Captured image control — hidden when a camera source (front/back) is selected
            if !isCameraSourceSelected {
              if viewModel.hasCapturedImage {
                Text("Has captured image")
                  .font(.caption)
                  .foregroundColor(.green)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }

              MockDeviceKitButton("Select image") {
                showingImagePicker = true
              }
              .sheet(isPresented: $showingImagePicker) {
                MediaPickerView(mode: .image) { url, _ in
                  viewModel.selectImage(from: url)
                }
              }
            }
          }
        }
      }
      .padding()
    }
  }
}

private struct CameraSourcePicker: View {
  let cameraSource: CameraFacing?
  let hasCameraFeed: Bool
  let onFrontCamera: () -> Void
  let onBackCamera: () -> Void
  let onVideoFile: () -> Void

  private var currentSourceLabel: String {
    if let source = cameraSource {
      return source == .front ? "Front Camera" : "Back Camera"
    } else if hasCameraFeed {
      return "Video File"
    }
    return "None"
  }

  var body: some View {
    Menu {
      Button("Front Camera") { onFrontCamera() }
      Button("Back Camera") { onBackCamera() }
      Button("Video File") { onVideoFile() }
    } label: {
      HStack {
        Text("Camera Source: \(currentSourceLabel)")
          .font(.body)
          .foregroundColor(.primary)
        Spacer()
        Image(systemName: "chevron.down")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 12)
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
      )
    }
  }
}

// Replace this with PhotosPicker once we're on iOS 16 or newer

#endif
