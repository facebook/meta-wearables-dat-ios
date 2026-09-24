/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  Route.swift
//  birdspotter
//

import SwiftUI

/// The three tabs of the shell.
///
/// Named so a feature that lands the user on a tab from outside the UI — a voice launch
/// opening the session, which lives behind Identify — can say which one in a word, instead
/// of the shell's selection being an anonymous index nothing else can address.
enum Tab: Hashable {
  case explore
  case identify
  case journal
}

/// Every address in the app that can be pushed onto a tab's stack.
///
/// Keeping the two lists otherwise identical is what lets a feature that navigates from outside the
/// UI — "Hey Meta, what bird is that?" landing the user in Identify — be the same one-line call on
/// both platforms rather than two different mechanisms.
enum Route: Hashable {
  /// One species' page in the field guide.
  ///
  /// `speciesId` is the catalog slug (`northern-cardinal`), which is a stable id by
  /// contract — see ``Species`` — so an address stays good across a seed bump.
  case birdDetail(speciesId: String)

  /// One journal entry's page — an outing and everything it confirmed — pushed from a
  /// Journal row. The same surface the live flow's post-stop review will land on.
  ///
  /// `outingId` is the root row's UUID in `journal.db`. Only the Journal opens this, but the
  /// single `destination` switch registers it for every tab's stack all the same — harmless,
  /// and simpler than a per-tab exception.
  case outingDetail(outingId: String)

  /// The step-by-step identification wizard, pushed from Identify.
  ///
  /// One route for the whole five-question flow: the stations share their answers and
  /// the back chevron walks them, which is a screen's internal state, not five
  /// addresses.
  case identifyWizard

  case settings

  /// Settings → Meta AI Glasses: where the link stands — registration, the device, camera
  /// access — and the way back out of it. Offered only once registration has happened;
  /// before that, Settings shows the set-up card instead.
  case glassesSettings

  /// Settings → Meta AI Glasses → Test ASR: a session opened to find out whether this pair
  /// transcribes, and what it hears when it does.
  case speechTest

  /// Settings → Meta AI Glasses → Camera: one photograph at chosen settings, and what the
  /// crossing cost.
  case glassesCamera

  /// Settings → Meta AI Glasses → Display Screen: any bird's card put on the glasses' panel
  /// by hand, and held there.
  case glassesDisplay

  /// Settings → Diagnostics: how the app's own event log is set, and the runs it has
  /// recorded.
  case diagnostics

  /// One recorded run's page: its lines, filtered by category and level. `name` is the
  /// log file's own name, which carries the run's start time — see ``DiagnosticsLogStore``.
  case diagnosticsFile(name: String)

  /// Settings → Demo Director: the preset picker that scripts what the app "identifies".
  case demoDirector

  /// One preset's page — its three sections as cards, and the duplicate/rename/delete
  /// actions. `presetId` is the preset's stored id; the shipped one's ships in its JSON.
  case demoDirectorPreset(presetId: String)

  /// One STT-input row's editor. A nil `questionId` opens a new row rather than an
  /// existing one — the same address adds and amends, because the editor hands back a
  /// whole row either way and the save is an upsert.
  case demoDirectorQuestion(presetId: String, questionId: String?)

  /// One photo row's editor. A nil `photoId` adds. There is no address for what happens
  /// past the end of the list: that is fixed, not authored.
  case demoDirectorPhoto(presetId: String, photoId: String?)

  /// One ambient-input row's editor. A nil `callId` adds.
  case demoDirectorAmbient(presetId: String, callId: String?)
}

extension Route {
  /// The one place an address becomes a screen.
  ///
  /// Every tab's stack registers this same switch, which is why a screen reachable from
  /// three tabs is still written once.
  @ViewBuilder
  func destination(container: AppContainer) -> some View {
    switch self {
    case .birdDetail(let speciesId):
      BirdDetailScreen(speciesId: speciesId, birdCatalog: container.birdCatalogRepository)
    case .outingDetail(let outingId):
      OutingDetailScreen(
        outingId: outingId,
        journal: container.journalRepository,
        birdCatalog: container.birdCatalogRepository,
        mediaFileStore: container.mediaFileStore,
        mapLauncher: container.mapLauncher
      )
    case .identifyWizard:
      IdentifyWizardScreen(
        birdCatalog: container.birdCatalogRepository,
        journal: container.journalRepository,
        locationProvider: container.locationProvider
      )
    case .settings:
      SettingsScreen(
        glassesSession: container.glassesSessionRepository,
        journal: container.journalRepository,
        mockDevice: container.mockDeviceRepository
      )
    case .glassesSettings:
      GlassesSettingsScreen(glassesSession: container.glassesSessionRepository)
    case .speechTest:
      SpeechTestScreen(
        glassesSession: container.glassesSessionRepository,
        glassesSpeech: container.glassesSpeechRepository
      )
    case .glassesCamera:
      GlassesCameraScreen(
        glassesSession: container.glassesSessionRepository,
        glassesCamera: container.glassesCameraRepository,
        scratch: container.captureScratchStore
      )
    case .glassesDisplay:
      GlassesDisplayScreen(
        glassesSession: container.glassesSessionRepository,
        glassesDisplay: container.glassesDisplayRepository,
        birdCatalog: container.birdCatalogRepository
      )
    case .diagnostics:
      DiagnosticsScreen(
        store: container.diagnosticsLogStore,
        settings: container.diagnosticsSettings,
        reinstall: { container.installDiagnostics() }
      )
    case .diagnosticsFile(let name):
      DiagnosticsFileScreen(store: container.diagnosticsLogStore, fileName: name)
    case .demoDirector:
      DemoDirectorScreen(store: container.demoSettingsStore)
    case .demoDirectorPreset(let presetId):
      DemoDirectorPresetScreen(presetId: presetId, store: container.demoSettingsStore)
    case .demoDirectorQuestion(let presetId, let questionId):
      DemoQuestionEditorScreen(
        presetId: presetId,
        questionId: questionId,
        store: container.demoSettingsStore,
        birdCatalog: container.birdCatalogRepository
      )
    case .demoDirectorPhoto(let presetId, let photoId):
      DemoPhotoEditorScreen(
        presetId: presetId,
        photoId: photoId,
        store: container.demoSettingsStore,
        birdCatalog: container.birdCatalogRepository
      )
    case .demoDirectorAmbient(let presetId, let callId):
      DemoAmbientEditorScreen(
        presetId: presetId,
        callId: callId,
        store: container.demoSettingsStore,
        birdCatalog: container.birdCatalogRepository
      )
    }
  }
}
