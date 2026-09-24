/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyWizardScreen.swift
//  birdspotter
//

import SwiftUI

/// The step-by-step wizard: three questions, then the birds that match.
///
/// One destination, not four. The stations share their answers (going back must not forget
/// them), the progress header counts them as one flow, and the chevron walks the stations
/// before it leaves the wizard — all of which is one screen's internal state, not a navigation
/// stack. `Route.identifyWizard` stays a single entry on Identify's own stack, and the system
/// bar is hidden in favor of the wizard's own.
///
/// The where-stamp rides along invisibly: `.task` asks the ``LocationProvider`` for one fix as
/// the wizard appears, so the coordinate is usually in hand by the time a bird is claimed.
struct IdentifyWizardScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss

  @State private var model: IdentifyWizardViewModel

  init(
    birdCatalog: any BirdCatalogRepository,
    journal: any JournalRepository,
    locationProvider: any LocationProvider
  ) {
    _model = State(
      initialValue: IdentifyWizardViewModel(
        birdCatalog: birdCatalog,
        journal: journal,
        locationProvider: locationProvider
      ))
  }

  var body: some View {
    VStack(spacing: 0) {
      WizardBar(
        step: model.uiState.step,
        onBack: { if !model.goBack() { dismiss() } },
        onClose: { dismiss() }
      )

      if let question = model.uiState.step.question {
        Text(question)
          .font(theme.type.display)
          .foregroundStyle(theme.colors.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, theme.space.gutter)
          .padding(.top, theme.space.related)
          .padding(.bottom, theme.space.section)
      }

      stepContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

      if model.uiState.step.hasNextButton {
        NextButton(enabled: model.uiState.canAdvance) {
          model.advance()
        }
        .padding(.horizontal, theme.space.gutter)
        .padding(.vertical, theme.space.separate)
      }
    }
    .background(theme.colors.paper)
    .toolbar(.hidden, for: .navigationBar)
    // The where-stamp: one fix, started as the wizard opens. Location permission is the
    // Identify tab's entry gate, so this is expected to succeed by the time a bird is claimed.
    .task { await model.captureLocation() }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch model.uiState.step {
    case .size:
      ScrollView {
        WizardSizeStep(
          sizeClass: model.uiState.sizeClass,
          onChooseSizeClass: { model.chooseSizeClass($0) }
        )
      }

    case .colors:
      ScrollView {
        WizardColorsStep(
          colors: model.uiState.colors,
          onToggleColor: { model.toggleColor($0) }
        )
      }

    case .behavior:
      ScrollView {
        WizardBehaviorStep(
          behavior: model.uiState.behavior,
          onChooseBehavior: { model.chooseBehavior($0) }
        )
      }

    case .results:
      WizardResultsStep(
        coordinate: model.uiState.coordinate,
        spottedOn: model.uiState.spottedOn,
        candidates: model.uiState.candidates,
        savingSpeciesId: model.uiState.savingSpeciesId,
        savedSpeciesId: model.uiState.savedSpeciesId,
        saveError: model.uiState.saveError,
        onSaveSighting: { model.saveSighting($0) }
      )
    }
  }
}

extension IdentifyWizardStep {
  /// The station's question, or nil on the results list — which titles the bar instead.
  var question: String? {
    switch self {
    case .size: "What size was the bird?"
    case .colors: "What were the main colors?"
    case .behavior: "Was the bird… ?"
    case .results: nil
    }
  }

  /// Results advances by choosing a bird, not by Next — every other station earns the pinned
  /// button.
  var hasNextButton: Bool {
    switch self {
    case .results: false
    default: true
    }
  }
}

// MARK: - Chrome

private let wizardBarHeight: CGFloat = 56
private let wizardControlSize: CGFloat = 48

/// Chevron, progress, close. The chevron is absent on the first station — there is nothing
/// inside the wizard to go back to, and showing a control that closes the flow while dressed as
/// "back" would teach the wrong lesson.
private struct WizardBar: View {
  @Environment(\.theme) private var theme

  let step: IdentifyWizardStep
  let onBack: () -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      if step == .size {
        Spacer().frame(width: wizardControlSize)
      } else {
        Button(action: onBack) {
          Image(glyph: theme.glyphs.back)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: wizardControlSize, height: wizardControlSize)
        }
        .accessibilityLabel("Back")
      }

      Text(step == .results ? "Results" : "\(step.questionNumber) of 3")
        .font(theme.type.headline)
        .foregroundStyle(theme.colors.textPrimary)
        .frame(maxWidth: .infinity)

      Button(action: onClose) {
        Image(glyph: theme.glyphs.close)
          .foregroundStyle(theme.colors.textPrimary)
          .frame(width: wizardControlSize, height: wizardControlSize)
      }
      .accessibilityLabel("Close")
    }
    .padding(.horizontal, theme.space.snug)
    .frame(height: wizardBarHeight)
  }
}

/// The one filled button in the flow. Verdigris — the accent for "the thing the page is
/// about" — and squared to the card radius, because this app's controls are plates, not
/// pills.
private struct NextButton: View {
  @Environment(\.theme) private var theme

  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("Next")
        .font(theme.type.headline)
        .foregroundStyle(enabled ? theme.colors.paperRaised : theme.colors.textFaint)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(enabled ? theme.colors.verdigris : theme.colors.rule)
        .clipShape(.rect(cornerRadius: 3))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

#Preview {
  NavigationStack {
    IdentifyWizardScreen(
      birdCatalog: PreviewBirdCatalog(),
      journal: PreviewJournal(),
      locationProvider: PreviewLocationProvider()
    )
  }
  .birdSpotterTheme()
}

// The journal stand-in lives in PreviewCatalog beside the other preview seams — the same
// `PreviewJournal` the realtime cover's previews lean on.
