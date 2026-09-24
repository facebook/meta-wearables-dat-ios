/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DemoSettingsStore.swift
//  birdspotter
//

import Foundation

/// The Demo Director's saved state: the presets the operator has, and which one — if any —
/// is armed.
///
/// UserDefaults, not a database table: a preset is operator configuration the way the
/// database design's "deliberately absent" list says (`journal.db` stores what the user
/// *made*, `catalog.db` is a read-only seed, and a demo preset is neither). Losing one
/// costs a few taps, which is exactly the durability preferences promise.
///
/// **The shipped preset is a template, not a fixture.** ``shipped`` is decoded from the
/// bundled `SeedData/presets/full-flow.json` and is never itself the thing that plays; on
/// first run it is *copied* into the stored list, where it becomes an ordinary preset the
/// operator can rename, edit and delete like any other. That copy is what the Director
/// reads.
///
/// The cost of seeding — improving the shipped file no longer reaches a device that has
/// already run the app — is paid for by ``resetToShipped()``: ``isShippedPresent`` goes
/// false the moment the stored copy is edited or deleted, which is what surfaces the
/// button that puts the pristine version back.
///
/// Arming is explicit from the first launch: seeding arms the copy, and an empty stored id
/// means the deliberate "none" state in which the app never identifies.
nonisolated struct DemoSettingsStore: @unchecked Sendable {
  // @unchecked: UserDefaults is documented thread-safe, and the decoded template is
  // immutable — there is nothing here a data race can reach.

  private static let presetsKey = "demo.presets"
  private static let armedKey = "demo.armedPresetId"

  private let defaults: UserDefaults

  /// The bundled template, or nil when the shipped file is missing or unreadable.
  let shipped: DemoPreset?

  init(defaults: UserDefaults, shipped: DemoPreset?) {
    self.defaults = defaults
    self.shipped = shipped
    seedIfNeeded()
  }

  /// Opens the store over the app's preferences, decoding the shipped template as it
  /// goes. A template that will not decode is a staging bug the parity tests exist to
  /// catch before it ships; at runtime it degrades to "nothing to seed" with a log line,
  /// the same shape the catalog takes when `catalog.db` is missing.
  static func open(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> DemoSettingsStore {
    let shipped =
      bundle
      .url(forResource: "full-flow", withExtension: "json", subdirectory: "SeedData/presets")
      .flatMap { url -> DemoPreset? in
        do {
          return try DemoPreset.decode(try Data(contentsOf: url))
        } catch {
          BirdLog.error(.demo, "could not load the shipped preset", error)
          return nil
        }
      }
    if shipped == nil {
      BirdLog.error(.demo, "no shipped preset in the bundle")
    }
    return DemoSettingsStore(defaults: defaults, shipped: shipped)
  }

  /// Every preset the operator has, in saved order.
  ///
  /// Empty is a legal answer — deleting the last one is allowed, and nothing re-seeds
  /// behind the operator's back. Only a *never seeded* store fills itself.
  func presets() -> [DemoPreset] {
    guard let stored = defaults.data(forKey: Self.presetsKey) else { return [] }
    do {
      return try JSONDecoder().decode([DemoPreset].self, from: stored)
    } catch {
      // A blob this build cannot read is not worth crashing the panel over —
      // unknown *fields* are already ignored; this is for a mangled write.
      BirdLog.warning(.demo, "stored demo presets are unreadable; treating as none — \(error.localizedDescription)")
      return []
    }
  }

  func savePresets(_ presets: [DemoPreset]) {
    guard let encoded = try? JSONEncoder().encode(presets) else { return }
    defaults.set(encoded, forKey: Self.presetsKey)
  }

  /// The preset the Director should read from, or nil when identification is off —
  /// disarmed, or armed at an id that no longer resolves.
  func armedPreset() -> DemoPreset? {
    let id = defaults.string(forKey: Self.armedKey) ?? ""
    guard !id.isEmpty else { return nil }
    return presets().first { $0.id == id }
  }

  /// Arm the preset with `id`, or pass nil to disarm — the app then never identifies.
  func armPreset(id: String?) {
    defaults.set(id ?? "", forKey: Self.armedKey)
  }

  /// True while some stored preset is still byte-for-byte the shipped one.
  ///
  /// Value equality rather than an id check, deliberately: editing the seeded copy is as
  /// much a departure from the shipped script as deleting it, and both are things the
  /// operator may want to undo. False is what surfaces "Reset to starter".
  var isShippedPresent: Bool {
    guard let template = shipped else { return false }
    return presets().contains(template)
  }

  /// Put the pristine shipped preset back: replacing the stored one that carries its id
  /// if it is still there, appending it if it was deleted.
  ///
  /// Arming is left alone. Restoring a script is not the same as choosing to run it, and
  /// silently re-arming would change what the next session plays without being asked.
  func resetToShipped() {
    guard let template = shipped else { return }
    let current = presets()
    if current.contains(where: { $0.id == template.id }) {
      savePresets(current.map { $0.id == template.id ? template : $0 })
    } else {
      savePresets(current + [template])
    }
  }

  /// First run: copy the template in and arm it, so the demo works out of the box before
  /// anyone opens the panel.
  ///
  /// Keyed on the presets key being *absent*, which is the only honest "never seeded"
  /// signal — an operator who deletes every preset leaves an empty list behind, and that
  /// must stay empty.
  private func seedIfNeeded() {
    guard defaults.object(forKey: Self.presetsKey) == nil, let template = shipped else { return }
    savePresets([template])
    armPreset(id: template.id)
  }
}
