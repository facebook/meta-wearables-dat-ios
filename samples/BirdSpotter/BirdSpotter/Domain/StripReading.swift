/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  StripReading.swift
//  birdspotter
//

import Foundation

/// The two ways the session's strip can draw what the microphone is hearing.
///
/// **One instrument, two readings — not two instruments.** They come off one buffer and one dB
/// scale; what differs is the question the picture answers, and the axis it spends its width on.
///
/// - ``sonogram`` spends the width on **time**: eight seconds of history scrolling right to left,
///   the newest column hard against the right edge. It says *what was in the sound* — the shape of
///   a call, which is what a watcher compares against the reference strip on a bird's page.
/// - ``waveform`` spends the width on **frequency**, and shows only *now*: a symmetric trace that
///   opens about the centre line and moves with the room. It says *what the microphone is hearing
///   this instant*, which is the reading an audience with no training in sonograms can read from
///   the back of a room — and the one that makes it obvious the app is listening at all.
///
/// It is a device preference, kept in ``SessionSettingsStore``: nothing recorded, kept or saved
/// knows which was on screen, and the choice outlives the session that made it.
nonisolated enum StripReading: String, CaseIterable, Sendable {
  /// Frequency against time, in magma — the strip this screen has always drawn.
  case sonogram

  /// Frequency against loudness, right now — the live trace.
  case waveform

  /// The word on the switch. Four letters each, so neither side of the track is the wider one.
  var plate: String {
    switch self {
    case .sonogram: "Sono"
    case .waveform: "Wave"
    }
  }

  /// What it is called out loud — the strip's accessibility label, and the switch's.
  var label: String {
    switch self {
    case .sonogram: "Sonogram"
    case .waveform: "Waveform"
    }
  }
}
