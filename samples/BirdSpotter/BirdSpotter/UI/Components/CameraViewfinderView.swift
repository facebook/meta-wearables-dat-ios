/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CameraViewfinderView.swift
//  birdspotter
//

import AVFoundation
import SwiftUI
import UIKit

/// Puts a ``CameraViewfinder``'s layer into the SwiftUI tree. Hosting plumbing, not part of the
/// mirrored surface — where a camera library ships its own host view, this file is what stands
/// in for it.
///
/// A representable rather than anything cleverer, because a `CALayer` needs a `UIView` to live
/// in and that is the whole job: attach the layer, keep its frame matched to the view's bounds,
/// and stay out of the way. The layer draws the camera on the hardware path; nothing here ever
/// sees a frame.
struct CameraViewfinderView: UIViewRepresentable {

  let viewfinder: CameraViewfinder

  func makeUIView(context: Context) -> ViewfinderHostView {
    ViewfinderHostView()
  }

  func updateUIView(_ view: ViewfinderHostView, context: Context) {
    view.attach(viewfinder.layer)
  }
}

/// The one `UIView` in the app, and it exists to own a layer.
final class ViewfinderHostView: UIView {

  private var attached: AVCaptureVideoPreviewLayer?

  /// Adopts [preview], releasing whatever was here before. Idempotent per layer, because
  /// `updateUIView` runs on every SwiftUI update and re-adding a sublayer restarts its
  /// implicit animations.
  func attach(_ preview: AVCaptureVideoPreviewLayer) {
    guard preview !== attached else { return }
    attached?.removeFromSuperlayer()
    attached = preview
    layer.addSublayer(preview)
    preview.frame = bounds
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Without the transaction, the layer eases towards every new size — and the panel's morph
    // resizes this view every frame, which would put the picture on a second, slower clock
    // than the card it sits in.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    attached?.frame = bounds
    CATransaction.commit()
  }
}
