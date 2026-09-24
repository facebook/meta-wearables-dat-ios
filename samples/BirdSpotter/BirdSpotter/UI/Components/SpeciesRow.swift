/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeciesRow.swift
//  birdspotter
//

import SwiftUI

/// The browse list's own metric. Not a token set: one value on one component, and a token
/// set of size one is ceremony.
enum SpeciesRowMetrics {
  /// Square, and small enough that a screenful of them decodes without a stutter.
  static let thumbnailSize: CGFloat = 64
}

/// One line of the field guide's index: thumbnail, common name, binomial.
///
/// Rows sit directly on the paper and are parted by ``HairlineRule`` rather than each
/// being its own ``CardSurface`` — 92 stacked cards read as a feed, where a run of ruled
/// lines reads as an index, which is what this is. The card treatment is reserved for the
/// one bird of the day above them.
///
/// No family line: the section header directly above already says it, and repeating it on
/// every row is the kind of noise that makes a long list tiring to scan.
struct SpeciesRow: View {
  @Environment(\.theme) private var theme

  let bird: SpeciesWithMedia

  var body: some View {
    HStack(alignment: .center, spacing: theme.space.separate) {
      if let photo = bird.heroPhoto {
        CatalogPhoto(media: photo, maxWidthPx: thumbnailWidthPx)
          .frame(
            width: SpeciesRowMetrics.thumbnailSize,
            height: SpeciesRowMetrics.thumbnailSize
          )
          .clipShape(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius))
      }

      // The row owns the rhythm between its two lines; neither adds its own gap.
      VStack(alignment: .leading, spacing: theme.space.tight) {
        Text(bird.species.commonName)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
          .lineLimit(1)
        Text(bird.species.scientificName)
          .font(theme.type.scientific)
          .foregroundStyle(theme.colors.textSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, theme.space.related)
    // Without this the row is only tappable where it has ink, so the gap beside a
    // short name does nothing.
    .contentShape(Rectangle())
  }
}
