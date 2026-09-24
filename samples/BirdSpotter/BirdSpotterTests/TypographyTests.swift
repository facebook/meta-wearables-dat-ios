/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Testing
import UIKit
@testable import birdspotter

/// A missing `UIAppFonts` entry or a wrong PostScript name fails *silently* — UIKit and
/// SwiftUI just hand back the system font. These tests are the tripwire.
struct TypographyTests {

  @Test func everyBundledFaceRegisters() {
    let missing = BirdSpotterFont.verifyRegistered()
    #expect(missing.isEmpty, "Fonts failed to register: \(missing)")
  }

  /// Guards the specific trap: instancing folds the STAT "Roman" axis value into the
  /// PostScript name, so `PublicSans-Regular.ttf` registers as `PublicSansRoman-Regular`.
  /// If someone "tidies" these names to match the filenames, this fails.
  @Test func postScriptNamesAreNotFilenames() {
    #expect(UIFont(name: "PublicSans-Regular", size: 12) == nil)
    #expect(UIFont(name: BirdSpotterFont.sansRegular, size: 12) != nil)
  }

  /// Public Sans replaced Libre Franklin specifically because Franklin has no `tnum`
  /// and proportional digits, which makes live telemetry jitter. Verify the adopted
  /// face genuinely renders digits at a uniform advance.
  @Test func dataFaceHasTabularFigures() throws {
    let font = try #require(UIFont(name: BirdSpotterFont.sansMedium, size: 16))
    let tabular = UIFont(
      descriptor: font.fontDescriptor.addingAttributes([
        .featureSettings: [
          [
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
          ]
        ]
      ]),
      size: 16
    )
    let widths = "0123456789".map {
      ($0 as Character).description.size(withAttributes: [.font: tabular]).width
    }
    let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
    #expect(spread < 0.01, "Digits are not tabular; spread was \(spread)pt")
  }
}
