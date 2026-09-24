/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesDisplayViewModelTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The display screen's two pieces of policy: **which birds a query offers to send**, and
/// **when the custom card is ready to go up.**
///
/// The matching itself belongs to Explore and is pinned by `ExploreViewModelTests`; what is
/// under test here is only the seam this screen adds — a blank field offers the whole guide,
/// anything else offers Explore's matches — against `PreviewCatalog.guide` for the same
/// reason that test uses it. The custom card's rule is the other seam: a bird chosen and a
/// message with ink in it, or the button never appears.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("GlassesDisplayViewModel")
struct GlassesDisplayViewModelTests {

  private let guide = PreviewCatalog.guide

  private func ids(_ species: [SpeciesWithMedia]) -> [String] {
    species.map(\.species.id)
  }

  @Test func aBlankQueryOffersTheWholeGuideInBrowseOrder() {
    // The screen opens ready to send: every bird on the table, in the order the guide
    // prints them, with nothing typed.
    let birds = GlassesDisplayViewModel.birdsFor("", in: guide)

    #expect(
      ids(birds) == [
        "american-crow", "blue-jay", "common-raven",
        "american-robin", "eastern-bluebird", "wood-thrush",
      ])
  }

  @Test func aWhitespaceQueryIsBlank() {
    // A field somebody spaced through must not read as a search for nothing.
    let birds = GlassesDisplayViewModel.birdsFor("   ", in: guide)

    #expect(birds.count == 6)
  }

  @Test func aQueryOffersWhatExploreWouldFind() {
    // One search policy in the app: what this field matches is exactly what Explore's
    // matches, so a bird findable there is sendable here by the same letters.
    let birds = GlassesDisplayViewModel.birdsFor("corvus", in: guide)

    #expect(ids(birds) == ["american-crow", "common-raven"])
  }

  @Test func aCustomCardNeedsBothABirdAndAMessage() {
    // Half a setup sends nothing: no bird means nowhere for the line to go, and no
    // line means the ordinary card already says it better.
    #expect(
      GlassesDisplayViewModel.customCardReady(
        bird: PreviewCatalog.blueJay,
        message: "The one to watch."
      ))
    #expect(
      !GlassesDisplayViewModel.customCardReady(
        bird: nil,
        message: "The one to watch."
      ))
    #expect(
      !GlassesDisplayViewModel.customCardReady(
        bird: PreviewCatalog.blueJay,
        message: ""
      ))
  }

  @Test func aWhitespaceMessageIsNoMessage() {
    // A message somebody spaced through must not put a card up with a blank last line.
    #expect(
      !GlassesDisplayViewModel.customCardReady(
        bird: PreviewCatalog.blueJay,
        message: "   \n"
      ))
  }
}
