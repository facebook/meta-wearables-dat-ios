/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  PhoneCameraPreviewSource.swift
//  birdspotter
//

import AVFoundation
import CoreImage
import Foundation

/// The phone's rear camera as a ``CameraPreviewSource`` — the only live viewfinder the app has.
/// Glasses never stream one: their photos arrive finished, as timeline events.
///
/// **`AVCaptureVideoPreviewLayer` for the picture, `AVCaptureVideoDataOutput` for the
/// photograph** — two outputs on one session, because the two jobs want opposite things:
///
/// - The *picture* has to feel like a camera, which means the hardware path: the preview layer
///   hands frames straight to the compositor, no conversion in app code, zoom visible at sensor
///   rate. This file used to route the picture through the data output instead, and that
///   pipeline — convert, stream, redraw, 30 times a second — was the viewfinder lag on this
///   platform too.
/// - The *photograph* has to be bytes the app can keep: BGRA buffers the shutter grabs the
///   latest conversion of. BGRA is what makes that conversion cheap — the pixel buffer arrives
///   in the layout `CIContext` wants.
///
/// Rotation is the capture connection's job, not the renderer's: the connection is asked for 90°
/// so frames arrive upright, as ``PreviewFrame`` promises. The app is portrait-only, so that
/// angle is a constant rather than something to track.
///
/// Cold, and it means it: nothing is opened until someone iterates, and `onTermination` is what
/// stops the camera. Configuration and frame delivery both live on one private queue —
/// `startRunning()` blocks for long enough to matter, and the main thread has a viewfinder to
/// draw.
///
/// **The capture graph is built once and kept, and only the running is per stream.** The camera
/// here is a *mode* over a session that never closes, so it is opened and shut repeatedly, and
/// rebuilding the device, the input, the output and the connection each time made every reopen
/// cost a fresh `startRunning()` — long enough that the panel showed its placeholder every single
/// time. Holding the graph pays that initialisation once instead.
///
/// **Kept configured, not kept running.** `stopRunning()` still happens the moment the panel
/// closes, because a running session is what lights the camera indicator — and a watcher who shut
/// the viewfinder and still sees the phone reporting a live camera has every reason to think the
/// app is watching them. Configuration costs nothing while stopped and no frame is delivered; only
/// the rebuild is skipped.
///
/// It follows that the device outlives a stream, so ``FrameCapture/end()`` is what puts it back to
/// rest — light out, zoom home. A fresh `AVCaptureDevice` used to give that for free.
///
/// **The controls are forwarded, not owned.** What the torch and the zoom actually touch are
/// properties of the open `AVCaptureDevice`, so this passes the two setters along; with no stream
/// open the light is a no-op, which is the honest answer to being asked to light a camera nobody
/// is looking through.
///
/// The seam is ``CameraPreviewSource``; the capture graph below it is platform plumbing.
nonisolated final class PhoneCameraPreviewSource: CameraPreviewSource, @unchecked Sendable {

  let kind = CaptureSourceKind.phone

  /// A phone does both. The only line the panel's controls are built from.
  let controls: Set<CameraControl> = [.flash, .zoom]

  let zoomRange: ClosedRange<Double> = 1...maximumZoom

  /// The one capture graph, for the life of the source. Built on the first stream rather than
  /// here: constructing this happens at app launch, and opening the camera to have it ready is
  /// not something an app does before anyone has asked to see through it.
  private let capture = FrameCapture()

  func previewStream() -> AsyncThrowingStream<PreviewFrame, Error> {
    AsyncThrowingStream { continuation in
      // The Identify gate should have collected this already, so reaching here unauthorized
      // means access was revoked from Settings while the cover was open — a real path, and
      // one that reads better as an honest error than as a viewfinder that never lights up.
      guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
        continuation.finish(throwing: CameraPreviewError.accessDenied)
        return
      }

      capture.begin(continuation)
      continuation.onTermination = { [capture] _ in capture.end() }
    }
  }

  func viewfinderStream() -> AsyncStream<CameraViewfinder> {
    AsyncStream { continuation in
      capture.attachViewfinder(continuation)
    }
  }

  func setTorch(_ isOn: Bool) { capture.setTorch(isOn) }

  func setZoom(_ factor: Double) {
    capture.setZoom(min(max(factor, zoomRange.lowerBound), zoomRange.upperBound))
  }
}

/// How often a frame is actually converted into a photograph-in-waiting — ten a second.
///
/// Enough that the shutter's picture is never more than 100 ms behind the layer (the flash path
/// waits three times that for the exposure anyway), and a fraction of the copying that converting
/// every frame cost.
private let photographInterval: TimeInterval = 0.1

/// How far the viewfinder will magnify. Well under what the sensor will digitally stretch to —
/// past this a bird is a smear of four pixels, and a control that keeps going long after the
/// picture stopped improving is a control that lies about what the camera can see.
private let maximumZoom: Double = 8

/// The capture graph, confined to a single serial queue and reused across streams.
///
/// `@unchecked Sendable` is a claim about that confinement, and the claim is the whole design:
/// every member below runs on ``queue`` — configuration, delivery, teardown — so the session, the
/// device and the Core Image context are never touched from two threads at once. The compiler
/// cannot see that, which is what the annotation is for; nothing here may be called from anywhere
/// else.
///
/// One instance serves every open of the camera panel. ``begin(_:)`` configures on the first call
/// and only starts on the rest; ``end()`` stops and returns the device to rest without pulling the
/// graph down.
private nonisolated final class FrameCapture: NSObject, @unchecked Sendable,
  AVCaptureVideoDataOutputSampleBufferDelegate
{

  private let queue = DispatchQueue(label: "com.pixelandtexel.birdspotter.camera-preview")
  private let session = AVCaptureSession()
  private let context = CIContext()

  /// Where frames go, or `nil` between streams — which is also the answer to "is anyone looking
  /// through this camera", and so what the torch is guarded on.
  private var continuation: AsyncThrowingStream<PreviewFrame, Error>.Continuation?

  /// The open device and the output taking frames off it, both `queue`'s alone — the torch and
  /// the zoom are properties of a device that has to be locked before either is touched. The
  /// input is not held: the session owns it, and one owner is enough.
  private var device: AVCaptureDevice?
  private var output: AVCaptureVideoDataOutput?

  /// The hardware-path picture: a layer the compositor draws the session into directly. Built
  /// with the graph and kept with it — reopening the panel reattaches the same layer.
  private var previewLayer: AVCaptureVideoPreviewLayer?

  /// Where the layer is handed out, or `nil` between viewers. One at a time, like the frames'
  /// continuation and for the same reason.
  private var viewfinderContinuation: AsyncStream<CameraViewfinder>.Continuation?

  /// Whether the graph has been built. Set only on success, so a camera that failed to open once
  /// is tried again on the next stream rather than being remembered as broken.
  private var isConfigured = false

  /// Whether the light is meant to be on. Held rather than read back off `torchMode`, so that
  /// ending a stream can put it out without first asking a device that may be gone.
  private var isTorchWanted = false

  /// When the last frame was actually converted — the throttle's memory, `queue`'s alone.
  private var lastConverted: TimeInterval = 0

  func begin(_ continuation: AsyncThrowingStream<PreviewFrame, Error>.Continuation) {
    queue.async { [self] in
      // One graph, one viewer. Nothing opens two viewfinders today, and a second stream
      // silently stealing the frames of the first is not a thing to find out at a demo.
      self.continuation?.finish()
      self.continuation = continuation

      guard isConfigured || configure() else {
        continuation.finish(throwing: CameraPreviewError.unavailable)
        self.continuation = nil
        return
      }

      // The picture, to whoever is already waiting for it. Configuration is what creates
      // the layer, so a viewfinder attached before the first `begin` gets its answer here.
      if let previewLayer, let viewfinderContinuation {
        viewfinderContinuation.yield(CameraViewfinder(layer: previewLayer))
      }

      // A runtime error is the camera going away under us — the hardware taken by another
      // process, or the session dying. An *interruption* is not: a phone call or a
      // multitasking split pauses the session and AVFoundation resumes it on its own, so
      // ending the stream there would turn a two-second pause into a dead viewfinder.
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(sessionFailed),
        name: .AVCaptureSessionRuntimeError,
        object: session
      )
      if !session.isRunning { session.startRunning() }
    }
  }

  /// Stops delivering and puts the camera back the way the next stream expects to find it.
  ///
  /// **The graph stays built**, which is the point of holding this — but everything the last
  /// viewer changed about the device does not, because the device now outlives them. A fresh
  /// `AVCaptureDevice` gave that for free; a kept one has to be told.
  func end() {
    queue.async { [self] in
      NotificationCenter.default.removeObserver(self)

      // The light goes out with the stream, always. A torch is the one thing here that
      // outlives the screen that lit it — `stopRunning` does not put it out on every device,
      // and a phone left glowing in a pocket is the worst bug this file could ship.
      isTorchWanted = false
      applyTorch()

      // And a viewfinder that reopened at 5× would look broken. The view model asks for this
      // too, on its way out; doing it here as well is what makes it true even if that call
      // and this one cross.
      applyZoom(1)

      // Stopped, not torn down: a running session is what lights the camera indicator, and
      // one lit behind a closed panel would say the app is still watching.
      if session.isRunning { session.stopRunning() }
      continuation = nil

      // The picture's viewer goes with the frames'. The layer itself stays — it is part of
      // the kept graph — and the next stream hands it out again.
      viewfinderContinuation?.finish()
      viewfinderContinuation = nil
    }
  }

  /// Registers the one viewer of the hardware-path picture, and answers it at once if the graph
  /// is already built. Called from ``PhoneCameraPreviewSource/viewfinderStream()``; the yield
  /// otherwise happens in ``begin(_:)``, whichever comes second.
  func attachViewfinder(_ continuation: AsyncStream<CameraViewfinder>.Continuation) {
    queue.async { [self] in
      viewfinderContinuation?.finish()
      viewfinderContinuation = continuation
      if let previewLayer {
        continuation.yield(CameraViewfinder(layer: previewLayer))
      }
    }
  }

  // MARK: The two controls
  //
  // Both run on `queue`, like everything else here — `lockForConfiguration` on a device
  // the delivery callback is reading from is precisely the race the confinement exists to stop.

  func setTorch(_ isOn: Bool) {
    queue.async { [self] in
      // The device stays open between streams now, so this is what keeps "light the torch"
      // from meaning anything while nobody is looking through the camera.
      guard continuation != nil else { return }
      isTorchWanted = isOn
      applyTorch()
    }
  }

  func setZoom(_ factor: Double) {
    queue.async { [self] in applyZoom(factor) }
  }

  private func applyZoom(_ factor: Double) {
    guard let device else { return }
    try? device.lockForConfiguration()
    // Clamped again here against *this* device: the source's range is what the UI pinches
    // within, and the front camera does not always reach as far as the back one.
    device.videoZoomFactor = min(max(factor, 1), device.activeFormat.videoMaxZoomFactor)
    device.unlockForConfiguration()
  }

  /// Puts the light where it is wanted, as far as this camera can. A device with no torch is not
  /// a failure — it is a camera that takes its pictures by available light.
  private func applyTorch() {
    guard let device, device.hasTorch, device.isTorchModeSupported(.on) else { return }
    try? device.lockForConfiguration()
    device.torchMode = isTorchWanted ? .on : .off
    device.unlockForConfiguration()
  }

  /// Builds the one-in, one-out graph, once. `false` means there is nothing to look through.
  private func configure() -> Bool {
    guard
      let device = Self.camera(),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return false }

    self.device = device

    session.beginConfiguration()
    defer { session.commitConfiguration() }

    // 720p, deliberately modest. It is a full-bleed viewfinder, so the temptation is to ask
    // for everything the sensor has — but every frame is converted into a `CGImage` and handed
    // to SwiftUI, and a 12 MP one of those thirty times a second is how a preview turns into a
    // slideshow. It is also the ceiling the glasses stream tops out at (`high` = 720 × 1280),
    // so both sources end up drawing at the same size, which is one less difference to explain
    // on stage.
    session.sessionPreset = .hd1280x720

    guard session.canAddInput(input) else { return false }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    // The viewfinder only ever wants the newest frame; a queue of them is just lag with a
    // memory cost.
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)

    guard session.canAddOutput(output) else { return false }
    session.addOutput(output)
    self.output = output

    orientOutput()

    // The picture. Created against the session while it is being configured, filled the way
    // the fallback `Image` crops, and turned upright the same way the frames are — the layer's
    // own connection needs telling too.
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    if let connection = layer.connection,
      connection.isVideoRotationAngleSupported(portraitRotationAngle)
    {
      connection.videoRotationAngle = portraitRotationAngle
    }
    previewLayer = layer

    isConfigured = true
    return true
  }

  /// The quarter turn every frame needs.
  private func orientOutput() {
    guard let connection = output?.connection(with: .video) else { return }
    if connection.isVideoRotationAngleSupported(portraitRotationAngle) {
      connection.videoRotationAngle = portraitRotationAngle
    }
  }

  /// The rear wide-angle camera. Wide rather than any available: an ultra-wide or a telephoto
  /// would start the viewfinder at a field of view the watcher did not ask for, and zoom is the
  /// control for that.
  private static func camera() -> AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }

  @objc private func sessionFailed() {
    queue.async { [self] in
      continuation?.finish(throwing: CameraPreviewError.interrupted)
      continuation = nil
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard shouldConvert() else { return }
    guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    // A frame that will not convert is one frame, not a broken stream — drop it and take the
    // next. Ending the stream here would turn a transient allocation failure into an error
    // screen.
    guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
    continuation?.yield(PreviewFrame(image: cgImage))
  }

  /// Whether this sample is worth converting — at most one per ``photographInterval``.
  ///
  /// These frames exist to keep the shutter's next photograph warm, and warming it thirty times
  /// a second is a river of copying for a picture taken maybe once a minute. The live view
  /// stopped needing them the day it moved onto the preview layer.
  private func shouldConvert() -> Bool {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastConverted >= photographInterval else { return false }
    lastConverted = now
    return true
  }
}

/// The rear camera's sensor sits a quarter turn from portrait, so every frame needs the same
/// quarter turn back. Named because `90` on its own, beside a rotation API that takes degrees
/// counterclockwise, is the kind of number that gets "fixed" to 270 by the next reader.
private let portraitRotationAngle: CGFloat = 90
