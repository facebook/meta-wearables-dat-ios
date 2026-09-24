/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesDisplayViewModel.swift
//  birdspotter
//

import Foundation

/// What the display screen shows.
nonisolated struct GlassesDisplayUiState: Equatable, Sendable {
  /// Whether a session has been asked for and not yet hung up on.
  var isRunning: Bool = false

  /// Where the session is — `nil` before the first reading.
  var sessionState: GlassesSessionState?

  /// Whether this pair has a panel at all — `nil` until a pair is listed.
  var hasDisplay: Bool?

  /// What is in the search field.
  var query: String = ""

  /// The pickable guide: everything on a blank query, the matches otherwise.
  var birds: [SpeciesWithMedia] = []

  /// The bird whose card is up on the glasses, or `nil` when none is.
  var shownBird: SpeciesWithMedia?

  /// The custom card's chosen bird, or `nil` when none has been chosen.
  var customBird: SpeciesWithMedia?

  /// The custom card's line — what will stand in for the catalog's description when the
  /// custom card is sent.
  var customMessage: String = ""

  /// Why the run ended, when it ended badly.
  var failure: String?
}

/// A session opened for one purpose: to put any bird's card on the glasses' panel, by hand.
///
/// **A demo control, not a feature.** The live flow already sends a card the moment a bird is
/// identified; what it cannot do is put a *chosen* bird up on cue, hold it there, and take it
/// down again — which is exactly what showing the display to somebody calls for. So this
/// screen opens a session the ordinary way, waits for nothing, and sends whatever row is
/// tapped. The card stays up until another row replaces it, **Clear screen** takes it down,
/// or the screen is left — leaving is a clear, because a card nobody is presenting is a card
/// nobody asked for.
///
/// The session comes up through ``GlassesSessionRepository/displaySessionStream()`` the
/// moment the screen opens: the whole point of being here is to send, and a screen that made
/// somebody press Connect first would just be adding a step to every rehearsal. The
/// display-only lease, deliberately — this screen draws and does nothing else, so no camera
/// is lit and no recogniser started on its behalf.
@MainActor
@Observable
final class GlassesDisplayViewModel {

  private let glassesSession: any GlassesSessionRepository
  private let glassesDisplay: any GlassesDisplayRepository
  private let birdCatalog: any BirdCatalogRepository
  private let settings: DisplaySettingsStore

  private(set) var uiState = GlassesDisplayUiState()

  /// The whole guide, kept beside the state for re-filtering — the same reason Explore
  /// keeps its own unfiltered copy.
  private var guide: [SpeciesGroup] = []

  /// The run: the session's lease, and the device watcher that lives inside it.
  private var run: Task<Void, Never>?

  /// The send in flight. The next tap cancels it rather than queueing behind it, so cards
  /// land in tap order and a slow photo load can never put an older bird over a newer one.
  private var send: Task<Void, Never>?

  init(
    glassesSession: any GlassesSessionRepository,
    glassesDisplay: any GlassesDisplayRepository,
    birdCatalog: any BirdCatalogRepository,
    settings: DisplaySettingsStore
  ) {
    self.glassesSession = glassesSession
    self.glassesDisplay = glassesDisplay
    self.birdCatalog = birdCatalog
    self.settings = settings
    uiState.customMessage = settings.customMessage
  }

  /// The guide and the stored custom setup, loaded once the screen is up.
  func load() async {
    guide = (try? await birdCatalog.browseGroups()) ?? []
    uiState.birds = Self.birdsFor(uiState.query, in: guide)
    // The stored bird resolves against the same load; a slug the catalog no longer
    // carries reads as unchosen rather than as an error to explain.
    if let storedId = settings.customBirdId {
      uiState.customBird = try? await birdCatalog.findById(storedId)
    }
  }

  /// Opens the session. Idempotent — called when the screen arrives, and again only by
  /// the retry offered after a failure.
  func start() {
    guard run == nil else { return }
    uiState.isRunning = true
    uiState.failure = nil
    run = Task { [weak self] in
      await self?.hold()
      self?.run = nil
    }
  }

  /// Hangs up. Leaving is a clear — see ``hold()``'s way down.
  func stop() {
    run?.cancel()
    run = nil
    send?.cancel()
    uiState.isRunning = false
  }

  /// Runs a query against the guide, or restores the whole of it when blank.
  func search(_ query: String) {
    uiState.query = query
    uiState.birds = Self.birdsFor(query, in: guide)
  }

  /// Sends the bird's card up. Replaces whatever the panel was showing.
  func show(_ bird: SpeciesWithMedia) {
    send?.cancel()
    send = Task { [glassesDisplay] in
      await glassesDisplay.showGallery(for: bird)
      guard !Task.isCancelled else { return }
      uiState.shownBird = bird
    }
  }

  /// Takes the card down and says so.
  func clearScreen() {
    send?.cancel()
    send = Task { [glassesDisplay] in
      await glassesDisplay.clear()
      guard !Task.isCancelled else { return }
      uiState.shownBird = nil
    }
  }

  /// The custom card's bird. Remembered, so the setup survives the app being restarted.
  func pickCustomBird(_ bird: SpeciesWithMedia) {
    settings.customBirdId = bird.species.id
    uiState.customBird = bird
  }

  /// The custom card's line, saved as it is typed — see ``DisplaySettingsStore`` for why.
  func editCustomMessage(_ message: String) {
    settings.customMessage = message
    uiState.customMessage = message
  }

  /// Sends the custom card up: the chosen bird's gallery, with the presenter's line in
  /// place of the catalog's description. Replaces whatever the panel was showing, exactly
  /// as a row tap does.
  func showCustom() {
    guard let bird = uiState.customBird,
      Self.customCardReady(bird: bird, message: uiState.customMessage)
    else { return }
    let message = uiState.customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    send?.cancel()
    send = Task { [glassesDisplay] in
      await glassesDisplay.showGallery(for: bird, message: message)
      guard !Task.isCancelled else { return }
      uiState.shownBird = bird
    }
  }

  /// The run itself: the session held open, and the device snapshot read for as long as it
  /// is — the snapshot is where ``GlassesDisplayUiState/hasDisplay`` comes from, and it is
  /// the one reading that decides whether a tap here means anything.
  private func hold() async {
    defer {
      // The card must not outlive the screen: whatever ends the run — a failure, the
      // session's own end, or the screen being left — the panel is wiped on the way
      // down. Unstructured, because the usual way out *is* cancellation, and a clear
      // that dies with its task clears nothing.
      Task { [glassesDisplay] in await glassesDisplay.clear() }
    }
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        // The watcher outlives nothing: the device stream never completes on its
        // own, so it is cancelled by hand once the session's stream has ended.
        group.addTask { [glassesSession] in
          for await device in glassesSession.deviceInfoStream() {
            await MainActor.run { self.uiState.hasDisplay = device?.hasDisplay }
          }
        }
        for try await state in glassesSession.displaySessionStream() {
          uiState.sessionState = state
        }
        group.cancelAll()
      }
      // A session that ends of its own accord — a doff, a fold, a long press — takes
      // the card with it, so the screen must stop claiming one is up.
      uiState.isRunning = false
      uiState.shownBird = nil
    } catch is CancellationError {
      return
    } catch {
      BirdLog.error(.glasses, "display screen — the session ended in failure", error)
      uiState.isRunning = false
      uiState.shownBird = nil
      uiState.failure = Self.parting(for: error)
    }
  }

  /// Why the run ended, in a line. The same two answers the realtime screen gives, because
  /// they are the only two the app can tell apart — the log line beside this one carries
  /// the rest.
  private static func parting(for error: Error) -> String {
    if case GlassesError.glassesUpdateRequired = error {
      return "Your glasses need a firmware update — check them in the Meta AI app"
    }
    return "The glasses session ended — check they are connected and try again"
  }

  /// The pickable list for a query: the whole guide flattened when it is blank, the
  /// matches otherwise — through ``ExploreViewModel/speciesMatching(_:in:)``, deliberately,
  /// so "search" means the same thing on this screen as it does on Explore and the
  /// locale-fold reasoning documented there is written once.
  nonisolated static func birdsFor(
    _ query: String,
    in groups: [SpeciesGroup]
  ) -> [SpeciesWithMedia] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return groups.flatMap(\.species) }
    return ExploreViewModel.speciesMatching(trimmed, in: groups)
  }

  /// Whether the custom card can be sent: a bird chosen, and a message with ink in it.
  /// A whitespace message is no message — a card whose last line is blank would read as
  /// the send having dropped the description.
  nonisolated static func customCardReady(bird: SpeciesWithMedia?, message: String) -> Bool {
    bird != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
