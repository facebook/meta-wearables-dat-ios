/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionReviewScreen.swift
//  birdspotter
//

import SwiftUI

/// The confirmation — the second screen of the real-time flow, after the stop.
///
/// The session is over by the time this appears and nothing has been written: the stop answered
/// *is the microphone still open*, and this screen answers *is this worth keeping*. What it
/// offers, in the order a watcher wants it: the timeline read back whole, the birds separable
/// from the rest, a place for notes, and Save or Discard.
///
/// The birds take a tap: a saved outing's sightings are the ones a watcher **confirmed**,
/// not the ones a detector offered, and dropping a bad detection here is the whole reason a
/// confirmation exists rather than an autosave. Dropping one keeps its row on the timeline
/// — the journal records what happened either way; what changes is what enters the life
/// list.
///
/// **Discard is a real button, and it does not ask twice.** A rehearsal before a demo and a
/// session started by accident are both sessions somebody stopped, and neither is a journal
/// entry; a journal that fills with rehearsals is a journal nobody reads.
///
/// Runs in the cover's dark palette like the session it reviews — one flow, one cabinet.
struct SessionReviewScreen: View {
  @Environment(\.theme) private var theme

  let session: RealtimeSession
  let review: SessionReview
  let onToggleBird: (Double) -> Void
  let onNotesChange: (String) -> Void
  let onSave: () -> Void
  let onDiscard: () -> Void

  /// The photograph being looked at full screen, or `nil` — see ``PhotoLightbox``.
  @State private var openPhoto: OpenPhoto?
  @Namespace private var photoNamespace

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: theme.space.tight) {
        Text("Review")
          .font(theme.type.title)
          .foregroundStyle(theme.colors.textPrimary)
        Text(subtitle)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
        // The rows have been tappable since this screen existed and nothing said so —
        // the VoiceOver label read "tap to drop it" while a sighted watcher got a chip
        // that looks like every other status plate in the app. Said once, at the top,
        // and only where there is actually a bird to tap.
        if hasConfirmableRows {
          Text("Tap a bird to drop it from your life list")
            .font(theme.type.caption)
            .foregroundStyle(theme.colors.textFaint)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.separate)

      HairlineRule()
        .padding(.top, theme.space.separate)

      // The timeline read back whole: oldest first, because a stopped session is a story
      // being read rather than a report still arriving — the live log's newest-first is
      // for the opposite situation.
      ScrollView {
        LazyVStack(alignment: .leading, spacing: theme.space.related) {
          ForEach(session.events, id: \.at) { event in
            ReviewRow(
              event: event,
              isDropped: review.droppedBirds.contains(event.at),
              photoNamespace: photoNamespace,
              onToggle: { onToggleBird(event.at) },
              onOpenPhoto: { openPhoto = $0 }
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.space.gutter)
        .padding(.vertical, theme.space.separate)
      }
      // The journal saves an outing with or without birds by design — forty minutes
      // of wind still happened somewhere. Said plainly rather than left blank.
      .overlay(alignment: .top) {
        if session.events.isEmpty {
          PlateLabel(text: "Nothing landed on the timeline", color: theme.colors.textFaint)
            .padding(.top, theme.space.section)
        }
      }

      HairlineRule()

      // The one thing a person can contribute that no sensor can, asked for at the
      // moment they still remember what the morning was like.
      //
      // In the app's own box — see ``NotesField``. This screen forces the dark palette,
      // and a system-drawn field is the one thing on it that would not know.
      NotesField(
        text: review.notes,
        onTextChange: onNotesChange,
        placeholder: "Notes — what the morning was like",
        isEnabled: !review.isSaving && review.savedOutingId == nil
      )
      .padding(.horizontal, theme.space.gutter)
      .padding(.top, theme.space.separate)

      if let message = review.saveErrorMessage {
        Text(message)
          .font(theme.type.label)
          .foregroundStyle(theme.colors.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, theme.space.gutter)
          .padding(.top, theme.space.snug)
      }

      HStack {
        Button(action: onDiscard) {
          Text("Discard")
            .font(theme.type.headline)
            .foregroundStyle(theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(review.isSaving)
        .accessibilityLabel("Discard this session without saving")

        Spacer()

        SaveButton(
          isSaving: review.isSaving,
          isSaved: review.savedOutingId != nil,
          action: onSave
        )
      }
      .padding(theme.space.gutter)
    }
    .fullScreenCover(item: $openPhoto) { photo in
      PhotoLightbox(source: photo.source, caption: photo.caption) { openPhoto = nil }
        .navigationTransition(.zoom(sourceID: photo.id, in: photoNamespace))
        // This screen runs dark, so the margin the zoom opens behind it should too — see
        // ``PhotoLightbox`` for why the asking belongs here and not around the flow.
        .preferredColorScheme(.dark)
    }
  }

  /// Whether anything on this timeline can actually be kept or dropped — what decides
  /// whether the hint under the subtitle is worth printing.
  private var hasConfirmableRows: Bool {
    session.events.contains { $0.namedBird != nil }
  }

  /// The one line under the title: how long it ran, and what it holds. Counts rather than
  /// a lecture — the list below is the detail.
  ///
  /// **The bird count is the *kept* count, and that is the whole point of it.** It used to
  /// count every row that named a bird, which meant dropping one changed the row under the
  /// thumb and nothing else on the screen — the one interaction this screen exists for had
  /// no consequence anywhere a watcher was looking. Counting what will actually enter the
  /// life list makes the header answer every tap, which is also how the interaction teaches
  /// itself to somebody who found it by accident.
  private var subtitle: String {
    let named = session.events.filter { $0.namedBird != nil }
    let kept = named.filter { !review.droppedBirds.contains($0.at) }.count
    let photos = session.events.filter { event in
      if case .photo = event { return true }
      return false
    }.count
    var parts = [sessionStamp(review.durationSeconds)]
    if kept > 0 { parts.append(kept == 1 ? "1 bird" : "\(kept) birds") }
    if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
    // Two different nothings, and they are not the same sentence: a session that found no
    // birds, and a session whose birds the watcher threw all back. Saying "nothing
    // identified" for the second would be the screen forgetting what it just did.
    if named.isEmpty && photos == 0 {
      parts.append("nothing identified")
    } else if kept == 0 && !named.isEmpty {
      parts.append("no birds kept")
    }
    return parts.joined(separator: " · ")
  }
}

extension SessionEvent {

  /// The bird this row would put in the life list, or `nil` where it names none.
  ///
  /// **Three kinds of row can name one**, and the journal treats all three the same: a detection
  /// the microphone found, an answer the script linked a species to, and — since a photo carries
  /// its own identification — a photograph the app named a bird in. Asking one question of the
  /// event, here, is what keeps the count in the subtitle, the tappability of a row and the chip
  /// on it from drifting into three slightly different lists.
  var namedBird: String? {
    switch self {
    case let .bird(_, _, commonName, _): commonName
    case let .answer(_, _, _, speciesId, commonName): speciesId != nil ? commonName : nil
    case let .photo(_, _, _, _, _, _, identification):
      if case let .bird(_, commonName, _) = identification { commonName } else { nil }
    case .speech: nil
    }
  }
}

/// One event, read back — the live log's row with its stamp and its inks, plus the one
/// thing review adds: anything that would enter the life list carries its keep-or-drop
/// state, and the whole row takes the tap, because the chip alone is a small target for
/// a decision this screen exists for.
///
/// See ``SessionEvent/namedBird`` for what counts as naming one — a kept bird is a
/// sighting, however it was reached.
private struct ReviewRow: View {
  @Environment(\.theme) private var theme

  let event: SessionEvent
  let isDropped: Bool
  let photoNamespace: Namespace.ID
  let onToggle: () -> Void
  let onOpenPhoto: (OpenPhoto) -> Void

  var body: some View {
    row
      .contentShape(.rect)
      // **A tap gesture rather than a `Button`, because the photograph in this row needs a
      // tap of its own.** Nested buttons hand every touch to the outer one, so a thumbnail
      // inside a keep-or-drop button could never be opened; nested tap gestures give the
      // innermost the area it actually covers, which is exactly the split this row wants —
      // 44 points of photograph opens the picture, and the rest of the row still toggles.
      .onTapGesture { if isConfirmable { onToggle() } }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(isConfirmable ? .isButton : [])
      .accessibilityHint(isConfirmable ? (isDropped ? "Keep this bird" : "Drop this bird") : "")
      // Spelled out as its own action because the combined element flattens the thumbnail's
      // own gesture away — without this the picture would be reachable by touch and not by
      // VoiceOver, which is the half-built version of this feature.
      .accessibilityActions {
        if let photo = openablePhoto {
          Button("View photo") { onOpenPhoto(photo) }
        }
      }
  }

  private var isConfirmable: Bool { event.namedBird != nil }

  /// This row's photograph, where it has one that has actually arrived.
  private var openablePhoto: OpenPhoto? {
    guard case let .photo(at, _, image, _, _, _, identification) = event,
      let image
    else { return nil }
    var caption: String?
    switch identification {
    case let .bird(_, commonName, _): caption = commonName
    case let .words(text): caption = text
    default: caption = nil
    }
    return OpenPhoto(id: String(at), source: .image(image), caption: caption)
  }

  private var row: some View {
    HStack(alignment: .center, spacing: theme.space.related) {
      Text(sessionStamp(event.at))
        .font(theme.type.data)
        .foregroundStyle(theme.colors.textFaint)
        .frame(width: reviewStampWidth, alignment: .leading)

      switch event {
      case let .photo(_, _, image, _, _, _, identification):
        // Always present by the time the review opens — ``RealtimeViewModel/stopSession()``
        // drops any capture whose picture was still crossing, because that photograph is
        // never arriving now and an empty tile is not a thing to decide about.
        if let image {
          Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: reviewPhotoSize, height: reviewPhotoSize)
            .clipShape(.rect(cornerRadius: theme.space.tight))
            .matchedTransitionSource(id: String(event.at), in: photoNamespace)
            .onTapGesture { if let photo = openablePhoto { onOpenPhoto(photo) } }
        }

        // What the app made of it, beside it — the same place the live log put it, so
        // reading a session back and watching it happen are the same picture. A capture
        // still waiting when the stop came is simply a photograph: the session is over,
        // and there is nothing left to be waiting for.
        switch identification {
        case let .bird(_, commonName, confidence):
          PlateLabel(
            text: commonName,
            color: isDropped ? theme.colors.textFaint : theme.colors.gilt
          )
          PlateLabel(
            text: "\(Int((confidence * 100).rounded()))%",
            color: isDropped ? theme.colors.textFaint : theme.colors.textSecondary
          )
          Spacer(minLength: theme.space.related)
          KeepChip(name: commonName, isDropped: isDropped)

        case let .words(text):
          Text(text)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.gilt)
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
          PlateLabel(text: "Photo", color: theme.colors.textSecondary)
        }

      case let .speech(_, text):
        Text(text)
          .font(theme.type.body)
          .foregroundStyle(theme.colors.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)

      case let .answer(_, text, _, speciesId, commonName):
        Text(text)
          .font(theme.type.body)
          .foregroundStyle(isDropped ? theme.colors.textFaint : theme.colors.gilt)
        if let commonName {
          PlateLabel(
            text: commonName,
            color: isDropped ? theme.colors.textFaint : theme.colors.gilt
          )
        }
        if speciesId != nil {
          Spacer(minLength: theme.space.related)
          KeepChip(name: commonName ?? "this bird", isDropped: isDropped)
        }

      case let .bird(_, _, commonName, confidence):
        // A dropped bird keeps its row but loses its ink: the timeline records what
        // happened; the gilt is for what the journal will call a sighting.
        PlateLabel(
          text: commonName,
          color: isDropped ? theme.colors.textFaint : theme.colors.gilt
        )
        PlateLabel(
          text: "\(Int((confidence * 100).rounded()))%",
          color: isDropped ? theme.colors.textFaint : theme.colors.textSecondary
        )
        Spacer(minLength: theme.space.related)
        KeepChip(name: commonName, isDropped: isDropped)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// The keep-or-drop state, worn identically by every row that names a bird.
private struct KeepChip: View {
  @Environment(\.theme) private var theme

  let name: String
  let isDropped: Bool

  var body: some View {
    PlateLabel(
      text: isDropped ? "Dropped" : "Sighting",
      color: isDropped ? theme.colors.textFaint : theme.colors.verdigris
    )
    .accessibilityLabel(
      isDropped
        ? "\(name) dropped — tap to keep it"
        : "\(name) kept as a sighting — tap to drop it"
    )
  }
}

/// Save, in the same verdigris the wizard's claim wears: one color for "this enters the
/// journal", wherever it is offered. The saved state is only ever seen for the beat before
/// the cover falls.
private struct SaveButton: View {
  @Environment(\.theme) private var theme

  let isSaving: Bool
  let isSaved: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(isSaved ? "In your journal" : isSaving ? "Saving…" : "Save to Journal")
        .font(theme.type.headline)
        .foregroundStyle(isSaved || !isSaving ? theme.colors.paperRaised : theme.colors.textFaint)
        .padding(.horizontal, theme.space.gutter)
        .frame(height: 48)
        .background(isSaved || !isSaving ? theme.colors.verdigris : theme.colors.rule)
        .clipShape(.rect(cornerRadius: 3))
    }
    .buttonStyle(.plain)
    .disabled(isSaving || isSaved)
  }
}

/// The stamp column, same width as the live log's, so the flow reads as one instrument.
private let reviewStampWidth: CGFloat = 44

/// A photo in the review — the log's size; recognising the bird is still the job.
private let reviewPhotoSize: CGFloat = 44
