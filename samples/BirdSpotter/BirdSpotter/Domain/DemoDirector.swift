/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirector.swift
//  birdspotter
//

import Foundation

/// The demo implementation of the identification seam — a ``SessionDetector`` whose
/// findings come from the armed ``DemoPreset`` instead of a hard-coded script.
///
/// `findingStream()` plays the preset's ambient calls on their gaps, and emits nothing at
/// all when no preset is armed — which is a legal, intended state: the session listens,
/// the shutter captures, and nothing ever identifies. The realtime screen's job is to say
/// so rather than look broken.
///
/// The other two sections answer on cue rather than on the clock, so they are pulls, not
/// a stream: the shutter asks ``response(toPhotoAt:)`` with its running per-session
/// count, and a spoken transcript asks ``answer(to:)`` — once the speech feature lands;
/// until then the lane is authorable and deliberately silent in a session.
nonisolated protocol DemoDirector: SessionDetector {

  /// The preset currently armed, or nil when identification is switched off.
  var armed: DemoPreset? { get }

  /// The scripted response for the `index`th photo of this session, counted from zero —
  /// the row at that index, ``DemoPhotoResponse/pastTheEnd`` past the end of the list, or
  /// nil when nothing is armed. The caller owns the count; it resets when a session starts.
  func response(toPhotoAt index: Int) -> DemoPhotoResponse?

  /// The question row a spoken `transcript` matches, or nil for a clean miss — the
  /// caller shows the preset's `unmatchedQuestion` line.
  func answer(to transcript: String) -> DemoQuestion?
}
