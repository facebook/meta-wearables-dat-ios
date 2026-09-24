/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WizardResultsStep.swift
//  birdspotter
//

import SwiftUI

/// The wizard's answer: every species the five answers leave standing, in checklist
/// order, each with its plates and the two things to do about it — claim it, or read
/// about it first.
///
/// "This is my bird" writes the sighting and the card says so in place; the flow does
/// not yank the user elsewhere at its one moment of success. One claim per wizard run —
/// the other cards' buttons quiet down once a bird is taken. The info button pushes
/// `Route.birdDetail` onto Identify's own stack, the exact navigation the detail screen's
/// doc comment promises.
struct WizardResultsStep: View {
  @Environment(\.theme) private var theme

  let coordinate: Coordinate?
  let spottedOn: Date
  let candidates: [SpeciesWithMedia]?
  let savingSpeciesId: String?
  let savedSpeciesId: String?
  let saveError: IdentifyWizardSaveError?
  let onSaveSighting: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      answersStrip
      if let saveError { saveErrorNotice(saveError) }

      if let candidates {
        if candidates.isEmpty {
          NoMatches()
        } else {
          ScrollView {
            LazyVStack(spacing: theme.space.separate) {
              ForEach(candidates) { bird in
                CandidateCard(
                  bird: bird,
                  saving: savingSpeciesId == bird.species.id,
                  saved: savedSpeciesId == bird.species.id,
                  claimTaken: savedSpeciesId != nil,
                  onSaveSighting: { onSaveSighting(bird.species.id) }
                )
              }
            }
            .padding(.horizontal, theme.space.gutter)
            .padding(.top, theme.space.separate)
            .padding(.bottom, theme.space.page)
          }
        }
      } else {
        Searching()
      }
    }
  }

  /// Why the last "This is my bird" did not stick, in the one place the tap happened.
  ///
  /// A tap that writes nothing has to say so. Nothing was saved either way, so the wording is
  /// about what to do next rather than about what broke — and the buttons below stay live,
  /// because trying again is the entire remedy for both cases.
  private func saveErrorNotice(_ error: IdentifyWizardSaveError) -> some View {
    Text(
      error == .noLocationFix
        ? "Couldn't get your location, and an entry needs one. Try again in a moment, or step somewhere with a clearer view of the sky."
        : "Couldn't save that entry. Nothing was written — try again."
    )
    .font(theme.type.body)
    .foregroundStyle(theme.colors.textSecondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, theme.space.gutter)
    .padding(.top, theme.space.related)
  }

  /// What was taken for the sighting — the day, and that the spot was stamped — riding above
  /// the list the answers produced.
  private var answersStrip: some View {
    let date = spottedOn.formatted(.dateTime.month(.abbreviated).day())
    return VStack(spacing: 0) {
      HairlineRule()
      Text(coordinate != nil ? "Current location · \(date)" : date)
        .font(theme.type.caption)
        .foregroundStyle(theme.colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.space.gutter)
        .padding(.vertical, theme.space.related)
        .background(theme.colors.paperRaised)
      HairlineRule()
    }
  }
}

private struct CandidateCard: View {
  @Environment(\.theme) private var theme

  let bird: SpeciesWithMedia
  let saving: Bool
  let saved: Bool
  let claimTaken: Bool
  let onSaveSighting: () -> Void

  @State private var plate = 0

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: 0) {
        if !bird.photos.isEmpty {
          plates
        }

        VStack(alignment: .leading, spacing: 0) {
          Text(bird.species.commonName)
            .font(theme.type.title)
            .foregroundStyle(theme.colors.textPrimary)
          Text(bird.species.scientificName)
            .font(theme.type.scientific)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.space.tight)
          Text(bird.species.aboutText)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(4)
            .padding(.top, theme.space.related)

          HStack(spacing: theme.space.related) {
            ClaimButton(
              saving: saving,
              saved: saved,
              claimTaken: claimTaken,
              action: onSaveSighting
            )
            InfoButton(speciesId: bird.species.id)
          }
          .padding(.top, theme.space.separate)
        }
        .padding(theme.space.cardInset)
      }
    }
  }

  /// The card's own little carousel — the same paging ScrollView the detail page
  /// uses, for the same gesture reasons its comment explains.
  private var plates: some View {
    VStack(spacing: 0) {
      Color.clear
        .aspectRatio(4 / 3, contentMode: .fit)
        .overlay {
          ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
              ForEach(bird.photos.indices, id: \.self) { position in
                CatalogPhoto(
                  media: bird.photos[position],
                  label: "\(bird.species.commonName), plate \(position + 1)"
                )
                .containerRelativeFrame(.horizontal)
                .clipped()
              }
            }
            .scrollTargetLayout()
          }
          .scrollTargetBehavior(.paging)
          .scrollIndicators(.hidden)
          .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
          .scrollPosition(id: settledPlate)
        }
        .clipped()

      HairlineRule()
      HStack(spacing: theme.space.separate) {
        Text(bird.photos.indices.contains(plate) ? (bird.photos[plate].credit ?? "") : "")
          .font(theme.type.caption)
          .foregroundStyle(theme.colors.textFaint)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
        Text("\(plate + 1) of \(bird.photos.count)")
          .font(theme.type.data)
          .foregroundStyle(theme.colors.textSecondary)
      }
      .padding(.horizontal, theme.space.cardInset)
      .padding(.vertical, theme.space.snug)
      .background(theme.colors.paperRaised)
      HairlineRule()
    }
  }

  private var settledPlate: Binding<Int?> {
    Binding(
      get: { plate },
      set: { position in if let position { plate = position } }
    )
  }
}

/// "This is my bird", and its three quieter moods: saving, saved, or too late.
private struct ClaimButton: View {
  @Environment(\.theme) private var theme

  let saving: Bool
  let saved: Bool
  let claimTaken: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: theme.space.snug) {
        if saved {
          Image(glyph: theme.glyphs.selected)
            .font(.system(size: 15, weight: .semibold))
        }
        Text(saved ? "In your journal" : saving ? "Saving…" : "This is my bird")
          .font(theme.type.headline)
      }
      .foregroundStyle(labelColor)
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(background)
      .clipShape(.rect(cornerRadius: 3))
    }
    .buttonStyle(.plain)
    .disabled(saving || claimTaken)
  }

  // A saved card keeps its color: "in your journal" is a state, not a dead control,
  // and graying it out would read as an error.
  private var background: Color {
    saved ? theme.colors.verdigris : (claimTaken || saving) ? theme.colors.rule : theme.colors.verdigris
  }

  private var labelColor: Color {
    saved ? theme.colors.paperRaised : (claimTaken || saving) ? theme.colors.textFaint : theme.colors.paperRaised
  }
}

/// The quieter companion: read the guide's page before deciding.
private struct InfoButton: View {
  @Environment(\.theme) private var theme

  let speciesId: String

  var body: some View {
    NavigationLink(value: Route.birdDetail(speciesId: speciesId)) {
      Image(glyph: theme.glyphs.info)
        .font(.system(size: 20))
        .foregroundStyle(theme.colors.verdigris)
        .frame(width: 48, height: 48)
        .overlay(
          RoundedRectangle(cornerRadius: 3)
            .stroke(theme.colors.rule, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("About this bird")
  }
}

private struct Searching: View {
  @Environment(\.theme) private var theme

  var body: some View {
    VStack {
      Spacer()
      ProgressView()
        .tint(theme.colors.verdigris)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// An honest empty answer, with the way out named rather than implied.
private struct NoMatches: View {
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: theme.space.related) {
      Spacer()
      PlateLabel(text: "No Matches")
      Text("No bird in the guide fits everything you picked. Go back and drop a color, or try the next size.")
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
        .multilineTextAlignment(.center)
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, theme.space.gutter)
  }
}
