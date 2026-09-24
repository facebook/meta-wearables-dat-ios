/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoDirectorViewModel.swift
//  birdspotter
//

import Foundation

/// Each ambient row's position on the session clock, in ms — the running total the editor
/// prints beside the authored gap (`+15s · 0:23`), so rehearsing against a stopwatch needs
/// no arithmetic. Row gaps stay the stored truth; these are derived, never written back.
nonisolated func ambientRunningTotals(_ calls: [DemoAmbientCall]) -> [Int] {
  var total = 0
  return calls.map { call in
    total += call.afterMillis
    return total
  }
}

/// What the Demo Director settings screens render: every preset, which one is armed, and
/// whether the shipped script is still among them.
///
/// A snapshot of the store, re-read after every mutation rather than observed: preferences
/// only change through these screens, and a live stream over two prefs keys would be
/// machinery without a reader.
nonisolated struct DemoDirectorUiState: Equatable {
  var presets: [DemoPreset] = []
  /// The armed preset's id, or nil for the deliberate "none" state.
  var armedId: String?
  /// Whether "Reset to starter" should be offered — true once no stored preset matches
  /// the shipped one, because it was edited or deleted. See
  /// ``DemoSettingsStore/isShippedPresent``.
  var canResetToShipped: Bool = false

  func preset(_ id: String) -> DemoPreset? { presets.first { $0.id == id } }

  /// What the dropdown reads when nothing is armed.
  var armedName: String { armedId.flatMap { preset($0)?.name } ?? "None" }
}

/// The Demo Director settings screens' state holder — the picker, a preset's page and the
/// row editors all share it, each over its own instance.
///
/// Every action writes through ``DemoSettingsStore`` and re-reads, so what the screens show
/// is exactly what the next session will play. Row edits are **upserts by id**: an editor
/// hands back a whole row, and a row whose id is not in the list yet is an addition.
@MainActor
@Observable
final class DemoDirectorViewModel {

  private(set) var uiState = DemoDirectorUiState()

  private let store: DemoSettingsStore

  init(store: DemoSettingsStore) {
    self.store = store
    refresh()
  }

  // MARK: - The preset list

  /// The dropdown's selection: arm `id`, or nil for none.
  func arm(_ id: String?) {
    store.armPreset(id: id)
    refresh()
  }

  /// The panic button, offered only while ``DemoDirectorUiState/canResetToShipped``.
  func resetToShipped() {
    store.resetToShipped()
    refresh()
  }

  /// A copy of `id` under a fresh identity, appended to the list. Returns the new
  /// preset's id so the caller can navigate straight to it, or nil when there is nothing
  /// to copy.
  ///
  /// The copy's rows are re-identified too: ids are unique per row, and two presets
  /// sharing one would make an edit to either land on both.
  @discardableResult
  func duplicate(_ id: String) -> String? {
    guard var copy = uiState.preset(id) else { return nil }
    copy.id = UUID().uuidString
    copy.name = "\(copy.name) copy"
    copy.questions = copy.questions.map {
      var row = $0
      row.id = Self.newId()
      return row
    }
    copy.photoResponses = copy.photoResponses.map {
      var row = $0
      row.id = Self.newId()
      return row
    }
    copy.ambientCalls = copy.ambientCalls.map {
      var row = $0
      row.id = Self.newId()
      return row
    }
    store.savePresets(store.presets() + [copy])
    refresh()
    return copy.id
  }

  /// A preset with nothing scripted — the honest starting point for authoring one.
  @discardableResult
  func newPreset() -> String {
    let created = DemoPreset(
      id: UUID().uuidString,
      name: "New preset",
      unmatchedQuestion: "Sorry — didn't catch that."
    )
    store.savePresets(store.presets() + [created])
    refresh()
    return created.id
  }

  func rename(_ id: String, to name: String) {
    update(id) { $0.name = name }
  }

  /// Remove a preset. Deleting the armed one disarms — nothing is quietly re-armed.
  func delete(_ id: String) {
    if store.armedPreset()?.id == id { store.armPreset(id: nil) }
    store.savePresets(store.presets().filter { $0.id != id })
    refresh()
  }

  // MARK: - Rows

  func saveQuestion(_ presetId: String, _ question: DemoQuestion) {
    update(presetId) { $0.questions = upsert($0.questions, question) }
  }

  func deleteQuestion(_ presetId: String, _ questionId: String) {
    update(presetId) { $0.questions.removeAll { $0.id == questionId } }
  }

  func savePhotoResponse(_ presetId: String, _ response: DemoPhotoResponse) {
    update(presetId) { $0.photoResponses = upsert($0.photoResponses, response) }
  }

  func deletePhotoResponse(_ presetId: String, _ responseId: String) {
    update(presetId) { $0.photoResponses.removeAll { $0.id == responseId } }
  }

  func saveAmbientCall(_ presetId: String, _ call: DemoAmbientCall) {
    update(presetId) { $0.ambientCalls = upsert($0.ambientCalls, call) }
  }

  func deleteAmbientCall(_ presetId: String, _ callId: String) {
    update(presetId) { $0.ambientCalls.removeAll { $0.id == callId } }
  }

  /// Re-read the store. Public because the screens hold separate instances over the same
  /// preferences — returning to the picker after an edit deeper in must not show the
  /// snapshot from before it.
  func refresh() {
    uiState = DemoDirectorUiState(
      presets: store.presets(),
      armedId: store.armedPreset()?.id,
      canResetToShipped: store.shipped != nil && !store.isShippedPresent
    )
  }

  private func update(_ presetId: String, _ transform: (inout DemoPreset) -> Void) {
    store.savePresets(
      store.presets().map { preset in
        guard preset.id == presetId else { return preset }
        var edited = preset
        transform(&edited)
        return edited
      })
    refresh()
  }

  /// A fresh row id. Rows are addressed by id, so every new one needs its own.
  static func newId() -> String { UUID().uuidString }
}

/// Replace the element sharing `item`'s id, or append it when none does — what "save a row"
/// means when the editor cannot know whether it is adding or amending.
private func upsert<T: Identifiable>(_ list: [T], _ item: T) -> [T] where T.ID == String {
  list.contains { $0.id == item.id }
    ? list.map { $0.id == item.id ? item : $0 }
    : list + [item]
}
