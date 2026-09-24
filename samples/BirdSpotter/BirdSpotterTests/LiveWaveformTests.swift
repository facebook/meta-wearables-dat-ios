/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  LiveWaveformTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// The travelling waves the waveform reading is drawn from: how many there are, what makes them
/// move, what makes them tall, and what they draw when there is nothing to draw.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("LiveWaveform")
struct LiveWaveformTests {

  @Test func curves_areOnePerBandAtFullResolution() {
    let curves = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0)

    #expect(curves.count == LiveWaveform.curveCount)
    for curve in curves { #expect(curve.count == LiveWaveform.resolution) }
  }

  @Test func curves_carryTheWavelengthsAcrossTheWidth() {
    let curve = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0.5)[0]

    // Four waves cross zero twice each. One of those eight can land exactly on the last sample,
    // where the envelope has already taken the value to zero — so seven is the honest floor.
    let drawn = curve.filter { $0 != 0 }
    let crossings = zip(drawn, drawn.dropFirst()).count { ($0 > 0) != ($1 > 0) }
    #expect(crossings >= 2 * LiveWaveform.wavelengths - 1, "crossings were \(crossings)")
    #expect(crossings <= 2 * LiveWaveform.wavelengths, "crossings were \(crossings)")
  }

  @Test func curves_dieAtBothEnds() {
    let curves = LiveWaveform.curves(bins: flat(1), level: 1, phase: 1.7)

    // The envelope, not the sine: whatever the phase, the waves reach the strip's edges at
    // nothing, so the shape ends rather than being cut off.
    for curve in curves {
      #expect(abs(curve.first ?? 1) < 0.0001)
      #expect(abs(curve.last ?? 1) < 0.0001)
    }
  }

  @Test func curves_travelWithThePhase() {
    let now = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0)
    let later = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 1)

    // The clock is the only thing that moves them, and every curve has to move — three that
    // travelled together would read as one striped object.
    for curve in now.indices {
      let moved = now[curve].indices.contains { abs(now[curve][$0] - later[curve][$0]) > 0.05 }
      #expect(moved, "curve \(curve) did not move")
    }
  }

  @Test func curves_doNotAllTravelTheSameWay() {
    // Three curves travelling the same way read as one thing scrolling, and a scroll is a claim
    // about time that this reading does not have — the sonogram beside it is the one with a time
    // axis. Mixed signs are what keep the picture churning in place instead of running backwards.
    let directions = (0..<LiveWaveform.curveCount).map(direction(ofCurve:))

    #expect(directions.allSatisfy { $0 != 0 }, "a curve stood still: \(directions)")
    #expect(Set(directions).count > 1, "every curve travelled the same way: \(directions)")
  }

  /// Which way curve `index` travels, as the sign of the offset that best re-aligns it with
  /// itself half a second on. Measured across the middle half of the strip, where the envelope is
  /// flattest and the travelling sine is all that is moving.
  private func direction(ofCurve index: Int) -> Int {
    let now = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0)[index]
    let later = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0.5)[index]
    let middle = (LiveWaveform.resolution / 4)..<(LiveWaveform.resolution * 3 / 4)

    func misfit(_ offset: Int) -> Float {
      middle.reduce(0) { total, i in
        let difference = later[i] - now[i + offset]
        return total + difference * difference
      }
    }

    // ±8 samples covers a quarter of a wave at this resolution, which is more travel than half a
    // second buys any of the three — so the best alignment is a real match, not a range edge.
    let best = (-8...8).min { misfit($0) < misfit($1) } ?? 0
    return best.signum()
  }

  @Test func curves_scaleWithTheLevel() {
    let loud = LiveWaveform.curves(bins: flat(0.5), level: 1, phase: 0.4)
    let quiet = LiveWaveform.curves(bins: flat(0.5), level: 0.25, phase: 0.4)

    // The whole picture swells and falls with the room, and nothing about its shape changes as
    // it does — the phase is the same, so this is the same drawing at a quarter of the height.
    for curve in loud.indices {
      for i in loud[curve].indices {
        #expect(abs(loud[curve][i] * 0.25 - quiet[curve][i]) < 0.0001)
      }
    }
  }

  @Test func curves_followTheirOwnBandOfTheSpectrum() {
    // Everything in the top third — a bird, not a voice.
    let bins = (0..<sonogramBins).map { Float($0 > sonogramBins * 2 / 3 ? 1 : 0.05) }

    let curves = LiveWaveform.curves(bins: bins, level: 1, phase: 0)
    let reach = curves.map { curve in curve.map { abs($0) }.max() ?? 0 }

    // The third curve is the one that stands up. Three curves that only differed in phase would
    // be decoration; these carry the three numbers a listener would describe the sound with.
    #expect(reach[2] > reach[0], "reach was \(reach)")
    #expect(reach[2] > reach[1], "reach was \(reach)")
  }

  @Test func curves_areFlatWithNothingToDraw() {
    // Three ways to have nothing: no column at all, a silent one, and one whose bins are all
    // zero. All three are a microphone that is open and hearing nothing.
    #expect(LiveWaveform.curves(bins: [], level: 1, phase: 0).allSatisfy { $0.allSatisfy { $0 == 0 } })
    #expect(LiveWaveform.curves(bins: flat(0.5), level: 0, phase: 0).allSatisfy { $0.allSatisfy { $0 == 0 } })
    #expect(LiveWaveform.curves(bins: flat(0), level: 1, phase: 0).allSatisfy { $0.allSatisfy { $0 == 0 } })
  }

  @Test func bandLevels_splitTheSpectrumInThirds() {
    let bins = (0..<sonogramBins).map { bin -> Float in
      if bin < sonogramBins / 3 { 0.9 } else if bin < sonogramBins * 2 / 3 { 0.6 } else { 0.3 }
    }

    let bands = LiveWaveform.bandLevels(bins: bins)

    #expect(bands.count == LiveWaveform.curveCount)
    #expect(abs(bands[0] - 0.9) < 0.02)
    #expect(abs(bands[1] - 0.6) < 0.02)
    #expect(abs(bands[2] - 0.3) < 0.02)
  }

  /// A spectrum with the same thing in every bin.
  private func flat(_ magnitude: Float) -> [Float] {
    [Float](repeating: magnitude, count: sonogramBins)
  }
}
