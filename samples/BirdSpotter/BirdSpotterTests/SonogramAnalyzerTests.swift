/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramAnalyzerTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The live sonogram's arithmetic: that a known tone lands in the bin it belongs to, that silence
/// sits on the floor, and that columns come out at the rate the strip is drawn at.
///
/// These are the tests that keep every build drawing the *same picture*. The transform is written
/// out longhand precisely so it can be pinned like this — a framework FFT and a hand-rolled loop
/// can both be correct and still disagree about windowing or scaling, and nobody would notice
/// until two strips were side by side on a slide.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("SonogramAnalyzer")
struct SonogramAnalyzerTests {

  /// A full-scale tone at `frequency`, sampled at ``captureSampleRate``.
  private func tone(frequency: Double, count: Int) -> AudioChunk {
    AudioChunk(
      samples: (0..<count).map { n in
        Float(sin(2 * Double.pi * frequency * Double(n) / Double(captureSampleRate)))
      }
    )
  }

  private func silence(_ count: Int) -> AudioChunk {
    AudioChunk(samples: [Float](repeating: 0, count: count))
  }

  private func peakBin(_ column: SonogramColumn) -> Int {
    var best = 0
    for bin in column.magnitudes.indices where column.magnitudes[bin] > column.magnitudes[best] {
      best = bin
    }
    return best
  }

  // MARK: - Windowing

  @Test func analyze_withAChunkShorterThanAWindow_returnsNothingAndKeepsTheSamples() {
    let analyzer = SonogramAnalyzer()

    // 400 is short of the 512 a column needs, so nothing can be said yet — but the samples
    // must not be thrown away, which the second chunk proves.
    #expect(analyzer.analyze(silence(400)).isEmpty)
    #expect(analyzer.analyze(silence(400)).count == 2)
  }

  @Test func analyze_producesAColumnEveryHop() {
    let analyzer = SonogramAnalyzer()

    // One second of audio: windows start at 0, 256, … up to the last one that still has 512
    // samples behind it. 62.5 columns a second, rounded down to whole windows.
    let columns = analyzer.analyze(silence(captureSampleRate))

    #expect(columns.count == 61)
  }

  @Test func reset_forgetsTheTail() {
    let analyzer = SonogramAnalyzer()
    _ = analyzer.analyze(silence(400))

    analyzer.reset()

    // Without the reset these 400 would have completed a window alongside the first 400.
    #expect(analyzer.analyze(silence(400)).isEmpty)
  }

  // MARK: - The transform

  @Test func analyze_withASineAtABinCentre_peaksInThatBin() {
    // 1000 Hz is exactly bin 32 at 31.25 Hz a bin, so there is no scalloping to allow for:
    // the tone belongs to one bin and the test can say which.
    let analyzer = SonogramAnalyzer()

    let columns = analyzer.analyze(tone(frequency: 1000, count: 2048))

    #expect(!columns.isEmpty)
    for column in columns {
      #expect(peakBin(column) == 32)
    }
  }

  @Test func analyze_withAFullScaleSine_reachesTheTopOfTheScale() {
    let analyzer = SonogramAnalyzer()

    let column = analyzer.analyze(tone(frequency: 1000, count: 1024))[0]

    // The scale is chosen so a full-scale sine reads 0 dB, which normalises to 1. Anything
    // less and the loudest thing the phone can hear would still draw dim.
    #expect(abs(column.magnitudes[32] - 1) < 0.02)
  }

  @Test func analyze_withSilence_sitsOnTheFloor() {
    let analyzer = SonogramAnalyzer()

    let column = analyzer.analyze(silence(1024))[0]

    for magnitude in column.magnitudes {
      #expect(abs(magnitude) < 0.0001)
    }
  }

  @Test func analyze_measuresTheColumnsOwnLoudness() {
    let analyzer = SonogramAnalyzer()

    let loud = analyzer.analyze(tone(frequency: 1000, count: 1024))[0]
    analyzer.reset()
    let quiet = analyzer.analyze(silence(1024))[0]

    // RMS, so a full-scale sine is 0.707 — which is -3 dB, near the top of the scale without
    // pinning to it. Silence is the floor, the same floor the magnitudes are measured against.
    #expect(abs(loud.level - 0.957) < 0.01)
    #expect(abs(quiet.level) < 0.0001)
  }

  @Test func analyze_withASine_leavesTheRestOfTheColumnQuiet() {
    let analyzer = SonogramAnalyzer()

    let column = analyzer.analyze(tone(frequency: 1000, count: 1024))[0]

    // Hann leaks into the neighbours, so the check skips them; three bins out the column
    // should be near the floor. A rectangular window would fail this everywhere.
    for (bin, magnitude) in column.magnitudes.enumerated() where bin < 29 || bin > 35 {
      #expect(magnitude < 0.35, "bin \(bin) was \(magnitude)")
    }
  }
}
