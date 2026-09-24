/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/*
 * Typefaces — "The Subscriber's Plate".
 *
 * Libre Caslon Display  headline serif; the register of English natural-history publishing
 * Libre Caslon Text     italic only, for scientific names (Display has no italic)
 * Public Sans           UI and data. A fork of Libre Franklin for the US Web Design System.
 * Cinzel                inscriptional caps. Wordmark and life-list numbering ONLY.
 *
 * Why Public Sans and not Libre Franklin: Libre Franklin ships no `tnum` feature and its
 * digits vary by 23.7% of an em, so a live-updating value on the Glasses screen visibly
 * jitters. Public Sans is the same Franklin skeleton with working tabular figures.
 *
 * This target registers *static* instances. SwiftUI resolves variable-font weights
 * unreliably and will hand back a smeared faux-bold, so each weight is its own file.
 */

/// PostScript names, which are **not** the filenames.
///
/// Instancing a variable font folds the STAT "Roman" axis value into the name, so the
/// files called `PublicSans-Regular.ttf` and `Cinzel-Bold.ttf` register as
/// `PublicSansRoman-Regular` and `CinzelRoman-Bold`. Getting these wrong fails silently —
/// SwiftUI falls back to the system font with no warning. Verify with
/// `BirdSpotterFont.verifyRegistered()` below.
enum BirdSpotterFont {
  static let caslonDisplay = "LibreCaslonDisplay-Regular"
  static let caslonTextItalic = "LibreCaslonText-Italic"
  static let sansRegular = "PublicSansRoman-Regular"
  static let sansMedium = "PublicSansRoman-Medium"
  static let sansSemiBold = "PublicSansRoman-SemiBold"
  static let sansBold = "PublicSansRoman-Bold"
  static let cinzelRegular = "CinzelRoman-Regular"
  static let cinzelBold = "CinzelRoman-Bold"

  static let all = [
    caslonDisplay, caslonTextItalic,
    sansRegular, sansMedium, sansSemiBold, sansBold,
    cinzelRegular, cinzelBold,
  ]

  /// Returns the names iOS could not resolve. Empty means every face registered.
  /// Called from a debug assertion at launch so a missing `UIAppFonts` entry surfaces
  /// immediately instead of as a quietly wrong-looking screen.
  static func verifyRegistered() -> [String] {
    all.filter { UIFont(name: $0, size: 12) == nil }
  }
}

/// The mirrored type scale — one role per line of the design, and the sizes that go with them.
///
/// Roles, not system text styles: a species name is `display`, which is what lets Meta's docs
/// show the same design whichever snippet a reader is looking at.
///
/// Every face is registered `relativeTo:` a system style, so Dynamic Type keeps working.
struct BirdSpotterTypography {
  /// Species name on a sighting card.
  let display = Font.custom(BirdSpotterFont.caslonDisplay, size: 34, relativeTo: .largeTitle)

  /// Section and screen titles.
  let title = Font.custom(BirdSpotterFont.caslonDisplay, size: 26, relativeTo: .title)

  /// Binomial name — italic serif, as the convention requires.
  let scientific = Font.custom(BirdSpotterFont.caslonTextItalic, size: 16, relativeTo: .body)

  /// Card and group headings.
  let headline = Font.custom(BirdSpotterFont.sansSemiBold, size: 18, relativeTo: .headline)

  /// Running text.
  let body = Font.custom(BirdSpotterFont.sansRegular, size: 16, relativeTo: .body)

  /// Buttons, chips, field labels.
  let label = Font.custom(BirdSpotterFont.sansMedium, size: 13, relativeTo: .subheadline)

  /// Timestamps, credits, secondary metadata.
  let caption = Font.custom(BirdSpotterFont.sansRegular, size: 12, relativeTo: .caption)

  /// Live sensor values on the Glasses screen. Pair with `.monospacedDigit()` at the call
  /// site — tabular figures are the whole point, and without them a ticking session timer
  /// shoves every digit beside it.
  let data = Font.custom(BirdSpotterFont.sansMedium, size: 15, relativeTo: .body)
    .monospacedDigit()

  /// Engraved-plate labels: the wordmark and life-list numbering ("SIGHTING NO. 0042").
  /// Uppercase, letterspaced, small. Cinzel has no lowercase worth reading — never use
  /// this for running text. Apply `.tracking(2.2)` and `.textCase(.uppercase)` alongside.
  let plate = Font.custom(BirdSpotterFont.cinzelBold, size: 11, relativeTo: .caption2)
}
