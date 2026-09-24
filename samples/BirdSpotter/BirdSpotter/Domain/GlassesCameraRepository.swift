/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesCameraRepository.swift
//  birdspotter
//

import Foundation

/// How a captured photograph is encoded. JPEG is what the capability hands over — a capture
/// request carries size and compression, never a format — so a second encoding lands here as
/// a second case the day the SDK grows one.
nonisolated enum PhotoFormat: Sendable {
  case jpeg
}

/// How much of the sensor a photograph keeps.
///
/// The coarse of the two knobs, and the one that costs the most: every step up is more
/// bytes over a link that is already the constraint everything else on this path is built
/// around. ``sessionDefault`` is what the live shutter asks for — see ``CaptureQuality``
/// for the argument the pair of them settle.
///
/// The four steps are 480p, 720p, 1080p and the sensor's own 4032×3024 — roughly twelve
/// megapixels. The SDK exposes an opaque size rather than pixel dimensions, so the glasses
/// decide what it means. Treat the numbers as the vendor's claim until a real crossing
/// prints its own — which is exactly what the camera settings screen is for.
nonisolated enum CaptureResolution: String, CaseIterable, Identifiable, Sendable {
  case small
  case medium
  case large
  case full

  var id: String { rawValue }

  /// What the live session's shutter asks for.
  static let sessionDefault = CaptureResolution.medium

  /// The size the way somebody choosing one actually thinks about it.
  ///
  /// **The SDK's own four words are useless on a picker**: `medium` says nothing about what
  /// it will cost or what it will show. So the label is the number, and the vendor's word
  /// survives only where there is no number to give: the largest is whatever this SKU's
  /// sensor is.
  var displayLabel: String {
    switch self {
    case .small: "480p"
    case .medium: "720p"
    case .large: "1080p"
    case .full: "Full · 12 MP"
    }
  }
}

/// How hard a photograph is compressed on the way out.
///
/// The fine knob: it trades feather detail against crossing time without changing the
/// number of pixels. ``sessionDefault`` is what the live shutter asks for.
///
/// **These two defaults are the whole bandwidth argument, and they are a judgement call.**
/// The link is the constraint the capture path is built around, and every step up in size
/// is time the watcher spends holding still — and, since the still crosses on the same
/// channel the sensors are on, time the readings spend down. Full size is a bird nobody
/// waits for; the smallest is a bird nobody can identify. The middle size at the heaviest
/// compression the SDK sells is the fast end of that trade, taken deliberately while the
/// crossing is still being timed on real glasses. The feather detail a catalog match wants
/// is the reason to walk the quality back up, and what walking it up costs is exactly what
/// ``GlassesCameraRepository/capturePhoto(format:resolution:quality:)`` exists to let
/// somebody measure.
nonisolated enum CaptureQuality: String, CaseIterable, Identifiable, Sendable {
  case low
  case medium
  case high

  var id: String { rawValue }

  /// What the live session's shutter asks for.
  static let sessionDefault = CaptureQuality.low

  var displayLabel: String {
    switch self {
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    }
  }
}

/// A photograph that finished its crossing from the glasses — encoded bytes, ready to
/// decode and stamp onto the session timeline.
///
/// Capture metadata crosses beside the image as a blob whose contents are still
/// unmeasured; nothing is invented for it here until a real crossing says what it holds.
nonisolated struct CapturedPhoto: Equatable, Sendable {
  let imageData: Data
}

/// The glasses camera, reduced to the one thing a session asks of it: **a photograph,
/// on demand.**
///
/// There is deliberately no frame stream here — a pair of glasses has no viewfinder in
/// this app, because the wearer's own eyes are the viewfinder (see
/// ``CameraPreviewSource``, which is the phone's and only the phone's). The call
/// suspends while the image makes its Bluetooth Classic crossing — the "receiving from
/// the glasses" beat is real, about a second, and worth showing rather than hiding.
///
/// Throws ``GlassesError/notConnected`` without a running session, and
/// ``GlassesError/transferFailed`` when the crossing does not finish.
nonisolated protocol GlassesCameraRepository: Sendable {

  /// Whether a capture on this build actually asks for the size and compression it is
  /// handed, or takes whatever the transport gives it.
  ///
  /// **A reading, not a switch.** The knobs belong to a transfer channel the capture path
  /// only reaches on some builds of the SDK; where it cannot, a request still succeeds and
  /// still returns a photograph — it simply returns the one the channel was always going
  /// to send. That is the failure worth naming, because from the outside it is
  /// indistinguishable from the settings working: bytes arrive either way. A screen that
  /// offers the two knobs reads this first and says so rather than pretending.
  var honoursCaptureSettings: Bool { get }

  /// One photograph through the wearer's own camera, at the size and compression asked
  /// for. Suspends for the transfer.
  ///
  /// The settings are honoured only where ``honoursCaptureSettings`` says they are.
  func capturePhoto(
    format: PhotoFormat,
    resolution: CaptureResolution,
    quality: CaptureQuality
  ) async throws -> CapturedPhoto
}

extension GlassesCameraRepository {

  /// The live session's shutter: a photograph at the app's own settings.
  ///
  /// The overwhelmingly common call, and the one the session makes — the settings are a
  /// standing decision about the link (see ``CaptureQuality``), not something a press of
  /// the temple button gets to reconsider.
  func capturePhoto(format: PhotoFormat) async throws -> CapturedPhoto {
    try await capturePhoto(
      format: format,
      resolution: .sessionDefault,
      quality: .sessionDefault
    )
  }
}
