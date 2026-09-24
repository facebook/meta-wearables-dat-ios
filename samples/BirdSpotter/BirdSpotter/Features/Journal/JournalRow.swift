/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalRow.swift
//  birdspotter
//

import SwiftUI

/// One line of the Journal: a thumbnail, what the outing earned, and when and where.
///
/// The outing counterpart to ``SpeciesRow``, and built to the same metric so a Journal and a
/// guide index read as the same list at two addresses — rows on the paper, parted by a
/// ``HairlineRule`` the screen draws, never each in its own card.
///
/// Labeling follows the design doc's one rule — the strongest confirmed fact leads, never a
/// switch on `kind`: the earliest confirmed bird names the row ("Green Jay + 2 more"), a
/// birdless outing falls back to its place, and a placeless one to its date. The thumbnail
/// walks the same ladder: captured photo, the primary bird's own plate, then a marked tile.
/// (A sonogram strip takes the third slot once the live flow can render one from a captured
/// segment — no captured audio exists before that flow ships.)
struct JournalRow: View {
  @Environment(\.theme) private var theme

  let entry: JournalEntry
  /// Resolves a captured photo's bytes. Nil in previews and anywhere a capture can't have
  /// happened, where the row falls back to the species plate or the tile.
  let mediaFileStore: MediaFileStore?

  var body: some View {
    HStack(alignment: .center, spacing: theme.space.separate) {
      thumbnail
        .frame(
          width: SpeciesRowMetrics.thumbnailSize,
          height: SpeciesRowMetrics.thumbnailSize
        )
        .clipShape(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius))

      // The row owns the rhythm between its lines; none adds its own gap.
      VStack(alignment: .leading, spacing: theme.space.tight) {
        title

        if let second = secondLine {
          Text(second)
            .font(theme.type.scientific)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
        }

        Text(metadata)
          .font(theme.type.caption)
          .foregroundStyle(theme.colors.textFaint)
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, theme.space.related)
    // The whole row is the target, so the gap beside a short name opens the entry too.
    .contentShape(Rectangle())
  }

  private var title: some View {
    Group {
      if entry.primaryBird != nil {
        Text(headline)
          .foregroundStyle(theme.colors.textPrimary)
      } else {
        // Not an error colour: an outing saves with or without a bird, and a
        // birdless row is just the quieter entry.
        Text(headline)
          .foregroundStyle(theme.colors.textSecondary)
      }
    }
    .font(theme.type.body)
    .lineLimit(1)
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let photo = entry.photos.first, let mediaFileStore {
      OutingPhoto(media: photo, mediaFileStore: mediaFileStore, maxWidthPx: thumbnailWidthPx)
    } else if let plate = entry.primaryBird?.species?.heroPhoto {
      CatalogPhoto(media: plate, maxWidthPx: thumbnailWidthPx)
    } else {
      ZStack {
        theme.colors.giltWash
        Image(glyph: entry.audio.isEmpty ? theme.glyphs.journal : theme.glyphs.call)
          .font(.system(size: 22))
          .foregroundStyle(theme.colors.textFaint)
      }
    }
  }

  /// The strongest confirmed fact: bird (+ count), else the date itself.
  private var headline: String {
    guard let primary = entry.primaryBird, let species = primary.species else {
      return JournalFormatting.date(entry.outing.startedAt)
    }
    let name = species.species.commonName
    let extra = entry.extraBirdCount
    return extra > 0 ? "\(name) + \(extra) more" : name
  }

  /// Scientific name under a single bird, a species count under several, nothing otherwise.
  private var secondLine: String? {
    guard let primary = entry.primaryBird, let species = primary.species else { return nil }
    if entry.extraBirdCount > 0 {
      return "\(entry.extraBirdCount + 1) species"
    }
    return species.species.scientificName
  }

  /// Date, and a live outing's length.
  private var metadata: String {
    var parts = [JournalFormatting.date(entry.outing.startedAt)]
    if entry.outing.kind == .live, let duration = entry.outing.durationMs {
      parts.append(JournalFormatting.durationLabel(duration))
    }
    return parts.joined(separator: " · ")
  }
}
