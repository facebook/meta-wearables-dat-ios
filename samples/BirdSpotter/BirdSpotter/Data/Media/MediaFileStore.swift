/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  MediaFileStore.swift
//  birdspotter
//

import Foundation

/// The app's captured-media directory: bytes in, relative paths out.
///
/// Deliberately knows nothing about sightings, the database, or bird anything — it moves
/// files. Pairing a file with a row is ``LocalJournalRepository``'s job, and keeping
/// the two concerns apart is what lets the write ordering (file first, then row) live in
/// exactly one place.
///
/// **Paths are always relative to `rootURL`.** An absolute path stored in the database
/// would be wrong the moment the app's container moves — which on iOS happens on every
/// reinstall, since the container UUID changes — so callers store what ``write(_:group:name:fileExtension:)``
/// returns and resolve it again through ``resolve(_:)``.
///
/// Bundled catalog media is *not* handled here; that is an `assetKey` resolved out of
/// the app bundle, and it is read-only. This store owns only what the user captured.
nonisolated struct MediaFileStore: Sendable {

  let rootURL: URL

  /// Writes `data` to `<group>/<name>.<fileExtension>` and returns the path relative
  /// to the media root.
  ///
  /// `group` is an opaque bucket the caller chooses (the repository uses the sighting
  /// id) so related files can be dropped together with ``deleteGroup(_:)``.
  func write(
    _ data: Data,
    group: String,
    name: String,
    fileExtension: String
  ) async throws -> String {
    let relativePath = "\(group)/\(name).\(fileExtension)"
    let target = resolve(relativePath)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: target, options: .atomic)
    return relativePath
  }

  /// Absolute URL for a stored relative path. Does not check existence.
  func resolve(_ relativePath: String) -> URL {
    rootURL.appendingPathComponent(relativePath)
  }

  func exists(_ relativePath: String) async -> Bool {
    FileManager.default.fileExists(atPath: resolve(relativePath).path)
  }

  func sizeBytes(_ relativePath: String) async -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: resolve(relativePath).path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  /// Removes one file. Already-absent is success — deletion is idempotent.
  func delete(_ relativePath: String) async throws {
    let target = resolve(relativePath)
    guard FileManager.default.fileExists(atPath: target.path) else { return }
    try FileManager.default.removeItem(at: target)
  }

  /// Removes a whole group directory — every file ever written under `group`.
  ///
  /// This is the deliberate reason ``write(_:group:name:fileExtension:)`` groups at
  /// all: it also sweeps files from a capture that crashed before its row was
  /// inserted, which a row-by-row delete cannot see.
  func deleteGroup(_ group: String) async throws {
    try await delete(group)
  }

  /// Empties the store — every group, every file the app ever captured.
  ///
  /// The root directory itself stays, so the store is writable again straight after and
  /// nothing has to re-`open()` it. Already-empty is success, like every other delete here.
  func deleteAll() async throws {
    let contents = try FileManager.default.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: nil
    )
    for url in contents {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// What an outing's sonogram sidecar is called inside the outing's own group.
  ///
  /// One name, reached from both ends: Save writes it and the journal page reads it, and a
  /// sidecar the reader cannot find is a walk that recomputes its strip for no reason.
  static let sonogramName = "sonogram"
  static let sonogramExtension = "sono"

  /// Where ``sonogramName`` lands for an outing, relative to the media root.
  ///
  /// Under the outing's group rather than beside it, which is the whole reason it needs no
  /// cleanup of its own: ``deleteGroup(_:)`` already takes the directory.
  static func sonogramPath(outingId: String) -> String {
    "\(outingId)/\(sonogramName).\(sonogramExtension)"
  }

  /// The store rooted at Application Support / `media` — the app's own storage, backed
  /// up with the app, not visible in Photos. Captures are Journal content, not camera roll.
  static func open() throws -> MediaFileStore {
    let root = try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("media")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return MediaFileStore(rootURL: root)
  }
}
