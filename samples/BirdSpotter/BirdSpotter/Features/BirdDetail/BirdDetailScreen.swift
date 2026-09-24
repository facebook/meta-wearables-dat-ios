/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  BirdDetailScreen.swift
//  birdspotter
//

import SwiftUI

/// One species' page in the field guide — the plates, the name, and what the guide says.
///
/// Pushed by `Route.birdDetail(speciesId:)`, which every tab registers, so the same page
/// opens from Explore's card, from an Identify result, and from a Journal entry — each
/// landing on its own tab's stack.
///
/// Spacing comes from `theme.space` throughout.
struct BirdDetailScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss

  @State private var model: BirdDetailViewModel
  @State private var barProgress: CGFloat = 0

  init(speciesId: String, birdCatalog: any BirdCatalogRepository) {
    _model = State(initialValue: BirdDetailViewModel(speciesId: speciesId, birdCatalog: birdCatalog))
  }

  var body: some View {
    ZStack(alignment: .top) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          switch model.uiState {
          case .loading: BirdPagePlaceholder()
          // `model` rather than a snapshot of its playback: only the vocalization
          // card reads `model.playback`, so the ~30 Hz playhead ticks invalidate
          // that card alone and not the plates and prose above it.
          case .ready(let bird): BirdPage(bird: bird, model: model)
          case .notFound: NotInTheGuide()
          }
        }
      }
      // Scroll geometry, not a `PreferenceKey`. The offset never enters the preference
      // system, so it cannot propagate up into `navigationDestination` and rebuild the
      // destination that emitted it — which is what put the first attempt at this bar
      // into unbounded recursion and killed the process on the stack guard page.
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        Self.barProgress(for: geometry)
      } action: { _, progress in
        barProgress = progress
      }

      CollapsingBar(title: barTitle, progress: barProgress) { dismiss() }
    }
    .background(theme.colors.paper)
    // The page draws its own bar rather than dressing the system one.
    //
    // UIKit's navigation bar owns its background and its title, and will not hand that
    // control back: `toolbarBackgroundVisibility` honours `.hidden` but never restores
    // the fill, and a faded `ToolbarItem` renders either fully or not at all. Drawing
    // `CollapsingBar` ourselves is the only way to get a bar that fades on scroll, and
    // hiding the system one is also what lets the plate run full-bleed to the top.
    .toolbar(.hidden, for: .navigationBar)
    // Hiding the bar takes the stack's swipe-back with it; this puts it back.
    .background(InteractivePopGesture())
    .task { await model.load() }
    // Silences the call when the page leaves the screen.
    .onDisappear { model.stopPlayback() }
  }

  /// 0 while the plate holds the page, 1 once the bar has taken the name over.
  ///
  /// Deliberately early — it begins as soon as the plate has visibly moved. Tuning it to
  /// the plate's own height reads better in the abstract, but most entries are short
  /// enough that the whole page only scrolls a couple of hundred points, and a handover
  /// pegged to the plate would then never fire at all. `Mourning Dove` is the shortest
  /// and reaches roughly 190.
  private static func barProgress(for geometry: ScrollGeometry) -> CGFloat {
    let travelled = geometry.contentOffset.y + geometry.contentInsets.top
    return min(max((travelled - handoverBegins) / handoverSpan, 0), 1)
  }

  private static let handoverBegins: CGFloat = 32
  private static let handoverSpan: CGFloat = 80

  private var barTitle: String {
    if case .ready(let bird) = model.uiState { bird.species.commonName } else { "" }
  }
}

// MARK: - The bar

private enum BarMetrics {
  /// A standard iOS bar row, so the name lands where a system title would.
  static let height: CGFloat = 44
  static let control: CGFloat = 44
  static let disc: CGFloat = 34
}

/// Transparent over the plate, paper once you have scrolled past it. Two things fade on the
/// one signal: the bar's fill and its title.
private struct CollapsingBar: View {
  @Environment(\.theme) private var theme

  let title: String
  let progress: CGFloat
  let onBack: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      BackControl(disc: 1 - progress, action: onBack)

      Text(title)
        .font(theme.type.headline)
        .foregroundStyle(theme.colors.textPrimary)
        .lineLimit(1)
        .opacity(progress)
        .frame(maxWidth: .infinity)

      // Balances the back control so the name sits on the screen's centre line.
      Color.clear.frame(width: BarMetrics.control, height: BarMetrics.control)
    }
    .padding(.horizontal, theme.space.related)
    .frame(height: BarMetrics.height)
    .background {
      theme.colors.paper
        .opacity(progress)
        .overlay(alignment: .bottom) { HairlineRule().opacity(progress) }
        // Carries the paper up behind the clock, so the bar and the status bar
        // become one surface rather than two.
        .ignoresSafeArea(edges: .top)
    }
  }
}

/// A disc on the plate, gone by the time the bar is solid behind it.
private struct BackControl: View {
  @Environment(\.theme) private var theme

  let disc: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(glyph: theme.glyphs.back)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(theme.colors.textPrimary)
        .frame(width: BarMetrics.disc, height: BarMetrics.disc)
        .background {
          Circle()
            .fill(theme.colors.paper)
            .opacity(0.94 * disc)
        }
    }
    .frame(width: BarMetrics.control, height: BarMetrics.control)
    .contentShape(.rect)
    .accessibilityLabel("Back")
  }
}

/// Puts the edge swipe back after `.toolbar(.hidden)` has removed it.
///
/// A `NavigationStack` wires its interactive pop gesture to the navigation bar, so hiding
/// the bar disables the gesture — on a screen with a back button of its own that is a
/// regression, not a simplification. Clearing the recogniser's delegate re-arms it; the
/// replacement delegate is what stops it firing on the stack's root, which would otherwise
/// leave the navigation controller wedged.
private struct InteractivePopGesture: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> Controller { Controller() }
  func updateUIViewController(_ controller: Controller, context: Context) {}

  final class Controller: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      guard let gesture = parent?.navigationController?.interactivePopGestureRecognizer else { return }
      gesture.delegate = self
      gesture.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
      (navigationController?.viewControllers.count ?? 0) > 1
    }
  }
}

// MARK: - The page

private struct BirdPage: View {
  @Environment(\.theme) private var theme

  let bird: SpeciesWithMedia
  /// Held only to forward to the vocalization card, which is the one thing on the page that
  /// reads the ticking `playback`. `BirdPage`'s own body never touches it, so a playhead
  /// tick does not rebuild the plates.
  let model: BirdDetailViewModel

  @State private var plate = 0

  var body: some View {
    // spacing 0: the carousel and its caption are flush by design, and everything
    // below is one block with its own rhythm.
    VStack(alignment: .leading, spacing: 0) {
      if !bird.photos.isEmpty {
        PlateCarousel(
          photos: bird.photos,
          commonName: bird.species.commonName,
          plate: $plate
        )
        PlateCaption(
          credit: bird.photos.indices.contains(plate) ? bird.photos[plate].credit : nil,
          plate: plate,
          count: bird.photos.count
        )
      }

      VStack(alignment: .leading, spacing: theme.space.section) {
        nameplate

        GuideSection(title: "About") {
          Prose(bird.species.aboutText)
        }

        GuideSection(title: "Habitat") {
          Prose(bird.species.habitatText)
        }

        if let audio = bird.referenceAudio {
          GuideSection(title: audio.type.sectionTitle) {
            VocalizationCard(media: audio, sonogram: bird.sonogram, model: model)
          }
        }
      }
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.section)
      .padding(.bottom, theme.space.page)
    }
  }

  /// Family in plate caps, then the name and the binomial — the head of a guide entry.
  ///
  /// `spacing: 0` with per-child padding, because these three gaps are deliberately
  /// different sizes; a uniform stack rhythm would flatten the hierarchy.
  private var nameplate: some View {
    VStack(alignment: .leading, spacing: 0) {
      PlateLabel(text: bird.species.familyName, color: theme.colors.verdigris)
        .padding(.bottom, theme.space.related)

      Text(bird.species.commonName)
        .font(theme.type.display)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(.bottom, theme.space.tight)

      Text(bird.species.scientificName)
        .font(theme.type.scientific)
        .foregroundStyle(theme.colors.textSecondary)
    }
  }
}

// MARK: - Plates

/// Every bundled photograph, swiped through in place.
///
/// Full bleed on purpose — the plate is the page's opening, and insetting it to the gutter
/// would make it a card like Explore's rather than a plate.
private struct PlateCarousel: View {
  let photos: [SpeciesMedia]
  let commonName: String
  @Binding var plate: Int

  var body: some View {
    // `Color.clear` sized to 4:3 first, with the pager laid *into* it. A horizontal
    // scroll takes its height from its content and a vertical ScrollView proposes an
    // unbounded one, so the pager has to be given a box rather than asked for one.
    Color.clear
      .aspectRatio(4 / 3, contentMode: .fit)
      .overlay {
        // A paging ScrollView rather than `TabView(.page)`. That style is a
        // `UIPageViewController`, and the page ScrollView above it wins the gesture
        // on any swipe carrying a little slope — which cancels the pan mid-turn.
        // `UIPageViewController` does not settle from a cancelled transition: it
        // stops under the finger and strands two plates on screen at once, having
        // already reported the new index. A scroll target behaviour snaps on
        // cancellation exactly as it does on release, so the plate always lands.
        ScrollView(.horizontal) {
          // Positional identity, matching the `plate` index the caption prints
          // and `scrollPosition` reports. The set is fixed once the bird loads.
          LazyHStack(spacing: 0) {
            ForEach(photos.indices, id: \.self) { position in
              CatalogPhoto(
                media: photos[position],
                label: "\(commonName), plate \(position + 1)"
              )
              .containerRelativeFrame(.horizontal)
              .clipped()
            }
          }
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        // Keeps a lone plate from rubber-banding, the way a one-page pager doesn't drag.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollPosition(id: settledPlate)
      }
      .clipped()
  }

  /// `scrollPosition` deals in an optional — it has no id to report before the first
  /// layout. Nil never means "no plate" here, so it is dropped rather than written back.
  private var settledPlate: Binding<Int?> {
    Binding(
      get: { plate },
      set: { position in if let position { plate = position } }
    )
  }
}

/// The strip under the plates: who took this one, and where you are in the set.
///
/// The credit rides with its photograph rather than collecting in a footer — everything
/// bundled is openly licensed on the condition that the photographer is named, and naming
/// them beside the picture is both better manners and better design.
/// See licenses/ATTRIBUTION.md.
private struct PlateCaption: View {
  @Environment(\.theme) private var theme

  let credit: String?
  let plate: Int
  let count: Int

  /// The credit shrinks to 10pt before it starts truncating, written as the floor over
  /// the role's own size so both numbers stay legible — `theme.type.caption` is 12pt and
  /// `minimumScaleFactor` wants the ratio between them.
  private static let creditFloor: CGFloat = 10.0 / 12.0

  var body: some View {
    HStack(spacing: theme.space.separate) {
      Text(credit ?? "")
        .font(theme.type.caption)
        .foregroundStyle(theme.colors.textFaint)
        .lineLimit(1)
        // Shrink the line to fit before dropping characters from it. Credits run
        // long and it is the tail that goes — which is where the licence is, the
        // one part of the credit we are actually obliged to print.
        .minimumScaleFactor(Self.creditFloor)
        .truncationMode(.tail)

      Spacer(minLength: 0)

      Text("\(plate + 1) of \(count)")
        .font(theme.type.data)
        .foregroundStyle(theme.colors.textSecondary)
        .accessibilityLabel("Plate \(plate + 1) of \(count)")
    }
    .padding(.horizontal, theme.space.gutter)
    .padding(.vertical, theme.space.related)
    .background(theme.colors.paperRaised)
    .overlay(alignment: .top) { HairlineRule() }
    .overlay(alignment: .bottom) { HairlineRule() }
  }
}

// MARK: - Sections

/// A plate-capped heading over its content, at the page's one section rhythm.
private struct GuideSection<Content: View>: View {
  @Environment(\.theme) private var theme

  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: theme.space.related) {
      PlateLabel(text: title, color: theme.colors.gilt)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Running guide text.
private struct Prose: View {
  @Environment(\.theme) private var theme

  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(theme.type.body)
      .foregroundStyle(theme.colors.textSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The guide's entry for this bird's voice, now a working player: play or pause the clip, a
/// sonogram whose playhead tracks it, the sex and stage of the bird recorded, and who
/// recorded it.
///
/// Reads `model.playback` directly — the one view on the page that does — so the ~30 Hz
/// playhead ticks invalidate this card and not the plates and prose above it.
private struct VocalizationCard: View {
  @Environment(\.theme) private var theme

  let media: SpeciesMedia
  let sonogram: SpeciesMedia?
  let model: BirdDetailViewModel

  var body: some View {
    CardSurface {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: theme.space.related) {
          PlayButton(isPlaying: model.playback.isPlaying) {
            model.togglePlayback()
          }

          // The section eyebrow already names this "Song"/"Call"; the card leads
          // instead with who is singing — the sex and stage of the recorded bird.
          VStack(alignment: .leading, spacing: theme.space.tight) {
            Text(media.voiceDescription ?? "Reference recording")
              .font(theme.type.headline)
              .foregroundStyle(theme.colors.textPrimary)

            if let duration = media.formattedDuration {
              Text(duration)
                .font(theme.type.data)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityLabel("Duration \(duration)")
            }
          }

          Spacer(minLength: 0)
        }

        if let sonogram {
          Sonogram(
            media: sonogram,
            progress: model.playback.progress,
            onScrub: { model.seek(to: $0) }
          )
          .padding(.top, theme.space.separate)
        }

        if let credit = media.credit {
          HairlineRule()
            .padding(.vertical, theme.space.separate)

          Text("Recording: \(credit)")
            .font(theme.type.caption)
            .foregroundStyle(theme.colors.textFaint)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(theme.space.cardInset)
    }
  }
}

/// The transport control. A filled verdigris disc so it reads as the one thing to tap on the
/// card; the glyph swaps between play and pause without changing weight.
private struct PlayButton: View {
  @Environment(\.theme) private var theme

  let isPlaying: Bool
  let action: () -> Void

  /// A standard touch target, with the glyph sitting inside it — control sizes, not the
  /// spacing scale, which governs gaps rather than the size of a button.
  private static let disc: CGFloat = 44
  private static let glyphSize: CGFloat = 20

  var body: some View {
    Button(action: action) {
      Image(glyph: isPlaying ? theme.glyphs.pause : theme.glyphs.play)
        .font(.system(size: Self.glyphSize))
        .foregroundStyle(theme.colors.paper)
        .frame(width: Self.disc, height: Self.disc)
        .background(Circle().fill(theme.colors.verdigris))
    }
    .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")
  }
}

// MARK: - Other states

/// The page's silhouette while the query runs, so nothing jumps when the row lands.
private struct BirdPagePlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(theme.colors.rule)
        .aspectRatio(4 / 3, contentMode: .fit)
      Color.clear.frame(height: 260)
    }
  }
}

/// Shown for an id the catalog does not have — a species dropped by a later seed, or an
/// address that was never good. Not an error, so it does not read as one.
private struct NotInTheGuide: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Not in the Guide").font(theme.type.title)
      } icon: {
        Image(glyph: theme.glyphs.help)
      }
    } description: {
      Text("This bird isn't part of the bundled field guide.").font(theme.type.body)
    }
    .foregroundStyle(theme.colors.textSecondary)
    .frame(maxWidth: .infinity)
    // Clears the bar, which this screen's content runs underneath.
    // `ContentUnavailableView` brings its own generous insets, so this is the only
    // spacing it gets from us.
    .padding(.top, theme.space.page * 2)
  }
}

// MARK: - Formatting

extension SpeciesMediaType {
  /// Heads the vocalization section. A song and a call are both audio and both play the
  /// same way; the distinction is a field-guide one, so the guide prints it.
  var sectionTitle: String {
    switch self {
    case .photo: "Photograph"
    case .song: "Song"
    case .call: "Call"
    // Never heads a section of its own — the sonogram is drawn inside the
    // vocalization section, under the clip it depicts. Titled for completeness.
    case .sonogram: "Sonogram"
    }
  }
}

extension SpeciesMedia {
  /// `m:ss`, or nil for the photos that have no duration to print.
  var formattedDuration: String? {
    guard let durationMs else { return nil }
    let seconds = Int((Double(durationMs) / 1000).rounded())
    // `%ld`, not `%d`: Swift's `Int` is 64-bit and `%d` reads 32.
    return String(format: "%ld:%02ld", seconds / 60, seconds % 60)
  }

  /// "Male · Adult" from the recording's sex and stage — the field-guide facts about the
  /// bird on the clip, which the card shows in place of restating the section's own
  /// "Song"/"Call". Either half may be missing (both usually are); nil when both are, and
  /// the card falls back to a plain "Reference recording".
  ///
  /// Only the first letter is raised, so a Xeno-canto value like `male, female` reads
  /// "Male, female" rather than the word-by-word "Male, Female" `.capitalized` would give.
  var voiceDescription: String? {
    let parts = [sex, stage].compactMap { value -> String? in
      guard let value, !value.isEmpty else { return nil }
      return value.prefix(1).uppercased() + value.dropFirst()
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

// MARK: - Previews

#Preview("Bird page") {
  NavigationStack {
    BirdDetailScreen(speciesId: "northern-cardinal", birdCatalog: PreviewBirdCatalog())
  }
  .birdSpotterTheme()
}

#Preview("Not in the guide") {
  NavigationStack {
    BirdDetailScreen(speciesId: "dodo", birdCatalog: PreviewBirdCatalog(isEmpty: true))
  }
  .birdSpotterTheme()
}
