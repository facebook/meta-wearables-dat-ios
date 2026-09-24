/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesCameraViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The camera screen's three pieces of policy: **when the shutter may be pressed**, **what a
/// photograph is called on disk**, and **which of the two partings one failure gets.**
///
/// The crossing itself is the SDK's and is not under test here — what is, is the seam this
/// screen adds around it: a press that cannot succeed is not offered, a file lands under a
/// name that still means something an hour later, and a dropped photograph does not send
/// somebody off to fix a connection that is fine.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("GlassesCameraViewModel")
struct GlassesCameraViewModelTests {

  @Test func theShutterIsOfferedOnlyOnceTheSessionHasStarted() {
    // Connecting is not connected: the capability refuses a capture it has not started,
    // and the refusal comes back so fast it reads on the log as an empty photograph.
    for state in [GlassesSessionState.starting, .paused, .stopping, .stopped] {
      let uiState = GlassesCameraUiState(isRunning: true, sessionState: state)
      #expect(!uiState.canCapture)
    }

    let started = GlassesCameraUiState(isRunning: true, sessionState: .started)
    #expect(started.canCapture)
  }

  @Test func theShutterIsNotOfferedWhileAPhotographIsStillCrossing() {
    // One at a time. A queue of captures is a queue of photographs nobody asked for by
    // the time they land.
    let crossing = GlassesCameraUiState(
      isRunning: true,
      sessionState: .started,
      isCapturing: true
    )

    #expect(!crossing.canCapture)
  }

  @Test func aDeniedGrantStillLetsTheShutterBePressed() {
    // The grant is read off a live link and can be answered in another app between one
    // press and the next. Refusing on a stale reading leaves a dead button; the row
    // above says what is wrong and the press is allowed to fail honestly.
    let denied = GlassesCameraUiState(
      isRunning: true,
      sessionState: .started,
      cameraAccess: .denied
    )

    #expect(denied.canCapture)
  }

  @Test func aPhotographIsNamedForTheSettingsItWasTakenAt() {
    // The name is what the share sheet shows and what lands in the camera roll. Three
    // shots called photo-1, photo-2, photo-3 are three shots nobody can tell apart.
    #expect(
      GlassesCameraViewModel.fileName(for: .large, quality: .high, index: 3)
        == "glasses-large-high-3.jpg"
    )
    #expect(
      GlassesCameraViewModel.fileName(for: .small, quality: .low, index: 1)
        == "glasses-small-low-1.jpg"
    )
  }

  @Test func aPhotographIsNamedWithAnImageExtension() {
    // The extension is the whole reason the file has a name: it is what puts **Save
    // Image** in the share sheet rather than a list of places to file a document.
    let name = GlassesCameraViewModel.fileName(for: .full, quality: .medium, index: 12)

    #expect(name.hasSuffix(".jpg"))
  }

  @Test func aDroppedCrossingDoesNotBlameTheConnection() {
    // The link is usually still up and the next press usually works. Telling somebody to
    // check their glasses over one dropped photograph sends them to fix nothing.
    let parting = GlassesCameraViewModel.captureParting(for: GlassesError.transferFailed)

    #expect(parting.contains("Try again"))
    #expect(!parting.contains("connected"))
  }

  @Test func aShutterWithNoCameraUpSaysSo() {
    // The other of the two the app can tell apart: nothing to photograph through yet.
    let parting = GlassesCameraViewModel.captureParting(for: GlassesError.notConnected)

    #expect(parting.contains("not up"))
  }

  @Test func aSessionThatEndedOnAStaleFirmwarePointsAtTheMetaAiApp() {
    // The failure that lies: a pair in this state reports battery, wear and heat over the
    // link the whole time, so "check they are connected" is the one answer that helps
    // least.
    let parting = GlassesCameraViewModel.parting(for: GlassesError.glassesUpdateRequired)

    #expect(parting.contains("firmware"))
  }
}
