/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SpeciesGroup.swift
//  birdspotter
//

import Foundation

/// One section of the field guide — a header and the birds under it.
///
/// The guide is browsed in checklist sequence (``Species/browseOrder``), and a reader
/// needs landmarks in 93 rows or the scroll is featureless. The sections are the
/// landmarks: *Birds of Prey*, *Woodpeckers*, *Warblers*. ``name`` is
/// ``Species/groupName``, carried straight from the seed rather than derived here, so the
/// editorial call about which families sit together is made once in the CSV instead of
/// twice in two languages.
nonisolated struct SpeciesGroup: Identifiable, Equatable, Sendable {
  var name: String
  var species: [SpeciesWithMedia]

  var id: String { name }
}
