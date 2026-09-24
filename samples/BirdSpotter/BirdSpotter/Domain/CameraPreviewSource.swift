/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CameraPreviewSource.swift
//  birdspotter
//

import AVFoundation
import CoreGraphics
import Foundation

/// One frame of a live camera, already the right way up.
///
/// **Upright is the contract, not a suggestion.** Each source normalises at its own edge — the
/// capture connection is given a rotation angle — so nothing downstream carries a rotation it
/// has to remember to apply. The alternative (ship the angle, rotate in the renderer) leaks one
/// platform's sensor mounting into a screen that should only ever draw what it is handed.
///
/// A wrapper around a single `CGImage` rather than a stream of bare images, because a bare image
/// says nothing about what it is *for*: this is **the photograph the shutter will take** — see
/// ``CameraPreviewSource/previewStream()`` for what frames are and are not used for.
///
/// The two are the same choice: a graphics-framework image, not a UI-framework one, so the domain
/// does not depend on the UI framework to describe a picture.
nonisolated struct PreviewFrame: Sendable {
  let image: CGImage
}

/// The platform's own hardware-path picture — what the viewfinder *shows*, where ``PreviewFrame``
/// is what the shutter *takes*.
///
/// The payload is deliberately platform plumbing: an `AVCaptureVideoPreviewLayer` the compositor
/// draws the camera into directly, with no frame ever crossing app code — the whole point of the
/// handle. The type exists so the *seam* is mirrored even though the payload cannot be.
///
/// `@unchecked Sendable` because a `CALayer` is not, and this only carries it: built on the
/// capture queue, handed across once, and touched only on the main thread after that.
nonisolated final class CameraViewfinder: @unchecked Sendable {
  let layer: AVCaptureVideoPreviewLayer

  init(layer: AVCaptureVideoPreviewLayer) {
    self.layer = layer
  }
}

/// Why a camera has no picture.
///
/// Three cases, because there are exactly three answers worth giving a user: they said no, there is
/// nothing to look through, or something else took the camera.
nonisolated enum CameraPreviewError: Error, Equatable, Sendable {
  /// Camera permission is not granted. The Identify gate should have caught this first.
  case accessDenied

  /// No camera to open — no hardware to look through.
  case unavailable

  /// The camera was opened and then lost: another app took it, or the session dropped.
  case interrupted
}

/// Something a camera can be asked to do beyond producing frames.
///
/// **A set, not a pile of booleans**, because the question the viewfinder asks is always "can this
/// one do X" and the answer for a source that can do neither of them should be an empty set rather
/// than two `false`s it had to remember to write.
///
/// The phone answers with both; a simulated source answers with neither, and the panel simply has
/// fewer controls on it, without a line of `if kind == ...` anywhere in the UI. A control that
/// cannot do anything is not disabled here; it is **absent**, because a greyed-out flash is an
/// invitation to wonder what is broken.
nonisolated enum CameraControl: Sendable, Hashable {
  /// A light that can be lit for the moment a photo is taken — see
  /// ``CameraPreviewSource/setTorch(_:)``.
  case flash

  /// Magnification, over some range wider than a single point.
  case zoom
}

/// A live camera the watcher frames a shot with — **the phone's**, and only the phone's.
///
/// This seam used to be described as the one the glasses would arrive through, and the frames-only
/// shape was chosen so a `GlassesPreviewSource` could drop in behind it. That class is never
/// coming: **a pair of glasses has no viewfinder in the app**, because the wearer's own eyes are
/// the viewfinder — they look at the bird, press the action button, and the finished photo lands
/// on the session timeline as an event, the way a detector's finding does. What the glasses need
/// is a seam for *photos that arrive*, not one for frames that stream.
///
/// That is why this source has two outputs instead of one:
///
/// - ``viewfinderStream()`` is **the picture** — the platform's hardware path, camera to
///   compositor, never touching app code. This is what makes a pinch feel like the camera app's:
///   the preview does not wait on any copy this process makes.
/// - ``previewStream()`` is **the photograph** — upright frames the shutter grabs the latest of,
///   and the fallback picture for sources (SwiftUI previews, simulated feeds) that have no layer
///   to offer.
///
/// Cold, per the architecture contract: iterating starts the camera and cancelling stops it, so
/// there is no `start()`/`stop()` pair to keep in sync across two platforms. The frame stream
/// fails with a ``CameraPreviewError``; it does not finish on its own.
nonisolated protocol CameraPreviewSource: Sendable {

  /// Which camera this is — what the viewfinder's source pill reads.
  var kind: CaptureSourceKind { get }

  /// What this camera can be asked to do — see ``CameraControl``. Fixed for the life of the
  /// source: it describes the hardware, not the state of a running stream.
  var controls: Set<CameraControl> { get }

  /// How far this camera magnifies, `1` being none. `1...1` for a camera that cannot, which is
  /// also what an absent ``CameraControl/zoom`` says — the range is here so a pinch has something
  /// to clamp against without asking the hardware mid-gesture.
  var zoomRange: ClosedRange<Double> { get }

  /// Frames, upright, until the iteration ends. Cold: iterating is what opens the camera.
  func previewStream() -> AsyncThrowingStream<PreviewFrame, Error>

  /// The hardware-path picture, for as long as ``previewStream()`` is iterated — a new
  /// ``CameraViewfinder`` whenever the platform builds one.
  ///
  /// Empty by default, and empty is meaningful: a source with no layer to offer (a preview, a
  /// simulated feed) simply never yields, and the panel falls back to drawing
  /// ``previewStream()``'s frames — a picture either way, just not a free one.
  func viewfinderStream() -> AsyncStream<CameraViewfinder>

  /// Hold the light on, or let it go.
  ///
  /// **A torch is the mechanism; a flash is what it is for.** There is no still-capture pipeline
  /// here to hand a flash mode to — a photo is the viewfinder frame that was on screen — so the
  /// screen lights the torch, waits for the exposure to catch up, takes its frame and puts the
  /// light out. That sequence is the session's to run, not this seam's: how long to wait is a
  /// judgement about photographs, and a camera source only knows about lights.
  func setTorch(_ isOn: Bool)

  /// Magnify, clamped to ``zoomRange``.
  func setZoom(_ factor: Double)
}

/// **Doing none of it is the default.** A source that only produces frames — the previews,
/// whatever a demo needs next — conforms by saying nothing, and the two setters below are the
/// honest answer to being asked anyway: a camera with no torch does not fail when told to light
/// up, it simply has no light. The screen never reaches them, because ``controls`` said so first.
nonisolated extension CameraPreviewSource {
  var controls: Set<CameraControl> { [] }
  var zoomRange: ClosedRange<Double> { 1...1 }

  func viewfinderStream() -> AsyncStream<CameraViewfinder> {
    AsyncStream { $0.finish() }
  }

  func setTorch(_ isOn: Bool) {}
  func setZoom(_ factor: Double) {}
}
