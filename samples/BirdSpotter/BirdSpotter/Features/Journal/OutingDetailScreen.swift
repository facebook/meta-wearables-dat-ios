/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  OutingDetailScreen.swift
//  birdspotter
//

import SwiftUI

/// One journal entry's page — the plate, the birds it confirmed, the recording a live outing
/// left (played back under its whole sonogram), the timeline of what landed on it, and the
/// field notes. One surface, two entry points (stop, and a Journal row), per the design doc;
/// a `manual` entry simply has no recording or timeline to show.
///
/// Pushed by `Route.outingDetail(outingId:)` from a Journal row. Unlike `BirdDetailScreen`,
/// which draws its own bar to run a plate full-bleed under the status bar, this keeps the
/// system navigation bar: it is opened from one place, wants an ordinary back, and the app
/// already dresses that bar in paper and Caslon (`configureChromeAppearance`). Navigation
/// chrome is one of the things deliberately left un-mirrored.
///
/// Split into a stateful screen and a stateless ``OutingDetailLoaded`` so the Previews render
/// a page without a store behind it.
struct OutingDetailScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss

  @State private var model: OutingDetailViewModel
  @State private var confirmingDelete = false

  private let mediaFileStore: MediaFileStore
  private let mapLauncher: any MapLauncher

  init(
    outingId: String,
    journal: any JournalRepository,
    birdCatalog: any BirdCatalogRepository,
    mediaFileStore: MediaFileStore,
    mapLauncher: any MapLauncher
  ) {
    _model = State(
      initialValue: OutingDetailViewModel(
        outingId: outingId,
        journal: journal,
        birdCatalog: birdCatalog,
        mediaFileStore: mediaFileStore,
        // Owned by the view model from here — released with the screen, like the bird
        // page's clip player.
        player: SystemOutingAudioPlayer()
      ))
    self.mediaFileStore = mediaFileStore
    self.mapLauncher = mapLauncher
  }

  var body: some View {
    content
      .background(theme.colors.paper)
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .task { await model.load() }
      .onDisappear { model.releasePlayer() }
      .alert("Delete this entry?", isPresented: $confirmingDelete) {
        Button("Delete", role: .destructive) {
          Task { if await model.delete() { dismiss() } }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes the entry and anything it captured — photos, audio, and its birds. It can't be undone.")
      }
  }

  @ViewBuilder
  private var content: some View {
    switch model.uiState {
    case .loading:
      OutingDetailPlaceholder()
    case .notFound:
      OutingNotFound()
    case .loaded(let entry, let timeline):
      OutingDetailLoaded(
        entry: entry,
        timeline: timeline,
        playback: model.playback,
        mediaFileStore: mediaFileStore,
        onOpenInMaps: { mapLauncher.open($0) },
        onTogglePlayback: { model.togglePlayback() },
        onScrub: { model.scrub(toMs: $0) },
        onSeek: { model.seek(toMs: $0) },
        onSeekRow: { model.seekTo($0) },
        onDelete: { confirmingDelete = true }
      )
    }
  }

  private var navigationTitle: String {
    if case .loaded(let entry, _) = model.uiState {
      entry.primaryBird?.species?.species.commonName
        ?? "Journal Entry"
    } else {
      "Journal Entry"
    }
  }
}

/// The loaded page, given one resolved outing: a plate, the nameplate — and for a live
/// outing, the recording itself, playable under the whole session's sonogram, the timeline
/// of what landed on it, and the birds the watcher confirmed out of it. Then the field notes
/// (the wizard's answers included, as provenance for the ID), any written note, a way into
/// the guide per confirmed bird, and the delete affordance.
private struct OutingDetailLoaded: View {
  @Environment(\.theme) private var theme

  let entry: JournalEntry
  let timeline: [TimelineRow]
  let playback: OutingPlaybackUiState?
  let mediaFileStore: MediaFileStore?
  let onOpenInMaps: (SightingLocation) -> Void
  let onTogglePlayback: () -> Void
  let onScrub: (Int64) -> Void
  let onSeek: (Int64) -> Void
  let onSeekRow: (TimelineRow) -> Void
  let onDelete: () -> Void

  /// The photograph being looked at full screen, or `nil` — see ``PhotoLightbox``.
  @State private var openPhoto: OpenPhoto?
  @Namespace private var photoNamespace

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        // Full-bleed, like Explore's and the guide's plates — a deliberate exception to
        // the gutter.
        OutingHero(
          entry: entry,
          mediaFileStore: mediaFileStore,
          photoNamespace: photoNamespace,
          onOpenPhoto: { openPhoto = $0 }
        )

        VStack(alignment: .leading, spacing: theme.space.section) {
          nameplate

          if let playback {
            recordingSection(playback)
          }

          // A live outing that carries no audio rows says so, plainly — the
          // absence is a fact about the entry (saved before recording shipped, or
          // a save that dropped its audio), and a page that hides the whole idea
          // reads as a mystery. Keyed on the rows rather than on `playback`, which
          // is legitimately nil for a beat while a real recording decodes.
          if entry.outing.kind == .live, entry.audio.isEmpty {
            DetailSection(title: "Recording") {
              Text("No recording was kept with this entry.")
                .font(theme.type.body)
                .foregroundStyle(theme.colors.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if !timeline.isEmpty {
            timelineSection
          }

          if entry.outing.kind == .live, !entry.birds.isEmpty {
            confirmedSection
          }

          DetailSection(title: "Field Notes") {
            VStack(spacing: 0) {
              let rows = Self.detailRows(entry)
              ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { HairlineRule() }
                DetailRow(label: row.label, value: row.value)
              }
            }
          }

          locationSection(entry.location)

          if let notes = entry.outing.notes, !notes.isEmpty {
            DetailSection(title: "Notes") {
              Text(notes)
                .font(theme.type.body)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          // A live outing's guide links live on its Confirmed rows; the wizard's
          // one bird keeps the plain row it always had.
          if entry.outing.kind != .live {
            inTheGuide
          }

          deleteButton
        }
        .padding(.horizontal, theme.space.gutter)
        .padding(.top, theme.space.section)
        .padding(.bottom, theme.space.page)
      }
    }
    .fullScreenCover(item: $openPhoto) { photo in
      PhotoLightbox(
        source: photo.source,
        caption: photo.caption,
        mediaFileStore: mediaFileStore
      ) { openPhoto = nil }
      .navigationTransition(.zoom(sourceID: photo.id, in: photoNamespace))
    }
  }

  /// The recording, whole: the session's sonogram with the playhead held centre, and the
  /// transport under it — play scrolls the strip, a drag or a tapped row moves it by hand.
  /// See ``OutingSonogram`` for why the strip runs the way it does.
  private func recordingSection(_ playback: OutingPlaybackUiState) -> some View {
    DetailSection(title: "Recording") {
      VStack(alignment: .leading, spacing: theme.space.related) {
        OutingSonogram(
          sonogram: playback.sonogram,
          positionMs: playback.positionMs,
          totalMs: playback.totalMs,
          onScrub: onScrub,
          onSeek: onSeek
        )
        HStack(spacing: theme.space.separate) {
          recordingPlayButton(isPlaying: playback.isPlaying)
          Text(
            sessionStamp(Double(playback.positionMs) / 1000)
              + " / "
              + sessionStamp(Double(playback.totalMs) / 1000)
          )
          .font(theme.type.data)
          .foregroundStyle(theme.colors.textSecondary)
        }
      }
    }
  }

  /// The transport, worn exactly as the bird page's clip button wears it.
  private func recordingPlayButton(isPlaying: Bool) -> some View {
    Button(action: onTogglePlayback) {
      ZStack {
        Circle()
          .fill(theme.colors.verdigris)
          .frame(width: recordingPlaySize, height: recordingPlaySize)
        Image(glyph: isPlaying ? theme.glyphs.pause : theme.glyphs.play)
          .font(.system(size: recordingPlayGlyphSize))
          .foregroundStyle(theme.colors.paper)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")
  }

  /// Everything that landed on the session, oldest first — the live log, read back at
  /// leisure. Every row on the clock takes a tap, and the tap moves the playhead to its
  /// moment: the timeline is the recording's index, not a second list beside it.
  private var timelineSection: some View {
    DetailSection(title: "Timeline") {
      VStack(spacing: 0) {
        ForEach(Array(timeline.enumerated()), id: \.element.id) { index, row in
          if index > 0 { HairlineRule() }
          TimelineRowView(
            row: row,
            mediaFileStore: mediaFileStore,
            photoNamespace: photoNamespace,
            onSeek: { onSeekRow(row) },
            onOpenPhoto: { openPhoto = $0 }
          )
        }
      }
    }
  }

  /// The birds this outing put in the life list, each against the moment it was confirmed
  /// from and the confidence the detector offered — where one actually scored the bird the
  /// watcher named (see `OutingWithChildren.confidence(of:)`). The row is the way into the
  /// guide, which is why a live outing has no separate guide list.
  private var confirmedSection: some View {
    DetailSection(title: "Confirmed") {
      VStack(spacing: 0) {
        ForEach(Array(entry.birds.enumerated()), id: \.element.sighting.id) { index, bird in
          if index > 0 { HairlineRule() }
          confirmedRow(bird)
        }
      }
    }
  }

  @ViewBuilder
  private func confirmedRow(_ bird: ConfirmedBird) -> some View {
    let stamp = entry.withChildren.offset(of: bird.sighting)
      .map { sessionStamp(Double($0) / 1000) }
    let confidence = entry.withChildren.confidence(of: bird.sighting)
      .map { JournalFormatting.confidenceLabel($0) }
    let detail = [stamp, confidence].compactMap(\.self).joined(separator: " · ")

    let label = HStack(spacing: theme.space.snug) {
      VStack(alignment: .leading, spacing: 0) {
        // The unresolvable id renders as a bird all the same — see
        // `JournalRepository`: an unidentified sighting, never an error.
        Text(bird.species?.species.commonName ?? "Unidentified")
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textPrimary)
        if !detail.isEmpty {
          Text(detail)
            .font(theme.type.caption)
            .foregroundStyle(theme.colors.textFaint)
        }
      }
      Spacer(minLength: 0)
      if bird.species != nil {
        Image(glyph: theme.glyphs.disclosure)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.colors.textFaint)
      }
    }
    .padding(.vertical, theme.space.related)
    .contentShape(Rectangle())

    if let species = bird.species {
      NavigationLink(value: Route.birdDetail(speciesId: species.species.id)) { label }
        .buttonStyle(.plain)
    } else {
      label
    }
  }

  /// Family, then the name and binomial — or the kind and "No birds confirmed" where the
  /// outing earned no bird. The Merlin case, first-class: saved, just nothing confirmed.
  private var nameplate: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let primary = entry.primaryBird?.species {
        PlateLabel(text: primary.species.familyName, color: theme.colors.verdigris)
          .padding(.bottom, theme.space.related)
        Text(primary.species.commonName)
          .font(theme.type.display)
          .foregroundStyle(theme.colors.textPrimary)
          .padding(.bottom, theme.space.tight)
        Text(
          entry.extraBirdCount > 0
            ? "and \(entry.extraBirdCount) more"
            : primary.species.scientificName
        )
        .font(theme.type.scientific)
        .foregroundStyle(theme.colors.textSecondary)
      } else {
        PlateLabel(
          text: JournalFormatting.kindLabel(entry.outing.kind),
          color: theme.colors.verdigris
        )
        .padding(.bottom, theme.space.related)
        Text("No birds confirmed")
          .font(theme.type.display)
          .foregroundStyle(theme.colors.textSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A tappable guide row per confirmed bird — one bird keeps the old single-line wording.
  @ViewBuilder
  private var inTheGuide: some View {
    let resolved = entry.birds.compactMap(\.species)
    if !resolved.isEmpty {
      VStack(spacing: 0) {
        ForEach(Array(resolved.enumerated()), id: \.offset) { index, species in
          if index > 0 { HairlineRule() }
          NavigationLink(value: Route.birdDetail(speciesId: species.species.id)) {
            HStack(spacing: theme.space.snug) {
              Text(resolved.count == 1 ? "View in the field guide" : species.species.commonName)
                .font(theme.type.body)
                .foregroundStyle(theme.colors.textPrimary)
              Spacer(minLength: 0)
              Image(glyph: theme.glyphs.disclosure)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.textFaint)
            }
            .padding(.vertical, theme.space.related)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  /// The outing's spot as a small map, with the coordinate and a tap-through to Apple Maps
  /// beneath it — shown only when the outing actually carries a fix. The map is a static
  /// record here, not a navigator: a tap hands off rather than panning.
  private func locationSection(_ location: SightingLocation) -> some View {
    DetailSection(title: "Location") {
      VStack(alignment: .leading, spacing: 0) {
        SightingMap(location: location, onTap: { onOpenInMaps(location) })
          // A record's map, not a navigator's — tall enough to place the pin in its
          // blocks, short enough to leave the field notes above the fold.
          .frame(height: 180)
          .clipShape(.rect(cornerRadius: CardMetrics.cornerRadius))
        openInMapsRow(location)
      }
    }
  }

  /// "Open in Maps" with the coordinate as its quiet second line — worded and weighted like
  /// the guide rows, and carrying its own vertical padding so the map above sits flush.
  private func openInMapsRow(_ location: SightingLocation) -> some View {
    Button {
      onOpenInMaps(location)
    } label: {
      HStack(spacing: theme.space.snug) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Open in Maps")
            .font(theme.type.body)
            .foregroundStyle(theme.colors.textPrimary)
          Text(JournalFormatting.coordinates(location.coordinate))
            .font(theme.type.caption)
            .foregroundStyle(theme.colors.textFaint)
        }
        Spacer(minLength: 0)
        Image(glyph: theme.glyphs.disclosure)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.colors.textFaint)
      }
      .padding(.vertical, theme.space.related)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Understated on the page — a ruled button, not a red one — with the destructive weight
  /// carried by the confirmation the parent presents. The palette has no red, and a loud
  /// control here would be the one off-palette mark on the screen.
  private var deleteButton: some View {
    Button(action: onDelete) {
      Text("Delete Entry")
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.space.related)
        .overlay {
          RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .strokeBorder(theme.colors.rule, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Delete entry")
  }

  /// The field-notes rows present for this entry — only the facts it actually holds, so a
  /// wizard entry does not print an empty "Facing" or a phantom length. The wizard's
  /// answers ride at the end, in trait order, as provenance for the ID.
  private static func detailRows(_ entry: JournalEntry) -> [(label: String, value: String)] {
    let outing = entry.outing
    let primary = entry.primaryBird?.sighting
    var rows: [(label: String, value: String)] = [
      ("Spotted", JournalFormatting.dateTime(outing.startedAt))
    ]
    if outing.kind == .live, let duration = outing.durationMs {
      rows.append(("Length", JournalFormatting.durationLabel(duration)))
    }
    rows.append(("Logged", JournalFormatting.kindLabel(outing.kind)))
    // The confirmed moment's context — the primary bird's, since the outing spans many.
    // Read down the evidence links rather than off the sighting: aim belongs to the
    // photo that was aimed, and a confidence only prints when the watcher confirmed the
    // species the detection proposed.
    if let primary {
      let moment = entry.withChildren.moment(of: primary)
      if let gaze = moment.gazeContext {
        rows.append(("Looking", JournalFormatting.gazeLabel(gaze)))
      }
      if let bearing = moment.bearingDeg {
        rows.append(("Facing", JournalFormatting.bearingLabel(bearing)))
      }
      if let confidence = entry.withChildren.confidence(of: primary) {
        rows.append(("Confidence", JournalFormatting.confidenceLabel(confidence)))
      }
    }
    // "You said: robin-sized, black and red, in trees" — trait order, not insertion
    // order, so the page reads like the wizard walked.
    let answers = entry.withChildren.events
      .filter { $0.type == .wizardAnswer }
      .compactMap { event -> (WizardTrait, String)? in
        guard let trait = event.trait, let value = event.value else { return nil }
        return (trait, value)
      }
      .sorted { lhs, rhs in
        let order = WizardTrait.allCases
        return (order.firstIndex(of: lhs.0) ?? 0) < (order.firstIndex(of: rhs.0) ?? 0)
      }
    for (trait, value) in answers {
      rows.append(
        (
          JournalFormatting.wizardTraitLabel(trait),
          JournalFormatting.wizardAnswerLabel(trait, value)
        ))
    }
    return rows
  }
}

/// One moment, in the log's own inks: gilt for what the journal calls a sighting, the
/// quieter hand for everything else — the same rule the review screen taught, so a reader
/// can tell a confirmed bird from a passed-over one without a legend.
private struct TimelineRowView: View {
  @Environment(\.theme) private var theme

  let row: TimelineRow
  let mediaFileStore: MediaFileStore?
  let photoNamespace: Namespace.ID
  let onSeek: () -> Void
  let onOpenPhoto: (OpenPhoto) -> Void

  var body: some View {
    // **A tap gesture rather than a `Button`, because the photograph in this row needs a tap
    // of its own.** Nested buttons hand every touch to the outer one, so a thumbnail inside a
    // seek button could never be opened; nested tap gestures give the innermost the area it
    // actually covers — 44 points of photograph opens the picture, and the rest of the row
    // still moves the playhead.
    content
      .onTapGesture { if row.offsetMs != nil { onSeek() } }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(row.offsetMs != nil ? .isButton : [])
      .accessibilityHint(row.offsetMs != nil ? "Play from here" : "")
      .accessibilityActions {
        if let photo = openablePhoto {
          Button("View photo") { onOpenPhoto(photo) }
        }
      }
  }

  /// This row's photograph, where it has one — a captured photo, or the picture a confirmed
  /// bird was identified from.
  private var openablePhoto: OpenPhoto? {
    switch row {
    case let .detection(_, _, commonName, _, _, photo):
      photo.map { OpenPhoto(id: $0.id, source: .media($0), caption: commonName) }
    case let .photo(_, _, media):
      OpenPhoto(id: media.id, source: .media(media), caption: nil)
    case .exchange:
      nil
    }
  }

  private var content: some View {
    HStack(spacing: theme.space.related) {
      Text(row.offsetMs.map { sessionStamp(Double($0) / 1000) } ?? "—")
        .font(theme.type.data)
        .foregroundStyle(theme.colors.textFaint)
        .frame(width: timelineStampWidth, alignment: .leading)

      moment
    }
    .padding(.vertical, theme.space.related)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var moment: some View {
    switch row {
    case let .detection(_, _, commonName, confidence, isConfirmed, photo):
      HStack(spacing: theme.space.related) {
        if let photo, let mediaFileStore {
          thumbnail(photo, mediaFileStore)
        }
        PlateLabel(
          text: commonName ?? "Unidentified",
          color: isConfirmed ? theme.colors.gilt : theme.colors.textSecondary
        )
        if let confidence {
          PlateLabel(
            text: JournalFormatting.confidenceLabel(confidence),
            color: isConfirmed ? theme.colors.textSecondary : theme.colors.textFaint
          )
        }
        if isConfirmed {
          Spacer(minLength: 0)
          PlateLabel(text: "Confirmed", color: theme.colors.gilt)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case let .exchange(_, _, question, answer):
      VStack(alignment: .leading, spacing: theme.space.tight) {
        Text(question)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
        Text(answer)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.gilt)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case let .photo(_, _, media):
      HStack(spacing: theme.space.related) {
        if let mediaFileStore {
          thumbnail(media, mediaFileStore)
        }
        PlateLabel(text: "Photo", color: theme.colors.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func thumbnail(_ media: OutingMedia, _ store: MediaFileStore) -> some View {
    OutingPhoto(media: media, mediaFileStore: store, maxWidthPx: timelinePhotoPx)
      .frame(width: timelinePhotoSize, height: timelinePhotoSize)
      .clipShape(RoundedRectangle(cornerRadius: theme.space.tight))
      .matchedTransitionSource(id: media.id, in: photoNamespace)
      .onTapGesture { if let photo = openablePhoto { onOpenPhoto(photo) } }
  }
}

// MARK: - Pieces

/// A plate-capped heading over its content, at the page's one section rhythm — the entry
/// page's own ``GuideSection``.
private struct DetailSection<Content: View>: View {
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

/// One fact in the field notes: a small-caps label and its value, on one ruled line.
private struct DetailRow: View {
  @Environment(\.theme) private var theme

  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: theme.space.separate) {
      Text(label)
        .font(theme.type.label)
        .foregroundStyle(theme.colors.textFaint)
      Spacer(minLength: 0)
      Text(value)
        .font(theme.type.body)
        .foregroundStyle(theme.colors.textPrimary)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, theme.space.related)
  }
}

/// The entry's lead image: the first captured photo, else the primary bird's plate, else a
/// marked tile. Sized 4:3 by laying it into a cleared box, the way the guide's carousel is.
private struct OutingHero: View {
  @Environment(\.theme) private var theme

  let entry: JournalEntry
  let mediaFileStore: MediaFileStore?
  var photoNamespace: Namespace.ID?
  var onOpenPhoto: ((OpenPhoto) -> Void)?

  var body: some View {
    Color.clear
      .aspectRatio(4 / 3, contentMode: .fit)
      .overlay { plate }
      .clipped()
  }

  /// The lead photograph, where the entry's plate is a photograph the watcher took rather than
  /// a catalog illustration. **A bird's plate is not openable, deliberately** — it is the
  /// guide's artwork standing in for a photo nobody took, and blowing it up full screen would
  /// present somebody else's drawing as this outing's record.
  private var openablePhoto: OpenPhoto? {
    guard let photo = entry.photos.first, mediaFileStore != nil else { return nil }
    return OpenPhoto(
      id: photo.id,
      source: .media(photo),
      caption: entry.primaryBird?.species?.species.commonName
    )
  }

  @ViewBuilder
  private var plate: some View {
    if let photo = entry.photos.first, let mediaFileStore {
      let hero = OutingPhoto(
        media: photo,
        mediaFileStore: mediaFileStore,
        maxWidthPx: heroPhotoWidthPx
      )
      if let photoNamespace, let onOpenPhoto, let openablePhoto {
        hero
          .matchedTransitionSource(id: photo.id, in: photoNamespace)
          .onTapGesture { onOpenPhoto(openablePhoto) }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint("View this photo")
      } else {
        hero
      }
    } else if let plate = entry.primaryBird?.species?.heroPhoto {
      CatalogPhoto(media: plate, maxWidthPx: heroPhotoWidthPx)
    } else {
      ZStack {
        theme.colors.giltWash
        Image(glyph: entry.audio.isEmpty ? theme.glyphs.journal : theme.glyphs.call)
          .font(.system(size: 44))
          .foregroundStyle(theme.colors.textFaint)
      }
    }
  }
}

// MARK: - Other states

/// The page's silhouette while the read runs, so nothing jumps when it lands.
private struct OutingDetailPlaceholder: View {
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(theme.colors.rule)
        .aspectRatio(4 / 3, contentMode: .fit)
      Color.clear.frame(height: 220)
    }
  }
}

/// Shown for an entry the store no longer has — deleted from under the address, or a link
/// that was never good. Not an error, so it does not read as one.
private struct OutingNotFound: View {
  @Environment(\.theme) private var theme

  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Entry Not Found").font(theme.type.title)
      } icon: {
        Image(glyph: theme.glyphs.help)
      }
    } description: {
      Text("This entry is no longer in your journal.").font(theme.type.body)
    }
    .foregroundStyle(theme.colors.textSecondary)
  }
}

/// The transport, sized as the bird page sizes its clip button.
private let recordingPlaySize: CGFloat = 44
private let recordingPlayGlyphSize: CGFloat = 20

/// Room for `12:00` in the stamp column — the live log's width, so the two logs line up in
/// the hand.
private let timelineStampWidth: CGFloat = 44

/// A photo in the timeline — the live log's size, for the same reason.
private let timelinePhotoSize: CGFloat = 44

/// Decode target for a timeline thumbnail, in pixels — a hair over the largest it draws.
private let timelinePhotoPx = 176

// MARK: - Previews

#Preview("Wizard entry") {
  NavigationStack {
    OutingDetailLoaded(
      entry: PreviewCatalog.journalEntries[0],
      timeline: [],
      playback: nil,
      mediaFileStore: nil,
      onOpenInMaps: { _ in },
      onTogglePlayback: {},
      onScrub: { _ in },
      onSeek: { _ in },
      onSeekRow: { _ in },
      onDelete: {}
    )
    .navigationTitle("Journal Entry")
    .navigationBarTitleDisplayMode(.inline)
  }
  .birdSpotterTheme()
}

#Preview("Multi-bird") {
  NavigationStack {
    OutingDetailLoaded(
      entry: PreviewCatalog.journalEntries[1],
      timeline: [],
      playback: nil,
      mediaFileStore: nil,
      onOpenInMaps: { _ in },
      onTogglePlayback: {},
      onScrub: { _ in },
      onSeek: { _ in },
      onSeekRow: { _ in },
      onDelete: {}
    )
    .navigationTitle("Journal Entry")
    .navigationBarTitleDisplayMode(.inline)
  }
  .birdSpotterTheme()
}

#Preview("Birdless") {
  NavigationStack {
    OutingDetailLoaded(
      entry: PreviewCatalog.birdlessJournalEntry,
      timeline: [],
      playback: nil,
      mediaFileStore: nil,
      onOpenInMaps: { _ in },
      onTogglePlayback: {},
      onScrub: { _ in },
      onSeek: { _ in },
      onSeekRow: { _ in },
      onDelete: {}
    )
    .navigationTitle("Journal Entry")
    .navigationBarTitleDisplayMode(.inline)
  }
  .birdSpotterTheme()
}
