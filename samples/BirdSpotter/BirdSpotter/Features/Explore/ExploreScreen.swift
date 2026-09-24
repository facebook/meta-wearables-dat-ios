/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  ExploreScreen.swift
//  birdspotter
//

import SwiftUI

/// Explore — the field guide's front page.
///
/// Three sections: a title area, the day's featured bird, and the guide itself. The
/// glasses status pill and the Spot/Listen calls to action land here later.
///
/// A `LazyVStack` rather than a `VStack`, and that is the whole of the "loads as you
/// scroll" behaviour. 93 rows arrive from `catalog.db` in one query — they are cheap. The
/// photos are not, and a lazy stack builds a row, and so decodes its thumbnail, only once
/// the row is about to be seen. Paging the query would add state to every layer to save
/// microseconds; see ``SpeciesStore/speciesInBrowseOrder()``.
///
/// No `NavigationStack` of its own — the tab's stack is owned by `ContentView`, which is
/// what lets the card push a `Route` rather than name a screen.
///
/// Spacing comes from `theme.space` throughout.
struct ExploreScreen: View {
  @Environment(\.theme) private var theme

  @State private var model: ExploreViewModel

  init(birdCatalog: any BirdCatalogRepository) {
    _model = State(initialValue: ExploreViewModel(birdCatalog: birdCatalog))
  }

  var body: some View {
    ScrollView {
      // Per-child padding and `spacing: 0`, deliberately: the rhythm down this page is
      // not uniform — a section gap above each heading, none at all between the ruled
      // rows of a list — and setting both would add the two together.
      LazyVStack(alignment: .leading, spacing: 0) {
        titleArea

        // Above the featured card, not below it: search is the page's way in, and
        // buried under a 4:3 photo it would be a flick off screen. What keeps that
        // honest is that a query replaces everything under this line — see
        // `ExploreUiState.searching`.
        SearchField(text: model.query, onTextChange: { model.search($0) })
          .padding(.top, theme.space.separate)

        switch model.uiState {
        case .loading:
          BirdOfTheDayPlaceholder()
            .padding(.top, theme.space.section)
        case .ready(let birdOfTheDay, let guide):
          NavigationLink(value: Route.birdDetail(speciesId: birdOfTheDay.species.id)) {
            BirdOfTheDayCard(bird: birdOfTheDay)
          }
          // Without this the link tints every label inside the card blue and
          // draws a chevron. The card is the button.
          .buttonStyle(.plain)
          .padding(.top, theme.space.section)

          guideSections(guide)
        case .searching(let results):
          searchResults(results)
        case .empty:
          CatalogUnavailable()
            .padding(.top, theme.space.section)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.page)
    }
    .background(theme.colors.paper)
    // The screen writes its own header, so the bar would only repeat it.
    .toolbar(.hidden, for: .navigationBar)
    .task { await model.load() }
  }

  /// The rest of the guide: a heading per section, then its birds as ruled rows.
  ///
  /// A `ForEach` inside the `LazyVStack` rather than around it, so the stack still sees
  /// each row as its own child and can skip building the ones off screen. Ids are
  /// species slugs and group names, both stable by contract.
  @ViewBuilder
  private func guideSections(_ guide: [SpeciesGroup]) -> some View {
    ForEach(guide) { group in
      PlateLabel(text: group.name, color: theme.colors.gilt)
        .padding(.top, theme.space.section)
        .padding(.bottom, theme.space.related)

      ForEach(group.species) { bird in
        NavigationLink(value: Route.birdDetail(speciesId: bird.species.id)) {
          SpeciesRow(bird: bird)
        }
        .buttonStyle(.plain)

        // Under every row, including the section's last: a rule closes an index
        // entry the way a printed guide does, and the one before the next heading
        // is what gives that heading something to sit against.
        HairlineRule()
      }
    }
  }

  /// A query's matches: a count in the slot a section heading would take, then the same
  /// ruled rows the guide is built from.
  ///
  /// Flat, with no section headings. A three-letter query pulls a handful of birds out of
  /// as many different sections, and heading each one would put more headings on screen
  /// than results.
  @ViewBuilder
  private func searchResults(_ results: [SpeciesWithMedia]) -> some View {
    PlateLabel(text: resultsLabel(count: results.count), color: theme.colors.gilt)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.related)

    if results.isEmpty {
      // Plain text on the paper rather than a `CardSurface`. `CatalogUnavailable`
      // earns a card by being a permanent, unusual state; this one comes and goes
      // between keystrokes, and a card flashing in and out reads as a fault.
      Text("Nothing in the guide matches “\(model.query)”.")
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textSecondary)
    } else {
      ForEach(results) { bird in
        NavigationLink(value: Route.birdDetail(speciesId: bird.species.id)) {
          SpeciesRow(bird: bird)
        }
        .buttonStyle(.plain)

        HairlineRule()
      }
    }
  }

  /// Eyebrow over a headline, with no chrome above it.
  ///
  /// A field guide opens well because the page starts with the page, not with furniture.
  private var titleArea: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: "The Field Guide", color: theme.colors.gilt)

      Text("Venture into the wild.")
        .font(theme.type.display)
        .foregroundStyle(theme.colors.textPrimary)
    }
  }
}

/// The plate over a query's matches — "12 BIRDS", "1 BIRD", "NO MATCHES".
///
/// A count rather than a bare "RESULTS": it sits in the slot a section heading occupies, so
/// it may as well say the one thing a heading there cannot.
private func resultsLabel(count: Int) -> String {
  switch count {
  case 0: "No Matches"
  case 1: "1 Bird"
  default: "\(count) Birds"
  }
}

// MARK: - Bird of the day

/// The day's species: photo, plate label, name, binomial, and the credit the licence
/// requires. Tapping it opens the full page.
private struct BirdOfTheDayCard: View {
  @Environment(\.theme) private var theme

  let bird: SpeciesWithMedia

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: 0) {
        if let photo = bird.heroPhoto {
          CatalogPhoto(media: photo)
            // `.fit`, not `.fill`: this sizes the *frame* to 4:3, and a vertical
            // ScrollView proposes an unbounded height — which `.fill` tries to
            // cover, blowing the box past its width, overflowing the gutter
            // and over-cropping the photo. The inner image still fills-and-crops
            // via `scaledToFill`.
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
          HairlineRule()
        }

        // spacing 0 with per-child padding: these gaps are deliberately different
        // sizes, and a uniform stack rhythm would flatten the hierarchy.
        VStack(alignment: .leading, spacing: 0) {
          PlateLabel(text: "Bird of the Day", color: theme.colors.verdigris)
            .padding(.bottom, theme.space.related)

          Text(bird.species.commonName)
            .font(theme.type.display)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.bottom, theme.space.tight)

          Text(bird.species.scientificName)
            .font(theme.type.scientific)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.bottom, theme.space.separate)

          Text(bird.species.familyName)
            .font(theme.type.label)
            .foregroundStyle(theme.colors.textFaint)

          if let credit = bird.heroPhoto?.credit {
            HairlineRule()
              .padding(.vertical, theme.space.separate)
            // Not decoration: everything bundled is openly licensed on the
            // condition that the photographer is named.
            // See licenses/ATTRIBUTION.md.
            Text("Photograph: \(credit)")
              .font(theme.type.caption)
              .foregroundStyle(theme.colors.textFaint)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.space.cardInset)
      }
    }
  }
}

/// The card's silhouette while the first query runs, so the layout does not jump.
private struct BirdOfTheDayPlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    CardSurface {
      VStack(spacing: 0) {
        Rectangle()
          .fill(theme.colors.rule)
          .aspectRatio(4 / 3, contentMode: .fit)
        Color.clear.frame(height: 150)
      }
    }
  }
}

/// Shown when the catalog has no species at all — which means the seed never staged, not
/// that the user did anything. Says so plainly rather than blaming the network.
private struct CatalogUnavailable: View {
  @Environment(\.theme) private var theme

  var body: some View {
    CardSurface {
      VStack(spacing: theme.space.related) {
        PlateLabel(text: "The Guide Is Empty")

        Text("No species were bundled with this build.")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, theme.space.cardInset)
      .padding(.vertical, theme.space.page)
    }
  }
}

// MARK: - Previews

#Preview("Bird of the day") {
  NavigationStack {
    ExploreScreen(birdCatalog: PreviewBirdCatalog())
  }
  .birdSpotterTheme()
}

#Preview("Empty catalog") {
  NavigationStack {
    ExploreScreen(birdCatalog: PreviewBirdCatalog(isEmpty: true))
  }
  .birdSpotterTheme()
}
