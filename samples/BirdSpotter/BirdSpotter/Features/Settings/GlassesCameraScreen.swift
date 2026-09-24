/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesCameraScreen.swift
//  birdspotter
//

import ImageIO
import SwiftUI

/// Camera — one photograph at chosen settings, and what it cost.
///
/// Pushed from the glasses settings screen. The session opens with the screen; the two
/// pickers set what the next shutter asks for; the result arrives with its size, its bytes
/// and its crossing time printed beside it, and the share sheet is how it leaves the phone.
/// See ``GlassesCameraViewModel`` for why the screen exists at all.
struct GlassesCameraScreen: View {
  @State private var model: GlassesCameraViewModel

  init(
    glassesSession: any GlassesSessionRepository,
    glassesCamera: any GlassesCameraRepository,
    scratch: CaptureScratchStore
  ) {
    _model = State(
      initialValue: GlassesCameraViewModel(
        glassesSession: glassesSession,
        glassesCamera: glassesCamera,
        scratch: scratch
      )
    )
  }

  var body: some View {
    GlassesCameraContent(
      uiState: model.uiState,
      onPickResolution: { model.choose(resolution: $0) },
      onPickQuality: { model.choose(quality: $0) },
      onCapture: { model.capturePhoto() },
      onRetry: { model.start() }
    )
    .task { model.start() }
    // The run is the screen's, not the navigation stack's: walking away hangs up, and
    // drops a crossing still in the air with it.
    .onDisappear { model.stop() }
  }
}

/// The drawing, taking a reading rather than a repository.
private struct GlassesCameraContent: View {
  @Environment(\.theme) private var theme

  let uiState: GlassesCameraUiState
  let onPickResolution: (CaptureResolution) -> Void
  let onPickQuality: (CaptureQuality) -> Void
  let onCapture: () -> Void
  let onRetry: () -> Void

  var body: some View {
    ScrollView {
      // Per-child padding and no `spacing:`, deliberately — the rhythm down this page
      // is not uniform, and setting both would add the two together.
      VStack(alignment: .leading, spacing: 0) {
        sessionSection

        settingsSection
          .padding(.top, theme.space.section)

        shutterSection
          .padding(.top, theme.space.section)

        if let shot = uiState.shot {
          resultSection(shot)
            .padding(.top, theme.space.section)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.separate)
      .padding(.bottom, theme.space.page)
    }
    .background(theme.colors.paper)
    .navigationTitle("Camera")
    .navigationBarTitleDisplayMode(.inline)
  }

  /// Where the session stands, and whether the grant the shutter needs is in hand.
  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Session", color: theme.colors.gilt)

      readingRow(label: "Glasses", value: sessionValue)
      readingRow(label: "Camera access", value: accessValue, support: accessSupport)

      if let failure = uiState.failure {
        // In the page's own ink rather than a red: the palette spends its one red on
        // controls that end something, and a line explaining why the session ended is
        // a statement, not a control.
        Text(failure)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
      }

      if !uiState.isRunning {
        ActionButton(title: "Reconnect", action: onRetry)
      }
    }
  }

  /// The two knobs the SDK sells, and — where they do not reach the capture — the one line
  /// that says so before anybody spends an afternoon comparing identical photographs.
  private var settingsSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Settings", color: theme.colors.gilt)

      if !uiState.honoursCaptureSettings {
        Text(
          "This build's captures travel a channel that takes neither setting, so "
            + "both pickers are inert: every photograph below comes back at "
            + "whatever the transport sends."
        )
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textPrimary)
      }

      pickerRow(
        title: "Resolution",
        support: "How much of the sensor is kept. The expensive knob."
      ) {
        ForEach(CaptureResolution.allCases) { resolution in
          settingChip(
            title: resolution.displayLabel,
            isOn: uiState.resolution == resolution
          ) {
            onPickResolution(resolution)
          }
        }
      }

      pickerRow(
        title: "Quality",
        support: "How hard it is compressed. Same pixels, fewer bytes."
      ) {
        ForEach(CaptureQuality.allCases) { quality in
          settingChip(title: quality.displayLabel, isOn: uiState.quality == quality) {
            onPickQuality(quality)
          }
        }
      }
    }
    // The pickers stay tappable when they are inert: what they set is still what the
    // request carries, and the note above already says where it stops.
    .opacity(uiState.honoursCaptureSettings ? 1 : 0.6)
  }

  /// The shutter, and the crossing.
  ///
  /// **The wait is a row, not a dimmed button.** The Bluetooth crossing is about a second
  /// and sometimes several, and greying out the control somebody just pressed reads as
  /// broken rather than as working.
  private var shutterSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      ActionButton(title: "Take photo", action: onCapture)
        .disabled(uiState.sessionState != .started)
        .opacity(uiState.sessionState == .started ? 1 : 0.5)

      if uiState.isCapturing {
        HStack(spacing: theme.space.snug) {
          // The watcher's own photograph still arriving, so not gilt: gilt dots
          // are the app composing an answer.
          WorkingDots(color: theme.colors.textSecondary)
            .frame(width: workingDotsWidth, height: workingDotsHeight)
          Text("Receiving from the glasses…")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }

      if let captureFailure = uiState.captureFailure {
        Text(captureFailure)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
      }
    }
  }

  /// The photograph, and the three numbers that are the reason to have taken it.
  private func resultSection(_ shot: GlassesCameraShot) -> some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Last photograph", color: theme.colors.gilt)

      ShotImage(url: shot.fileURL)
        .frame(maxWidth: .infinity)
        .frame(height: shotHeight)
        .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .strokeBorder(theme.colors.rule, lineWidth: 1)
        }

      // Wrapping rather than scrolling: five short chips on a 390-point phone are two
      // rows, and a row that scrolls sideways hides the number at the end of it.
      FlowLayout(spacing: theme.space.snug) {
        Chip(text: shot.resolution.displayLabel, tone: .input)
        Chip(text: shot.quality.displayLabel, tone: .input)
        if let pixels = Self.pixelLabel(shot) {
          Chip(text: pixels)
        }
        Chip(text: Self.byteLabel(shot.byteCount))
        Chip(text: Self.crossingLabel(shot.crossingMillis), tone: .answer)
      }

      // The one way a photograph leaves the phone. The sheet's **Save Image** is what
      // puts it in the camera roll; everything else in the sheet is the same file going
      // somewhere else.
      ShareLink(item: shot.fileURL) {
        Text("Save or share")
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.verdigris)
          .padding(.vertical, theme.space.related)
          .padding(.horizontal, theme.space.cardInset)
          .frame(maxWidth: .infinity, minHeight: RowMetrics.minTapHeight)
          .overlay {
            RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
              .strokeBorder(theme.colors.verdigris, lineWidth: 1)
          }
          .contentShape(Rectangle())
      }
    }
  }

  /// What the session is doing, in the words the pill on the realtime screen uses — one
  /// vocabulary for the link across the app, so a reading here is comparable with a
  /// reading there.
  private var sessionValue: String {
    switch uiState.sessionState {
    case .starting: "Connecting"
    case .started: "Connected"
    case .paused: "Paused"
    case .stopping: "Stopping"
    case .stopped: "Stopped"
    case nil: uiState.isRunning ? "Connecting" : "Not started"
    }
  }

  private var accessValue: String {
    switch uiState.cameraAccess {
    case .granted: "Granted"
    case .denied: "Denied"
    case .unknown: "Unknown"
    case nil: "—"
    }
  }

  /// Only the readings that change what the shutter will do explain themselves. The grant
  /// is given in the Meta AI app, which is where this points rather than at a button that
  /// cannot be offered from here.
  private var accessSupport: String? {
    switch uiState.cameraAccess {
    case .denied:
      "Meta AI has not been given the camera — grant it on the Meta AI Glasses screen"
    case .unknown:
      "Meta AI can only answer this over a live link — connect your glasses"
    case .granted, nil:
      nil
    }
  }

  private func pickerRow(
    title: String,
    support: String,
    @ViewBuilder chips: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: theme.space.snug) {
      Text(title)
        .font(theme.type.headline)
        .foregroundStyle(theme.colors.textPrimary)
      Text(support)
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
      FlowLayout(spacing: theme.space.snug) {
        chips()
      }
    }
  }

  /// A ``Chip`` wearing a tap. The tone carries the state — `answer` is the gilt the app
  /// names things in, which is what a chosen setting is.
  private func settingChip(
    title: String,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Chip(text: title, tone: isOn ? .answer : .neutral)
    }
    .buttonStyle(.plain)
  }

  private func readingRow(label: String, value: String, support: String? = nil) -> some View {
    HStack(spacing: theme.space.related) {
      VStack(alignment: .leading) {
        Text(label)
          .font(theme.type.headline)
          .foregroundStyle(theme.colors.textPrimary)
        if let support {
          Text(support)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
        }
      }
      Spacer()
      Text(value)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }

  /// The image's own size, when the file could be read. `nil` is not an error worth a line
  /// of its own — the photograph is on screen above it, which is the better evidence.
  private static func pixelLabel(_ shot: GlassesCameraShot) -> String? {
    guard let width = shot.pixelWidth, let height = shot.pixelHeight else { return nil }
    return "\(width) × \(height)"
  }

  /// Bytes in the phone's own units, which is what the wearer will compare against
  /// everything else on their phone.
  private static func byteLabel(_ byteCount: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
  }

  /// **Milliseconds under a second, seconds above it.** A crossing is the number this
  /// screen exists to produce, and `0.8 s` throws away the digit that distinguishes a fast
  /// link from a very fast one while `1847 ms` makes a slow one hard to feel.
  private static func crossingLabel(_ millis: Int) -> String {
    guard millis >= 1_000 else { return "\(millis) ms" }
    let seconds = Double(millis / 100) / 10
    return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
  }
}

/// The captured file, decoded off the main thread at roughly the size it will be drawn.
///
/// The same ImageIO thumbnail decode ``OutingPhoto`` uses, and for the same reason: a
/// full-size still is several megapixels, and a screen that decodes all of them to draw a
/// 320-point frame stutters on the one beat it most wants to feel smooth.
private struct ShotImage: View {
  @Environment(\.theme) private var theme

  let url: URL

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          // Fitted, not filled: the framing is what a capture test is looking at,
          // and a crop would take the edges away without saying so.
          .aspectRatio(contentMode: .fit)
      } else {
        theme.colors.rule
      }
    }
    .accessibilityLabel("The photograph the glasses sent")
    .task(id: url) {
      image = await Self.load(url: url)
    }
  }

  private static func load(url: URL) async -> UIImage? {
    await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: shotDecodeWidthPx,
      ]
      guard
        let cgImage = CGImageSourceCreateThumbnailAtIndex(
          source, 0, options as CFDictionary
        )
      else { return nil }
      return UIImage(cgImage: cgImage)
    }.value
  }
}

/// How tall the photograph is drawn. Big enough that feather detail is arguable at arm's
/// length, which is the whole reason somebody is comparing two of these.
private let shotHeight: CGFloat = 280

/// What the file is decoded to. Generous against the tallest phone at 3× rather than sized
/// to ``shotHeight``, so the picture is not the soft thing in a comparison about sharpness.
private nonisolated let shotDecodeWidthPx = 1_200

/// The dots' canvas. It draws to fill whatever it is given, and a wait beside a line of body
/// text wants to be about that line's height.
private let workingDotsWidth: CGFloat = 28
private let workingDotsHeight: CGFloat = 8

/// Mid-experiment: connected, the grant in hand, and a large photograph back with its numbers.
#Preview("A photograph back") {
  NavigationStack {
    GlassesCameraContent(
      uiState: GlassesCameraUiState(
        isRunning: true,
        sessionState: .started,
        cameraAccess: .granted,
        resolution: .large,
        quality: .high,
        shot: GlassesCameraShot(
          fileURL: URL(fileURLWithPath: "/dev/null/glasses-large-high-3.jpg"),
          resolution: .large,
          quality: .high,
          byteCount: 1_284_331,
          pixelWidth: 2_592,
          pixelHeight: 1_944,
          crossingMillis: 4_120
        )
      ),
      onPickResolution: { _ in },
      onPickQuality: { _ in },
      onCapture: {},
      onRetry: {}
    )
  }
  .birdSpotterTheme()
}

/// The beat the feature doc is about: the shutter fired, the picture still crossing, and the
/// control that was pressed still looking pressable.
#Preview("Crossing") {
  NavigationStack {
    GlassesCameraContent(
      uiState: GlassesCameraUiState(
        isRunning: true,
        sessionState: .started,
        cameraAccess: .granted,
        isCapturing: true
      ),
      onPickResolution: { _ in },
      onPickQuality: { _ in },
      onCapture: {},
      onRetry: {}
    )
  }
  .birdSpotterTheme()
}

/// The reading that matters: two pickers that cannot reach the capture, saying so before
/// anybody compares two identical photographs and concludes the glasses are broken.
#Preview("Settings not honoured") {
  NavigationStack {
    GlassesCameraContent(
      uiState: GlassesCameraUiState(
        isRunning: true,
        sessionState: .started,
        cameraAccess: .granted,
        honoursCaptureSettings: false
      ),
      onPickResolution: { _ in },
      onPickQuality: { _ in },
      onCapture: {},
      onRetry: {}
    )
  }
  .birdSpotterTheme()
}
