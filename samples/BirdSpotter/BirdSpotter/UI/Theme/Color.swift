/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// BirdSpotter palette — the "specimen cabinet" direction: museum-lacquer ground,
/// cool paper (deliberately not warm cream), aged brass as the single accent.
///
/// Provisional until the full visual-direction pass; the token names are the stable part.
struct BirdSpotterColors {
  let ink: Color
  let paper: Color
  let paperRaised: Color
  let lacquer: Color
  let lacquerRaised: Color
  let lacquerHigh: Color
  let gilt: Color
  let verdigris: Color
  /// The cabinet's red, and the palette's only one.
  ///
  /// A pigment name beside ``gilt`` and ``verdigris`` rather than a signal red, and muted for the
  /// same reason those are: a system-alert red would be the one colour on screen not drawn from
  /// the cabinet, and it would shout on a page whose loudest mark until now was a gold plate.
  ///
  /// It is the ink of **stopping and undoing**, and it is spent on exactly two controls: the one
  /// that ends a running session (``StopControl``) and a destructive ``ActionButton``. Both are
  /// the same sentence — *this ends something* — which is why they share one red rather than
  /// introducing a second. A second red is how a palette starts meaning nothing.
  ///
  /// It is never a status, never a chip, and never an error message's colour.
  let vermilion: Color
  /// A surface, despite the name — `gilt` laid over the ground thinly enough to tint it
  /// rather than colour it. What a control sits in when it wants to belong to the page's
  /// warm marks (the eyebrow, the section plates) without competing with the one card.
  ///
  /// Carried at low alpha rather than baked to a hex so it composites over `paper` and
  /// `lacquer` alike, the way `rule` does. Dark takes a little more of it: a warm wash
  /// registers less against the lacquer ground than against paper.
  let giltWash: Color
  /// ``giltWash``'s green counterpart, and what a box you type in is filled with.
  ///
  /// The same wash at the same alpha, laid in `verdigris` instead of `gilt`, because a field
  /// is not a label: gilt is the ink the app *names* things in, and a page whose search box,
  /// section plates and named birds are all one warm colour gives a watcher nothing to aim
  /// at. Verdigris is what the app asks you to *act* in — the buttons, the claim, Save — and a
  /// field is the quietest thing on that list, so it takes the same pigment at a whisper.
  let verdigrisWash: Color
  let textPrimary: Color
  let textSecondary: Color
  let textFaint: Color
  let rule: Color

  static let light = BirdSpotterColors(
    ink: Color(hex: 0x10171A),
    paper: Color(hex: 0xE9ECE6),
    paperRaised: Color(hex: 0xF3F5F0),
    lacquer: Color(hex: 0x10171A),
    lacquerRaised: Color(hex: 0x1A2429),
    lacquerHigh: Color(hex: 0x26333A),
    gilt: Color(hex: 0x8A6A28),
    verdigris: Color(hex: 0x456A60),
    vermilion: Color(hex: 0x9C3A28),
    giltWash: Color(hex: 0x8A6A28, opacity: 0.14),
    verdigrisWash: Color(hex: 0x456A60, opacity: 0.14),
    textPrimary: Color(hex: 0x10171A),
    textSecondary: Color(hex: 0x56635F),
    textFaint: Color(hex: 0x7C8985),
    rule: Color(hex: 0x10171A, opacity: 0.16)
  )

  static let dark = BirdSpotterColors(
    ink: Color(hex: 0x0D1315),
    paper: Color(hex: 0x0D1315),
    paperRaised: Color(hex: 0x151E21),
    lacquer: Color(hex: 0x10171A),
    lacquerRaised: Color(hex: 0x1A2429),
    lacquerHigh: Color(hex: 0x26333A),
    gilt: Color(hex: 0xC6A45E),
    verdigris: Color(hex: 0x6E9A8E),
    vermilion: Color(hex: 0xC25C46),
    giltWash: Color(hex: 0xC6A45E, opacity: 0.16),
    verdigrisWash: Color(hex: 0x6E9A8E, opacity: 0.16),
    textPrimary: Color(hex: 0xE9ECE6),
    textSecondary: Color(hex: 0x98A6A2),
    textFaint: Color(hex: 0x71807B),
    rule: Color(hex: 0xE9ECE6, opacity: 0.15)
  )
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}
