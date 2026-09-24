/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LogCategory.swift
//  birdspotter
//

import Foundation

/// Which part of the app a diagnostic line came from.
///
/// **Category, because that is what the platform calls it.** It is the `category` of
/// `Logger(subsystem:category:)`, so a developer already knows what it is from the system
/// logger they use every day. (It deliberately is *not* "channel" — that word is spoken for
/// by the identify log, where it separates discrete events from continuous ones.)
///
/// **The list answers "was that the glasses or the phone?"** That is the question a demo
/// post-mortem opens with, and it is why ``glasses`` is its own category rather than a
/// prefix on a message: the viewer filters on these, so one tap gives you every line the
/// wearable was responsible for and nothing else. The rest of the list is the phone.
///
/// The raw value is what a log file carries, so it is fixed by contract — renaming a case
/// would orphan every line already written.
enum LogCategory: String, CaseIterable, Sendable {

  /// Launch, the composition root, and anything about the process itself.
  case app

  /// **The glasses.** DAT registration, the paired-device roster, the session, the camera
  /// stream, and photographs crossing the link. Everything the wearable does and nothing
  /// the phone does — see ``DatGlassesSessionRepository``.
  case glasses

  /// A real-time run, end to end: started, what it heard, what it confirmed, how it
  /// finished. The app's own session, not the DAT one — that is ``glasses``.
  case session

  /// Microphones. Which one is live matters more than anything else here: a run silently
  /// falling back from the glasses to the phone is the failure this category exists for.
  /// See ``FailoverAudioSource``.
  case audio

  /// The viewfinder and the shutter — the phone's camera. A photograph taken *through the
  /// glasses* is ``glasses``, because it is the link that decides whether it arrives.
  case camera

  /// Outings saved, amended and deleted, and the media that goes with them.
  case journal

  /// The bundled field guide: opening `catalog.db`, and the seed swap when a build ships
  /// a newer one.
  case catalog

  /// Camera, microphone and location grants, on the phone.
  case permissions

  /// The Demo Director — which preset is armed, and what it answered.
  case demo

  /// What the file writes and the viewer filters on.
  var id: String { rawValue }

  /// What the viewer prints on a filter chip.
  var displayLabel: String {
    switch self {
    case .app: "App"
    case .glasses: "Glasses"
    case .session: "Session"
    case .audio: "Audio"
    case .camera: "Camera"
    case .journal: "Journal"
    case .catalog: "Catalog"
    case .permissions: "Permissions"
    case .demo: "Demo"
    }
  }

  /// Parses a category back off a log line. Unknown text is `nil` — a file written by a
  /// build that had a category this one does not know is still readable, and the line
  /// keeps its text rather than being filed under the wrong heading.
  static func parse(_ raw: String) -> LogCategory? {
    LogCategory(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
  }
}
