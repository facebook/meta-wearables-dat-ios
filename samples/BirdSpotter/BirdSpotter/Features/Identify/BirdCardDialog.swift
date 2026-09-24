/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdCardDialog.swift
//  birdspotter
//

import SwiftUI

/// The identified bird's card, on the phone — the same card the glasses would have drawn, for
/// every run that has no glass to draw on.
///
/// **It is the display's fallback, not a second design.** The order is the display's own — the two
/// names, the photographs, the description last — and so are its two measurements: `related`
/// between the parts, `separate` around them, because those are the numbers the component tree
/// sent up to the panel carries. A card that read differently in the two places would make the
/// phone a poor rehearsal for the glasses.
///
/// What it adds is the one thing a phone has and a panel does not: somewhere to scroll. Three
/// photographs and two blocks of text overflow a canvas built for exactly this, and they overflow
/// a phone by more.
///
/// **The close mark is the one thing here the glasses' card does not have, and it earns its
/// place.** A dialog that could only be dismissed by pressing away from it asks for a tap in the
/// thin margin around a card that fills most of the screen — a target that is hard to hit and
/// invisible until you have missed it. The mark shares the heading's line rather than taking a row
/// of its own, so the card still opens on the bird's name. Pressing outside still works; pressing
/// the card itself no longer does, because a body tap and a scroll are the same gesture until you
/// have finished making it.
///
/// **An overlay rather than a sheet**, because a sheet arrives from the bottom edge and stops
/// short of the top, which is a different object from the one the other app puts on screen. The
/// two are meant to be recognisably the same card.
struct BirdCardDialog: View {
  @Environment(\.theme) private var theme

  let bird: SpeciesWithMedia
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      // The scrim takes the press that lands beside the card, which is the other way out.
      Color.black.opacity(scrimOpacity)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)

      ScrollView {
        VStack(alignment: .leading, spacing: theme.space.related) {
          HStack(alignment: .firstTextBaseline, spacing: theme.space.related) {
            Text(bird.species.commonName)
              .font(theme.type.title)
              .foregroundStyle(theme.colors.textPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
              Image(glyph: theme.glyphs.close)
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close this card")
          }
          Text(bird.species.scientificName)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textSecondary)
          ForEach(bird.photos) { photo in
            // Unlabelled for the reason the component documents: the name is printed
            // directly above, and describing three photographs of it would have the
            // screen reader name the bird four times over.
            CatalogPhoto(media: photo)
              .aspectRatio(cardPhotoAspect, contentMode: .fill)
              .frame(maxWidth: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: theme.space.snug))
          }
          Text(bird.species.aboutText)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.space.separate)
      }
      .background(theme.colors.paper)
      .clipShape(RoundedRectangle(cornerRadius: theme.space.related))
      .padding(theme.space.gutter)
    }
  }
}

/// The shape a catalog photograph is cropped to here — the same 4:3 the field guide's own pages
/// use, so a bird looks like itself wherever it is met.
private let cardPhotoAspect: CGFloat = 4.0 / 3.0

/// Dark enough that the card reads as the thing in front, light enough that the session behind it
/// is still visibly running — which it is.
private let scrimOpacity: Double = 0.6
