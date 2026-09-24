/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/*
 * Glyphs — the app's icon set.
 *
 * Every icon in the app is named here and nowhere else. A screen that reaches for a raw
 * asset name — or for an SF Symbol — is a screen that will drift from its opposite number,
 * which is exactly how the two tab bars ended up drawing different pictures.
 *
 * The drawings live in `assets/glyphs/`; see that folder's README for provenance and
 * `licenses/icons/` for the terms.
 */

/// The mirrored glyph set — every icon the app draws, named once by role and resolved from
/// `assets/glyphs/`.
///
/// **Not SF Symbols, deliberately.** SF Symbols is licensed only for user interfaces running
/// on Apple operating systems, so a symbol used here would be a drawing this design system
/// cannot own. Roles, not pictures: `selected` is a checkmark today, and if it stops being one
/// it stops being one everywhere at once.
struct BirdSpotterGlyphs {

  // MARK: Tab bar
  //
  // Fill weight, all three. Identify is our own mark and the mark is a solid silhouette;
  // an outline binoculars beside it reads as two icon sets sharing one row.

  /// Binoculars — the field guide.
  let explore = "GlyphExplore"

  /// The BirdSpotter swallow. Says *bird*, which covers both the photo and the sound path.
  let identify = "GlyphIdentify"

  /// An open book — the life list.
  let journal = "GlyphJournal"

  // MARK: Navigation

  /// Back, in a screen that draws its own bar. A caret rather than an arrow — the shape that
  /// reads as "back" without belonging to any one platform's chrome.
  let back = "GlyphBack"

  /// Dismiss a modal or a wizard.
  let close = "GlyphClose"

  /// The right-hand caret on a row that opens something.
  let disclosure = "GlyphDisclosure"

  // MARK: Controls

  /// A search field's leading mark.
  let search = "GlyphSearch"

  /// Clear a search field. Filled, so it reads as a button rather than as decoration.
  let clearSearch = "GlyphClearSearch"

  /// A chosen option — wizard answers, filter chips.
  let selected = "GlyphSelected"

  /// Settings, as a toolbar control.
  let settings = "GlyphSettings"

  /// The viewfinder's capture control — a ring around a disc, the shape every camera app has
  /// taught people to reach for. Ours rather than Phosphor's: the set has no shutter, and the
  /// ring-and-disc is a control's shape rather than a picture of one.
  let shutter = "GlyphShutter"

  /// The viewfinder's light, on. A bolt rather than a bulb, because a bolt is what a camera
  /// control has meant since the flashgun.
  let flash = "GlyphFlash"

  /// The same bolt, struck through: the light is off. A second drawing rather than the first one
  /// dimmed — a control that is *off* and a control that is *unavailable* would otherwise be the
  /// same picture at different opacities, and the panel shows both.
  let flashOff = "GlyphFlashOff"

  // MARK: Content

  /// Supplementary detail about a result.
  let info = "GlyphInfo"

  /// The affordance on canned Q&A.
  let help = "GlyphHelp"

  /// A recording — the marker on a species' call.
  let call = "GlyphCall"

  /// Play a bird's recording. Filled, so it reads as a button rather than as decoration —
  /// the same reasoning as `clearSearch`.
  let play = "GlyphPlay"

  /// Pause the recording. Filled, to match `play` so the transport control does not change
  /// weight as it toggles.
  let pause = "GlyphPause"

  /// The emblem an empty Settings screen is built around. Filled, because at emblem size a
  /// regular-weight gear reads as wiry.
  let settingsMark = "GlyphSettingsMark"

  /// Where something happened — the pin beside a session's fix, and a sighting's place.
  let location = "GlyphLocation"

  /// Which way the watcher is facing.
  let compass = "GlyphCompass"

  /// How high the watcher is aiming — the band the viewfinder is pointed at.
  ///
  /// An eye rather than an angle: the role is *where they are looking*, which on a phone is
  /// whichever way it is tilted and on a pair of glasses will be the wearer's own gaze. The
  /// drawing follows the role, so that day changes nothing here.
  let gaze = "GlyphGaze"

  /// The Meta AI glasses — the card that offers to link them, the settings screen that
  /// reports on them, and wherever else the wearable itself needs naming.
  let glasses = "GlyphGlasses"

  /// The same pair, on a head — for glasses that are **being worn**.
  ///
  /// **Two drawings because the wearer's own state is the thing worth showing.** A pair
  /// connected and a pair connected *and on a face* are different facts about whether the
  /// session is really seeing anything, and the don signal is the one reading that says which.
  /// The bare frames are the resting state; this is the live one.
  ///
  /// Ours rather than Phosphor's: the set has no eyeglasses-on-a-head, and a role the design
  /// system needs is a role it draws.
  let glassesWorn = "GlyphGlassesWorn"

  /// The phone in the watcher's hand, wherever it is one of two devices the app could be
  /// using — the session's source pill, most of all. Named `device` rather than `phone`
  /// because the role is *this thing you are holding*, and the label beside it reads
  /// "On device" for the same reason: what matters is that it is not the glasses.
  let device = "GlyphDevice"

  // MARK: Size anchors
  //
  // The identify wizard's size scale: sparrow → robin → crow → goose, the ladder every
  // printed guide has used for the question.
  //
  // These are the one set here that is *not* fitted to its own box. All four are drawn
  // in a single shared 64×56 box, feet on a common ground line, at their true sizes
  // relative to each other — so a screen draws all four at one identical frame and the
  // proportions come out of the artwork. Fitting each to its own box, the way every
  // other glyph is fitted, would render a sparrow and a goose the same size and throw
  // away the only thing the row says.

  /// Sparrow — stop 1, the smallest anchor.
  let sizeSparrow = "GlyphSizeSparrow"

  /// Robin — stop 3.
  let sizeRobin = "GlyphSizeRobin"

  /// Crow — stop 5.
  let sizeCrow = "GlyphSizeCrow"

  /// Goose — stop 7, and the one that fills the shared box.
  let sizeGoose = "GlyphSizeGoose"

  // MARK: The mark
  //
  // The badge from `assets/icon.svg`, split into its two layers so the splash can turn
  // the rings around a still swallow. Both are registered to the badge's own box —
  // unlike `identify`, which refits the swallow alone to the icon grid.

  /// The badge's rings — the swallow's surround.
  let markRings = "GlyphMarkRings"

  /// The badge's swallow, at the rings' registration.
  let markBird = "GlyphMarkBird"
}

extension Image {
  /// `Image(glyph: theme.glyphs.search)` — the one way an icon enters a view.
  ///
  /// The assets are template-rendered, so they take `foregroundStyle` like any symbol would.
  init(glyph: String) {
    self.init(glyph)
  }
}
