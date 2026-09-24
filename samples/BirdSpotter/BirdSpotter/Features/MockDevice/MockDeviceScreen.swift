/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MockDeviceScreen.swift
//  birdspotter
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Mock Device Kit's controls, one section per capability the simulated pair has.
///
/// Laid over the running app rather than pushed onto a stack, so the thing being driven —
/// the realtime session, the glasses screen, the display gallery — stays exactly where it was
/// while the controls are up, and is back the moment they close. Every control is one call on
/// the kit and reads back what it was last set to; nothing here has state of its own beyond
/// the two file pickers.
struct MockDeviceScreen: View {
  @Environment(\.theme) private var theme

  let model: MockDeviceViewModel
  let onClose: () -> Void

  @State private var isPickingVideo = false
  @State private var isPickingPhoto = false

  var body: some View {
    VStack(spacing: 0) {
      header
      HairlineRule()
      ScrollView {
        VStack(alignment: .leading, spacing: theme.space.section) {
          kitSection
          if model.uiState.hasSelection {
            deviceSection
            grantsSection
            cameraSection
            inputsSection
            speechSection
            motionSection
            if model.uiState.selectedDevice?.model.hasDisplay == true {
              displaySection
            }
            voiceSection
          }
          if let notice = model.uiState.notice {
            Text(notice)
              .font(theme.type.caption)
              .foregroundStyle(theme.colors.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.space.gutter)
        .padding(.vertical, theme.space.separate)
      }
    }
    // Under the status bar and the home indicator too: this is laid over the app, and
    // the app must not show through at the edges.
    .background(theme.colors.paper.ignoresSafeArea())
    .fileImporter(isPresented: $isPickingVideo, allowedContentTypes: [.movie]) { result in
      if case .success(let url) = result { model.useCameraFeed(url) }
    }
    .fileImporter(isPresented: $isPickingPhoto, allowedContentTypes: [.image]) { result in
      if case .success(let url) = result { model.useCapturedPhoto(url) }
    }
  }

  private var header: some View {
    HStack(spacing: theme.space.related) {
      Text("Mock Device Kit")
        .font(theme.type.title)
        .foregroundStyle(theme.colors.textPrimary)
      Spacer()
      Button(action: onClose) {
        Image(glyph: theme.glyphs.close)
          .foregroundStyle(theme.colors.textSecondary)
          .frame(width: RowMetrics.minTapHeight, height: RowMetrics.minTapHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close")
    }
    .padding(.leading, theme.space.gutter)
    .padding(.trailing, theme.space.snug)
    .padding(.vertical, theme.space.snug)
  }

  // MARK: Kit

  private var kitSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Kit", color: theme.colors.gilt)

      Toggle(
        isOn: Binding(
          get: { model.uiState.isEnabled },
          set: { model.setEnabled($0) }
        )
      ) {
        VStack(alignment: .leading, spacing: theme.space.tight) {
          Text("Simulate the glasses")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textPrimary)
          Text("Off puts the real SDK back. Any running session ends first.")
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      .tint(theme.colors.verdigris)
      .disabled(model.uiState.isFlipping)

      Text("Model for the next pair")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
      choiceRow(MockGlassesModel.allCases, current: model.uiState.model, label: \.displayName) {
        model.choose(model: $0)
      }

      ActionButton(title: "Pair \(model.uiState.model.displayName)") { model.pair() }

      if !model.uiState.devices.isEmpty {
        Text("Paired")
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
        FlowLayout(spacing: theme.space.snug) {
          ForEach(model.uiState.devices) { device in
            Button {
              model.select(device.id)
            } label: {
              Chip(
                text: device.model.displayName,
                tone: device.id == model.uiState.selectedDeviceId ? .answer : .neutral
              )
            }
            .buttonStyle(.plain)
          }
        }
        ActionButton(title: "Unpair selected", tone: .destructive) { model.unpair() }
      }
    }
  }

  // MARK: Device

  private var deviceSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Device", color: theme.colors.gilt)

      FlowLayout(spacing: theme.space.snug) {
        ControlButton(title: "Power on") { model.powerOn() }
        ControlButton(title: "Power off") { model.powerOff() }
        ControlButton(title: "Unfold") { model.unfold() }
        ControlButton(title: "Fold") { model.fold() }
        ControlButton(title: "Put on") { model.don() }
        ControlButton(title: "Take off") { model.doff() }
      }

      BatterySlider(level: model.uiState.batteryLevel) { model.setBatteryLevel($0) }

      Toggle(
        isOn: Binding(
          get: { model.uiState.isCharging },
          set: { model.setCharging($0) }
        )
      ) {
        Text("Charging")
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
      }
      .tint(theme.colors.verdigris)

      Text("Heat")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
      choiceRow(
        [GlassesThermalLevel.nominal, .elevated, .critical],
        current: model.uiState.thermal,
        label: { Self.thermalLabel($0) }
      ) {
        model.setThermal($0)
      }
    }
  }

  private static func thermalLabel(_ level: GlassesThermalLevel) -> String {
    switch level {
    case .nominal: "Nominal"
    case .elevated: "Elevated"
    case .critical: "Critical"
    }
  }

  // MARK: Grants

  private var grantsSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Grants", color: theme.colors.gilt)
      grantRow("Camera", access: model.uiState.cameraAccess) { model.setAccess(.camera, $0) }
      grantRow("Microphone", access: model.uiState.microphoneAccess) { model.setAccess(.microphone, $0) }
    }
  }

  private func grantRow(
    _ title: String,
    access: GlassesAccess,
    onSet: @escaping (GlassesAccess) -> Void
  ) -> some View {
    Toggle(
      isOn: Binding(
        get: { access == .granted },
        set: { onSet($0 ? .granted : .denied) }
      )
    ) {
      Text(title)
        .font(theme.type.headline)
        .foregroundStyle(theme.colors.textPrimary)
    }
    .tint(theme.colors.verdigris)
  }

  // MARK: Camera

  private var cameraSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Camera", color: theme.colors.gilt)
      Text("What the stream shows, and what a capture comes back with. Video must be H.265.")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
      FlowLayout(spacing: theme.space.snug) {
        ControlButton(title: "Phone camera, back") { model.usePhoneCamera(.back) }
        ControlButton(title: "Phone camera, front") { model.usePhoneCamera(.front) }
        ControlButton(title: "Video file…") { isPickingVideo = true }
        ControlButton(title: "Captured photo…") { isPickingPhoto = true }
        ControlButton(title: "Fail next capture") { model.failNextCapture() }
      }
    }
  }

  // MARK: Inputs

  private var inputsSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Inputs", color: theme.colors.gilt)
      FlowLayout(spacing: theme.space.snug) {
        ControlButton(title: "Tap") { model.tap() }
        ControlButton(title: "Tap and hold") { model.tapAndHold() }
        ControlButton(title: "Swipe up") { model.navigate(.up) }
        ControlButton(title: "Swipe down") { model.navigate(.down) }
        ControlButton(title: "Swipe left") { model.navigate(.left) }
        ControlButton(title: "Swipe right") { model.navigate(.right) }
        ControlButton(title: "Select") { model.select() }
        ControlButton(title: "Back") { model.back() }
        ControlButton(title: "Capture") { model.pressCapture(.shortPress) }
        ControlButton(title: "Capture, hold") { model.pressCapture(.hold) }
        ControlButton(title: "Capture, double") { model.pressCapture(.doublePress) }
        ControlButton(title: "Action button") { model.pressActionButton() }
      }
    }
  }

  // MARK: Speech

  private var speechSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Speech", color: theme.colors.gilt)
      choiceRow(
        MockSpeechSource.allCases,
        current: model.uiState.speechSource,
        label: { $0 == .injected ? "Typed here" : "Phone's recogniser" }
      ) {
        model.setSpeechSource($0)
      }
      NotesField(
        text: model.uiState.speechText,
        onTextChange: { model.setSpeechText($0) },
        placeholder: "What the wearer says"
      )
      FlowLayout(spacing: theme.space.snug) {
        ControlButton(title: "Send partial") { model.sendTranscription(isFinal: false) }
        ControlButton(title: "Send final") { model.sendTranscription(isFinal: true) }
        ControlButton(title: "Recogniser error") { model.sendSpeechError() }
        ControlButton(title: "Complete") { model.completeSpeech() }
      }
    }
  }

  // MARK: Motion

  private var motionSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Head", color: theme.colors.gilt)
      choiceRow(MockMotionPose.allCases, current: model.uiState.pose, label: \.displayName) {
        model.setPose($0)
      }
    }
  }

  // MARK: Display

  /// The simulated panel, drawn by the kit's own renderer and kept live by it.
  ///
  /// Identified by the pair: the view belongs to the pair it was made for, so a new selection
  /// has to make a new one rather than keep showing the last pair's panel.
  private var displaySection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Display", color: theme.colors.gilt)
      MockDisplayPreview { model.displayPreview() }
        .id(model.uiState.selectedDeviceId)
        .frame(maxWidth: .infinity)
        // The panel is square; the kit's view fills whatever it is given.
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .accessibilityLabel("What the app drew on the simulated display")

      if let port = model.uiState.displayServerPort {
        let previewURL = "http://127.0.0.1:\(port)/"
        Text("Chrome preview")
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
        displayServerStep(number: 1, text: "Open the preview link in Chrome") {
          HStack(spacing: theme.space.related) {
            Text(verbatim: previewURL)
              .font(theme.type.caption.monospaced())
              .foregroundStyle(theme.colors.textSecondary)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
            ControlButton(title: "Copy") {
              UIPasteboard.general.string = previewURL
            }
          }
        }
        displayServerStep(
          number: 2,
          text: "Enable the Meta Ray-Ban Display Simulator extension in Chrome"
        ) {
          EmptyView()
        }
      }
    }
  }

  private func displayServerStep<Detail: View>(
    number: Int,
    text: String,
    @ViewBuilder detail: () -> Detail
  ) -> some View {
    HStack(alignment: .top, spacing: theme.space.related) {
      Text(verbatim: "\(number).")
        .font(theme.type.label.monospacedDigit())
        .foregroundStyle(theme.colors.gilt)

      VStack(alignment: .leading, spacing: theme.space.tight) {
        Text(text)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textPrimary)
        detail()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Voice

  private var voiceSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Voice", color: theme.colors.gilt)
      ControlButton(title: "\u{201C}Hey Meta, open BirdSpotter\u{201D}") { model.simulateVoiceLaunch() }
    }
  }

  // MARK: -

  /// One-of-many, as chips: the chosen one in the answer tone, the rest quiet.
  private func choiceRow<Choice: Hashable>(
    _ choices: [Choice],
    current: Choice,
    label: @escaping (Choice) -> String,
    onPick: @escaping (Choice) -> Void
  ) -> some View {
    FlowLayout(spacing: theme.space.snug) {
      ForEach(choices, id: \.self) { choice in
        Button {
          onPick(choice)
        } label: {
          Chip(text: label(choice), tone: choice == current ? .answer : .neutral)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// A small, squared control — the kit's verbs, set the way ``ActionButton`` is set but sized
/// to sit twelve to a row rather than one.
private struct ControlButton: View {
  @Environment(\.theme) private var theme

  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(.horizontal, theme.space.related)
        .padding(.vertical, theme.space.snug)
        .background(theme.colors.paperRaised)
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .strokeBorder(theme.colors.rule, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// The battery, as a slider that reports when the thumb is let go — not on every tick, so
/// the kit is told once per gesture rather than a hundred times.
private struct BatterySlider: View {
  @Environment(\.theme) private var theme

  let level: Int
  let onSet: (Int) -> Void

  @State private var value: Double

  init(level: Int, onSet: @escaping (Int) -> Void) {
    self.level = level
    self.onSet = onSet
    _value = State(initialValue: Double(level))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: theme.space.tight) {
      HStack {
        Text("Battery")
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
        Spacer()
        Text("\(Int(value))%")
          .font(theme.type.data)
          .foregroundStyle(theme.colors.textSecondary)
      }
      Slider(value: $value, in: 0...100, step: 1) { editing in
        if !editing { onSet(Int(value)) }
      }
      .tint(theme.colors.verdigris)
    }
  }
}

/// Hosts the kit's live view of the simulated panel. Made once per identity — the caller
/// re-identifies it when the pair changes — and never updated, because the kit keeps it current.
private struct MockDisplayPreview: UIViewRepresentable {
  let makeView: () -> UIView?

  func makeUIView(context: Context) -> UIView { makeView() ?? UIView() }
  func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview("Panel") {
  MockDeviceScreen(model: MockDeviceViewModel(mockDevice: PreviewMockDevice())) {}
    .birdSpotterTheme()
}

/// A kit that holds one pair and answers nothing — enough for a preview to lay out. Shared
/// with the Settings preview, which needs a kit to hang its switch on.
struct PreviewMockDevice: MockDeviceRepository {
  var isEnabled: Bool { true }
  func isEnabledStream() -> AsyncStream<Bool> {
    AsyncStream {
      $0.yield(true)
      $0.finish()
    }
  }
  func setEnabled(_ enabled: Bool) async {}
  func devicesStream() -> AsyncStream<[MockDeviceInfo]> {
    AsyncStream {
      $0.yield([MockDeviceInfo(id: "mock-1", model: .metaRayBanDisplay)])
      $0.finish()
    }
  }
  func pair(model: MockGlassesModel) async throws(MockDeviceError) -> MockDeviceInfo {
    MockDeviceInfo(id: "mock-2", model: model)
  }
  func unpair(_ id: String) {}
  func powerOn(_ id: String) {}
  func powerOff(_ id: String) {}
  func don(_ id: String) {}
  func doff(_ id: String) {}
  func fold(_ id: String) {}
  func unfold(_ id: String) {}
  func setBatteryLevel(_ id: String, level: Int) {}
  func setCharging(_ id: String, isCharging: Bool) {}
  func setThermal(_ id: String, level: GlassesThermalLevel) {}
  func setAccess(_ permission: GlassesPermission, _ access: GlassesAccess) {}
  func setRequestResult(_ permission: GlassesPermission, _ access: GlassesAccess) {}
  func setCameraFeed(_ id: String, fileURL: URL) {}
  func setCameraFeed(_ id: String, facing: MockCameraFacing) {}
  func setCapturedPhoto(_ id: String, fileURL: URL) {}
  func simulateCaptureFailure(_ id: String) {}
  func tap(_ id: String) {}
  func tapAndHold(_ id: String) {}
  func navigate(_ id: String, _ direction: MockNavDirection) {}
  func select(_ id: String) {}
  func back(_ id: String) {}
  func pressCapture(_ id: String, _ press: MockCapturePress) {}
  func pressActionButton(_ id: String) {}
  func setSpeechSource(_ id: String, _ source: MockSpeechSource) {}
  func simulateTranscription(_ id: String, text: String, isFinal: Bool) {}
  func simulateSpeechError(_ id: String, message: String) {}
  func simulateSpeechCompletion(_ id: String) {}
  func setMotionPose(_ id: String, _ pose: MockMotionPose) {}
  func startDisplayServer() async -> UInt16? { nil }
  func stopDisplayServer() async {}
  func displayPreview(_ id: String) -> UIView? { nil }
  func sendDisplayClick(_ id: String, identifier: String) -> Bool { false }
  func simulateVoiceLaunch(_ id: String) -> String? { nil }
}
