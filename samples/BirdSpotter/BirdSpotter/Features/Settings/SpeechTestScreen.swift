/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeechTestScreen.swift
//  birdspotter
//

import SwiftUI

/// Test ASR — a session opened to hear the wearer and print what came back, and nothing else.
///
/// Pushed from the glasses settings screen, where the rest of the hardware readings live. See
/// ``SpeechTestViewModel`` for what the three readings on it are actually diagnosing.
struct SpeechTestScreen: View {
  @State private var model: SpeechTestViewModel

  init(
    glassesSession: any GlassesSessionRepository,
    glassesSpeech: any GlassesSpeechRepository
  ) {
    _model = State(
      initialValue: SpeechTestViewModel(
        glassesSession: glassesSession,
        glassesSpeech: glassesSpeech
      )
    )
  }

  var body: some View {
    SpeechTestContent(
      uiState: model.uiState,
      onStart: { model.start() },
      onStop: { model.stop() }
    )
    // The run is the screen's, not the navigation stack's: walking away hangs up, which is
    // the same lease every other glasses session in the app is held on.
    .onDisappear { model.stop() }
  }
}

/// The drawing, taking a reading rather than a repository — which is what lets the states this
/// screen exists to produce be seen without a pair of glasses to produce them.
private struct SpeechTestContent: View {
  @Environment(\.theme) private var theme

  let uiState: SpeechTestUiState
  let onStart: () -> Void
  let onStop: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: theme.space.section) {
        sessionSection
        heardSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.vertical, theme.space.separate)
    }
    .background(theme.colors.paper)
    .navigationTitle("Test ASR")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var sessionSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Session", color: theme.colors.gilt)

      Text(
        "Recognition runs on the glasses — no audio reaches the phone, and the "
          + "microphone here stays free."
      )
      .font(theme.type.label)
      .foregroundStyle(theme.colors.textSecondary)

      readingRow(label: "Glasses", value: sessionValue)
      readingRow(label: "Recogniser", value: speechValue, support: speechSupport)

      if let failure = uiState.failure {
        // In the page's own ink rather than a red: the palette spends its one red on
        // controls that end something, and a line explaining why a test stopped is a
        // statement, not a control.
        Text(failure)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
      }

      if uiState.isRunning {
        ActionButton(title: "Stop", tone: .destructive, action: onStop)
      } else {
        ActionButton(title: "Start listening", action: onStart)
      }
    }
  }

  private var heardSection: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "Heard", color: theme.colors.gilt)

      // The utterance in progress, italic and above the finished ones — the line that says
      // the glasses are hearing *you* rather than merely listening.
      if let partial = uiState.partial {
        Text(partial)
          .font(theme.type.body.italic())
          .foregroundStyle(theme.colors.textSecondary)
      }

      if uiState.heard.isEmpty && uiState.partial == nil {
        Text(emptyLine)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
      }

      ForEach(Array(uiState.heard.enumerated()), id: \.offset) { _, heard in
        HairlineRule()
        heardRow(heard)
      }
    }
  }

  /// One finished utterance: what was heard, and how sure the glasses were about it.
  private func heardRow(_ heard: Transcription) -> some View {
    HStack(alignment: .top, spacing: theme.space.related) {
      Text(heard.text)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
      Spacer()
      // A confidence the recogniser would not give is a dash, never a number — see
      // ``Transcription``.
      Text(heard.confidence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }

  /// What the session is doing, in the words the pill on the realtime screen uses — one
  /// vocabulary for the link across the app, so a reading here is comparable with a reading
  /// there.
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

  private var speechValue: String {
    switch uiState.speechState {
    case .idle: "Not started"
    case .starting: "Starting"
    case .listening: "Listening"
    case .stopped: "Stopped"
    case .unavailable: "Unavailable"
    }
  }

  /// Only the readings that need explaining explain themselves — and the one that matters is
  /// `unavailable`, which is otherwise indistinguishable from a quiet room.
  private var speechSupport: String? {
    switch uiState.speechState {
    case .unavailable:
      "This pair has no on-device recognition, so nothing here will ever be heard"
    case .stopped:
      "The recogniser was listening and went quiet — usually the link, not the speech"
    case .idle, .starting, .listening:
      nil
    }
  }

  /// What an empty list means, which depends entirely on what the recogniser is doing.
  private var emptyLine: String {
    if uiState.speechState == .listening { return "Listening — say something." }
    return uiState.isRunning ? "Waiting for the glasses." : "Nothing yet."
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
}

/// A run in progress: the glasses listening, one sentence landed and another mid-air.
#Preview("Listening") {
  NavigationStack {
    SpeechTestContent(
      uiState: SpeechTestUiState(
        isRunning: true,
        sessionState: .started,
        speechState: .listening,
        partial: "and it has a yellow",
        heard: [
          Transcription(
            text: "It's green with a yellow belly",
            isFinal: true,
            confidence: 0.91
          ),
          Transcription(text: "What bird is that", isFinal: true, confidence: nil),
        ]
      ),
      onStart: {},
      onStop: {}
    )
  }
  .birdSpotterTheme()
}

/// The reading the screen exists to produce: a pair that cannot do this at all.
#Preview("Unavailable") {
  NavigationStack {
    SpeechTestContent(
      uiState: SpeechTestUiState(
        isRunning: true,
        sessionState: .started,
        speechState: .unavailable
      ),
      onStart: {},
      onStop: {}
    )
  }
  .birdSpotterTheme()
}
