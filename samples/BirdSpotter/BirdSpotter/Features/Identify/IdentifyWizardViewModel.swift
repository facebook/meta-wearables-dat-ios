/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IdentifyWizardViewModel.swift
//  birdspotter
//

import Foundation

/// The wizard's stations, in walking order. The first three are questions ("1 of 3");
/// `results` is the list they narrow to.
nonisolated enum IdentifyWizardStep: Int, CaseIterable, Sendable {
  case size, colors, behavior, results

  /// 1-based position for the "2 of 3" header. Meaningless for `results`.
  var questionNumber: Int { rawValue + 1 }
}

/// Why a save did not happen, for the one message the Results station can show.
///
/// `noLocationFix` is its own case rather than folded into `writeFailed` because the two ask
/// different things of the user: a failed write is worth simply tapping again, while a missing fix
/// is worth stepping outside first. Both leave the button live.
nonisolated enum IdentifyWizardSaveError: Equatable, Sendable {
  case noLocationFix
  case writeFailed
}

/// Everything the wizard screen renders — one value, because the four stations share the
/// answers and the answers outlive the station that asked for them (going back must not
/// forget what was picked).
///
/// `spottedOn` and `coordinate` are *stamped*, not asked: the flow takes *when* (today) and
/// *where* (the phone's fix) on its own, so the only questions left are about the bird. Only
/// `sizeClass`, `colors`, and `behavior` filter the catalog — see ``IdentifyQuery``.
/// `candidates` is nil while the results query runs, then the answer, possibly empty.
struct IdentifyWizardUiState {
  var step: IdentifyWizardStep = .size
  var spottedOn: Date
  /// The phone's fix, stamped onto the outing. Nil only until ``captureLocation()`` returns;
  /// a save that arrives before it does asks again rather than proceeding without one.
  var coordinate: Coordinate?
  var sizeClass: Int?
  var colors: Set<PlumageColor> = []
  var behavior: BirdBehavior?
  var candidates: [SpeciesWithMedia]?
  /// Species id of a save in flight — at most one, ever.
  var savingSpeciesId: String?
  /// Species id the user confirmed. One per wizard run; set once, never cleared.
  var savedSpeciesId: String?
  /// Why the last save did not happen. Cleared the moment another is attempted.
  var saveError: IdentifyWizardSaveError?

  /// Whether the pinned Next button is live. Each question earns it once answered; Results has
  /// nowhere to advance to.
  var canAdvance: Bool {
    switch step {
    case .size: sizeClass != nil
    case .colors: !colors.isEmpty
    case .behavior: behavior != nil
    case .results: false
    }
  }
}

/// The step-by-step identify flow: three answers in, a shortlist out, and — when the user
/// taps "This is my bird" — one `manual` outing written in one breath: the outing, its three
/// `wizardAnswer` events (the provenance the journal shows for the ID), and the one confirmed
/// sighting.
///
/// *When* and *where* are taken automatically: `spottedOn` is today, and a one-shot
/// ``LocationProvider`` fix stamps the outing's coordinates. The place and date questions the
/// flow used to ask are gone — the Identify tab gates entry on the location permission instead,
/// so by the time the wizard runs a fix is expected. Expected, not guaranteed: the permission is
/// not a fix, so a save with none in hand asks once more and then declines, because ``Outing``'s
/// coordinates are required.
///
/// `today` and `now` are injected so tests can pin the clock, same seam as everywhere else.
@MainActor
@Observable
final class IdentifyWizardViewModel {

  private(set) var uiState: IdentifyWizardUiState

  private let birdCatalog: any BirdCatalogRepository
  private let journal: any JournalRepository
  private let locationProvider: any LocationProvider
  private let now: @Sendable () -> Int64

  /// The color step's cap — naming more than three "main colors" stops being true.
  static let maxColors = 3

  init(
    birdCatalog: any BirdCatalogRepository,
    journal: any JournalRepository,
    locationProvider: any LocationProvider,
    today: @Sendable () -> Date = Date.init,
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.birdCatalog = birdCatalog
    self.journal = journal
    self.locationProvider = locationProvider
    self.now = now
    uiState = IdentifyWizardUiState(spottedOn: today())
  }

  /// Grabs the phone's position once, in the background, and stamps it onto the in-flight
  /// answers. The screen calls this when the wizard appears, so the fix is normally waiting
  /// long before the user reaches Results. Idempotent enough — a later fix replaces an
  /// earlier one, and ``saveSighting(_:)`` asks again itself if none ever landed.
  func captureLocation() async {
    uiState.coordinate = await locationProvider.currentCoordinate()
  }

  func chooseSizeClass(_ sizeClass: Int) {
    precondition((1...7).contains(sizeClass), "sizeClass is 1-7 on the sparrow-to-goose scale")
    uiState.sizeClass = sizeClass
  }

  /// Toggles a swatch. A fourth color is ignored, not queued — same as the reference app.
  func toggleColor(_ color: PlumageColor) {
    if uiState.colors.contains(color) {
      uiState.colors.remove(color)
    } else if uiState.colors.count < Self.maxColors {
      uiState.colors.insert(color)
    }
  }

  func chooseBehavior(_ behavior: BirdBehavior) {
    uiState.behavior = behavior
  }

  func advance() {
    guard uiState.canAdvance,
      let next = IdentifyWizardStep(rawValue: uiState.step.rawValue + 1)
    else { return }
    // Candidates reset on every entry: coming back and changing an answer must never show
    // the previous answer's list, even for the moment the query takes.
    uiState.step = next
    uiState.candidates = nil
    if next == .results {
      Task { await loadCandidates() }
    }
  }

  /// One station back. False at the first station — that back press belongs to navigation, and
  /// the caller pops the wizard itself.
  func goBack() -> Bool {
    guard uiState.step != .size,
      let previous = IdentifyWizardStep(rawValue: uiState.step.rawValue - 1)
    else {
      return false
    }
    uiState.step = previous
    return true
  }

  private func loadCandidates() async {
    guard let sizeClass = uiState.sizeClass, let behavior = uiState.behavior else { return }
    let query = IdentifyQuery(sizeClass: sizeClass, colors: uiState.colors, behavior: behavior)
    do {
      let found = try await birdCatalog.identifyCandidates(query)
      // Stale-guard: only publish onto the results station. Backing out mid-query and
      // re-advancing restarts the load against the edited answers.
      if uiState.step == .results {
        uiState.candidates = found
      }
    } catch is CancellationError {
      // leave state as-is
    } catch {
      if uiState.step == .results {
        uiState.candidates = []
      }
    }
  }

  /// "This is my bird": the wizard's answers, which have been sitting in ``uiState`` since
  /// the user gave them, assembled into one `manual` ``OutingDraft`` and written in a single
  /// call. No capture, so no media, no confidence, no timeline offsets; the location is the
  /// phone's own fix rather than a glasses one.
  ///
  /// The answers are stored as `wizardAnswer` events in the catalog enums' own spellings —
  /// colors sorted so the stored string is deterministic on both platforms, where the
  /// selection order of a set is not.
  func saveSighting(_ speciesId: String) {
    guard uiState.savingSpeciesId == nil, uiState.savedSpeciesId == nil else { return }
    // Results is unreachable without all three answers; bail rather than store a partial set.
    guard let sizeClass = uiState.sizeClass, let behavior = uiState.behavior else { return }
    let colors = uiState.colors.map(\.rawValue).sorted().joined(separator: ",")
    uiState.savingSpeciesId = speciesId
    uiState.saveError = nil
    Task {
      do {
        // An outing has to know where it happened. The tab is gated on the location
        // permission, so by here a fix is normally already in hand; when the ask is
        // still in flight — or when it came back empty on a phone that has the
        // permission but no signal — ask once more and then decline rather than
        // logging a bird nowhere. Declining lands in the same state a failed write
        // does: the button stays live.
        var fix = uiState.coordinate
        if fix == nil { fix = await locationProvider.currentCoordinate() }
        guard let coordinate = fix else { throw JournalError.noLocationFix }
        _ = try await journal.saveOuting(
          OutingDraft(
            kind: .manual,
            startedAt: now(),
            location: CaptureLocation(
              latitude: coordinate.latitude,
              longitude: coordinate.longitude
            ),
            events: [
              PendingEvent.wizardAnswer(trait: .size, value: String(sizeClass)),
              PendingEvent.wizardAnswer(trait: .colors, value: colors),
              PendingEvent.wizardAnswer(trait: .behavior, value: behavior.rawValue),
            ],
            sightings: [PendingSighting(speciesId: speciesId)]
          )
        )
        uiState.savingSpeciesId = nil
        uiState.savedSpeciesId = speciesId
      } catch {
        // A failure leaves the button live to try again *and says so*. Clearing the
        // spinner alone was the bug: the tap looked like it did nothing, which reads as
        // a broken app rather than as a phone that could not place itself. The write is
        // one transaction, so the Journal is exactly as it was either way.
        uiState.savingSpeciesId = nil
        uiState.saveError =
          (error as? JournalError) == .noLocationFix
          ? .noLocationFix
          : .writeFailed
      }
    }
  }
}
