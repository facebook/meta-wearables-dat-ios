/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CaptureSourceKind.swift
//  birdspotter
//

import Foundation

/// Whose ears and eyes these are.
///
/// Shared by every capture seam — ``CameraPreviewSource`` and ``AudioCaptureSource`` both report
/// one — because a session asks the question once and shows the answer once. The real-time screen
/// says it out loud in a pill: a demo where the audience cannot tell whether they are looking
/// through the phone or through the glasses is a demo that proves nothing, and ``simulated``
/// exists for the same reason the "Simulated device" badge does — a Mock Device Kit feed must
/// never be mistaken for hardware.
nonisolated enum CaptureSourceKind: Sendable {
  /// The phone's own camera and microphone. Always available; the fallback every path reaches.
  case phone

  /// The glasses, over Bluetooth.
  case glasses

  /// A canned feed standing in for either — Mock Device Kit, or a bundled clip.
  case simulated
}
