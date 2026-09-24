/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  CaptureScratchStore.swift
//  birdspotter
//

import Foundation

/// Somewhere to put a photograph that is only being looked at.
///
/// **Deliberately not ``MediaFileStore``.** That one is the Journal's: what it holds is
/// content the watcher captured on purpose, it is backed up with the app, and every file in
/// it is owned by a row in the database. A photograph taken to find out what `large` costs
/// is none of those things — it belongs to nobody, it should not survive the next demo, and
/// filing it beside a real sighting would put a test shot in somebody's journal.
///
/// So it lands in the caches directory, where the system is free to take it back, and the
/// screen that writes it empties the whole directory first. A file exists here for exactly
/// one reason: **the share sheet hands out a URL, not bytes.** Looking at the photograph
/// needs no file at all; saving it to the camera roll needs one.
nonisolated struct CaptureScratchStore: Sendable {

  let rootURL: URL

  /// Writes `data` as `name` and hands back where it landed.
  ///
  /// `name` carries the extension, because the extension is the whole reason the file has
  /// a name at all: it is what tells the share sheet this is an image and puts **Save
  /// Image** in the sheet rather than a list of places to file a document.
  func write(_ data: Data, named name: String) throws -> URL {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let target = rootURL.appendingPathComponent(name)
    try data.write(to: target, options: .atomic)
    return target
  }

  /// Throws the lot away. Already-empty is success, like every other delete in the app.
  ///
  /// Called on the way in rather than on the way out: a screen that swept up after itself
  /// would also sweep the file out from under a share sheet the watcher left open, and a
  /// crash would leave the directory behind anyway.
  func empty() {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: nil
      )) ?? []
    for url in contents {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// The store rooted at Caches / `glasses-captures`.
  static func open() throws -> CaptureScratchStore {
    let root = try FileManager.default
      .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("glasses-captures")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return CaptureScratchStore(rootURL: root)
  }
}
