/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesCameraViewModel.swift
//  birdspotter
//

import Foundation
import ImageIO

/// One photograph that crossed, and everything measured about the crossing.
///
/// **The numbers are the point of the screen, not decoration on it.** A photograph on its
/// own answers "did it work"; the size it was asked for, the bytes that arrived and the
/// seconds they took are what answer "what does `large` cost", which is the question the
/// two pickers above exist to ask.
nonisolated struct GlassesCameraShot: Equatable, Sendable {
  /// Where the bytes landed — what the share sheet is handed. See ``CaptureScratchStore``.
  let fileURL: URL

  /// What was asked for, kept beside the result rather than read off the pickers: the
  /// pickers move on to the next experiment, and a photograph must go on saying which
  /// settings it is the answer for.
  let resolution: CaptureResolution
  let quality: CaptureQuality

  let byteCount: Int

  /// The image's own size, or `nil` when the bytes could not be read as an image at all.
  let pixelWidth: Int?
  let pixelHeight: Int?

  /// How long the crossing took, shutter to bytes.
  let crossingMillis: Int
}

/// What the camera screen shows.
nonisolated struct GlassesCameraUiState: Equatable, Sendable {
  /// Whether a session has been asked for and not yet hung up on.
  var isRunning: Bool = false

  /// Where the session is — `nil` before the first reading.
  var sessionState: GlassesSessionState?

  /// Meta AI's camera grant — `nil` before the first reading. Without it the shutter is
  /// an offer that cannot be kept.
  var cameraAccess: GlassesAccess?

  /// Whether the two pickers below actually reach the capture — see
  /// ``GlassesCameraRepository/honoursCaptureSettings``.
  var honoursCaptureSettings: Bool = true

  /// What the next shutter will ask for.
  var resolution: CaptureResolution = .sessionDefault
  var quality: CaptureQuality = .sessionDefault

  /// Whether a crossing is in flight. The shutter is one at a time — the capability
  /// refuses a second anyway, and a queue of them would be a queue of things nobody asked
  /// for by the time they landed.
  var isCapturing: Bool = false

  /// The last photograph that arrived, or `nil` before the first one.
  var shot: GlassesCameraShot?

  /// Why the last shutter came back with nothing. Cleared by the next press.
  var captureFailure: String?

  /// Why the run ended, when it ended badly.
  var failure: String?

  /// Whether the shutter can be pressed at all: a session up, and nothing already crossing.
  ///
  /// **The grant is deliberately not in this test.** A denied grant is read off a live link
  /// and can be answered in another app between one press and the next, so refusing the
  /// press on it would leave a dead button on a screen whose own reading has gone stale.
  /// The row above says what is wrong; the press is allowed to fail honestly.
  var canCapture: Bool {
    sessionState == .started && !isCapturing
  }
}

/// A session opened for one purpose: to take one photograph at chosen settings and look at
/// what comes back.
///
/// **A measuring instrument, not a feature.** The live flow already takes photographs, at
/// the app's own standing settings and straight onto the timeline where the point of them is
/// the bird. What it cannot do is take the *same* picture twice at two sizes and say what
/// the second one cost — which is the only way the standing settings (see
/// ``CaptureQuality``) ever get to be more than a guess. So this screen opens a session, puts
/// the SDK's two knobs on screen, and prints bytes and milliseconds beside the result.
///
/// The session comes up the moment the screen opens, the way the other glasses sub-screens
/// do: the whole point of being here is to fire the shutter, and a Connect button first would
/// just be a step on every attempt. The **full** lease, deliberately and unlike the display
/// screen's — the camera is exactly what this wants lit.
@MainActor
@Observable
final class GlassesCameraViewModel {

  private let glassesSession: any GlassesSessionRepository
  private let glassesCamera: any GlassesCameraRepository
  private let scratch: CaptureScratchStore

  private(set) var uiState = GlassesCameraUiState()

  /// The run: the session's lease, and the device watcher that lives inside it.
  private var run: Task<Void, Never>?

  /// The crossing in flight. Held so leaving the screen can cancel it rather than leave a
  /// fifteen-second timeout running behind a screen nobody is on.
  private var capture: Task<Void, Never>?

  /// How many photographs this visit has taken, which is all the file names need to be
  /// distinct — see ``fileName(for:quality:)``.
  private var shotCount = 0

  init(
    glassesSession: any GlassesSessionRepository,
    glassesCamera: any GlassesCameraRepository,
    scratch: CaptureScratchStore
  ) {
    self.glassesSession = glassesSession
    self.glassesCamera = glassesCamera
    self.scratch = scratch
    uiState.honoursCaptureSettings = glassesCamera.honoursCaptureSettings
  }

  /// Opens the session, and throws away whatever the last visit left on disk.
  ///
  /// Idempotent — called when the screen arrives, and again only by the retry offered
  /// after a failure. The sweep is on the way in for the reason ``CaptureScratchStore/empty()``
  /// gives.
  func start() {
    guard run == nil else { return }
    scratch.empty()
    uiState.isRunning = true
    uiState.failure = nil
    run = Task { [weak self] in
      await self?.hold()
      self?.run = nil
    }
  }

  /// Hangs up, and drops a crossing still in the air.
  func stop() {
    run?.cancel()
    run = nil
    capture?.cancel()
    capture = nil
    uiState.isRunning = false
    uiState.isCapturing = false
  }

  /// What the next shutter asks for. Changing either leaves the photograph on screen
  /// alone — it carries the settings it was taken at, so the two can be compared rather
  /// than one silently relabelled.
  func choose(resolution: CaptureResolution) {
    uiState.resolution = resolution
  }

  func choose(quality: CaptureQuality) {
    uiState.quality = quality
  }

  /// Fires the shutter and waits out the crossing.
  ///
  /// The previous photograph stays on screen for the whole wait rather than being cleared
  /// at the press: a blank frame for a second and a half reads as the screen having lost
  /// the picture, and there is nothing to compare against while it is blank.
  func capturePhoto() {
    guard uiState.canCapture else { return }
    let resolution = uiState.resolution
    let quality = uiState.quality
    uiState.isCapturing = true
    uiState.captureFailure = nil
    shotCount += 1
    let name = Self.fileName(for: resolution, quality: quality, index: shotCount)

    capture = Task { [weak self, glassesCamera, scratch] in
      let startedAt = ContinuousClock.now
      do {
        let photo = try await glassesCamera.capturePhoto(
          format: .jpeg,
          resolution: resolution,
          quality: quality
        )
        let crossing = ContinuousClock.now - startedAt
        guard !Task.isCancelled else { return }

        // Off the main actor: a full-size still is megabytes, and both the write and
        // the header read are file work that has no business on the thread drawing
        // the screen.
        let landed = await Task.detached(priority: .userInitiated) {
          let url = try? scratch.write(photo.imageData, named: name)
          let size = url.flatMap { Self.pixelSize(of: $0) }
          return (url, size)
        }.value

        guard !Task.isCancelled, let self else { return }
        guard let fileURL = landed.0 else {
          // Bytes that crossed and then could not be written are a different
          // failure from a crossing that never finished, and saying so is the
          // difference between blaming the glasses and blaming the phone.
          BirdLog.error(.glasses, "camera screen — the photograph could not be written")
          self.uiState.isCapturing = false
          self.uiState.captureFailure =
            "The photograph arrived but could not be saved on this phone."
          return
        }
        self.uiState.shot = GlassesCameraShot(
          fileURL: fileURL,
          resolution: resolution,
          quality: quality,
          byteCount: photo.imageData.count,
          pixelWidth: landed.1?.width,
          pixelHeight: landed.1?.height,
          crossingMillis: crossing.wholeMilliseconds
        )
        self.uiState.isCapturing = false
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, let self else { return }
        BirdLog.error(.glasses, "camera screen — the shutter came back empty", error)
        self.uiState.isCapturing = false
        self.uiState.captureFailure = Self.captureParting(for: error)
      }
      self?.capture = nil
    }
  }

  /// The run itself: the session held open, the device snapshot read for as long as it is,
  /// and the camera grant re-asked whenever the link changes — the grant lives on the
  /// glasses, so a pair coming into range is the moment it becomes answerable at all.
  private func hold() async {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        // The watcher outlives nothing: the device stream never completes on its own,
        // so it is cancelled by hand once the session's stream has ended.
        group.addTask { [glassesSession] in
          // The device stream is followed for its *arrivals* rather than its
          // contents: the grant lives on the glasses, so a pair coming into range is
          // the moment it becomes answerable at all. Whether the pair is reachable is
          // deliberately not read here — the screen above owns that explanation, and
          // saying it twice is two places to keep true.
          for await _ in glassesSession.deviceInfoStream() {
            let access = await glassesSession.access(.camera)
            await MainActor.run { self.uiState.cameraAccess = access }
          }
        }
        for try await state in glassesSession.sessionStream() {
          uiState.sessionState = state
        }
        group.cancelAll()
      }
      // A session that ends of its own accord — a doff, a fold, a long press — takes
      // the shutter with it. The photograph stays: it is a measurement that already
      // happened, and it is still true.
      uiState.isRunning = false
    } catch is CancellationError {
      return
    } catch {
      BirdLog.error(.glasses, "camera screen — the session ended in failure", error)
      uiState.isRunning = false
      uiState.failure = Self.parting(for: error)
    }
  }

  /// Why the run ended, in a line. The same two answers the realtime screen gives, because
  /// they are the only two the app can tell apart — the log line beside this one carries
  /// the rest.
  nonisolated static func parting(for error: Error) -> String {
    if case GlassesError.glassesUpdateRequired = error {
      return "Your glasses need a firmware update — check them in the Meta AI app"
    }
    return "The glasses session ended — check they are connected and try again"
  }

  /// Why one shutter came back empty. **Separate from ``parting(for:)`` because a failed
  /// photograph is not a failed session** — the link is usually still up, the next press
  /// usually works, and telling somebody to check their connection over a dropped crossing
  /// sends them to fix something that is not broken.
  nonisolated static func captureParting(for error: Error) -> String {
    switch error {
    case GlassesError.transferFailed:
      "The photograph never finished crossing. Try again — a big one takes longer."
    case GlassesError.notConnected:
      "The camera is not up. Give the session a moment, or reconnect."
    default:
      "The shutter failed."
    }
  }

  /// What one photograph is called on disk: the settings it was taken at, and a number to
  /// keep two of them apart.
  ///
  /// **The settings are in the name on purpose.** This name is what the share sheet shows
  /// and what lands in the camera roll, and three test shots called `photo-1`, `photo-2`,
  /// `photo-3` are three photographs nobody can tell apart an hour later — which is the
  /// whole of what the exercise was for.
  nonisolated static func fileName(
    for resolution: CaptureResolution,
    quality: CaptureQuality,
    index: Int
  ) -> String {
    "glasses-\(resolution.rawValue)-\(quality.rawValue)-\(index).jpg"
  }

  /// The image's dimensions, read from the file's header rather than by decoding it —
  /// `CGImageSourceCopyPropertiesAtIndex` never materialises the bitmap, which for a
  /// full-size still is the difference between a few bytes read and several megabytes
  /// of pixels nobody wanted.
  nonisolated static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }
}

private extension Duration {
  /// Whole milliseconds, read off a monotonic clock — the property that matters, since a
  /// wall clock corrected mid-crossing would report a photograph that arrived before it
  /// was asked for.
  var wholeMilliseconds: Int {
    let (seconds, attoseconds) = components
    return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
  }
}
