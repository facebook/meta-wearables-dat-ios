/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  WavCodecTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// The journal's audio files, written and read by hand: what goes out must come back, and
/// anything this app never writes must be refused rather than guessed at.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("WavCodec")
struct WavCodecTests {

  @Test func roundTrip_returnsTheSamplesItWasGiven() throws {
    let samples = (0..<1000).map { Float(sin(Double($0) / 20)) * 0.8 }

    let decoded = try WavCodec.decode(WavCodec.encode(samples))

    #expect(decoded.count == samples.count)
    for i in samples.indices {
      // One quantisation step is the honest cost of 16-bit; anything more is a bug.
      #expect(abs(samples[i] - decoded[i]) <= 1 / Float(Int16.max))
    }
  }

  @Test func encode_writesTheHeaderASpecReaderExpects() {
    let bytes = WavCodec.encode([Float](repeating: 0, count: 8))

    #expect(String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE")
    #expect(String(decoding: bytes[12..<16], as: UTF8.self) == "fmt ")
    #expect(String(decoding: bytes[36..<40], as: UTF8.self) == "data")
    // 8 samples of 16-bit mono: 16 payload bytes on a 44-byte header.
    #expect(bytes.count == 44 + 16)
    // The sample rate, little-endian at offset 24.
    let rate = Int(bytes[24]) | Int(bytes[25]) << 8 | Int(bytes[26]) << 16 | Int(bytes[27]) << 24
    #expect(rate == captureSampleRate)
  }

  @Test func decode_clampsWhatOverdrives() throws {
    let decoded = try WavCodec.decode(WavCodec.encode([1.5, -1.5]))

    #expect(abs(decoded[0] - 1) < 0.001)
    #expect(abs(decoded[1] + 1) < 0.001)
  }

  @Test func decode_refusesWhatTheAppNeverWrites() {
    // Not a WAV at all.
    #expect(throws: (any Error).self) {
      _ = try WavCodec.decode(Data(count: 100))
    }

    // A real header at the wrong rate: byte 24 carries the sample rate.
    var wrongRate = WavCodec.encode([Float](repeating: 0, count: 8))
    wrongRate[24] = 0x44
    wrongRate[25] = 0xAC
    #expect(throws: (any Error).self) {
      _ = try WavCodec.decode(wrongRate)
    }
  }

  @Test func decode_upsamplesASegmentSavedAtTheOldRate() throws {
    // Byte 24 carries the sample rate: 8000 is 0x1F40, the rate segments were saved at before
    // the capture rate doubled.
    var legacy = WavCodec.encode([0.2, 0.4, 0.6])
    legacy[24] = 0x40
    legacy[25] = 0x1F

    let decoded = try WavCodec.decode(legacy)

    // Doubled, each new sample halfway between its neighbours and the last one held.
    let expected: [Float] = [0.2, 0.3, 0.4, 0.5, 0.6, 0.6]
    #expect(decoded.count == expected.count)
    for i in expected.indices {
      #expect(abs(decoded[i] - expected[i]) < 0.001)
    }
  }

  @Test func decode_walksPastAForeignChunk() throws {
    // A `LIST` chunk between `fmt ` and `data`, the way editors leave metadata behind.
    let plain = WavCodec.encode([0.5, -0.5])
    let listBody = Data(count: 6)
    var withList = Data()
    withList.append(plain[0..<36])
    withList.append(contentsOf: "LIST".utf8)
    withList.append(contentsOf: [UInt8(listBody.count), 0, 0, 0])
    withList.append(listBody)
    withList.append(plain[36...])

    let decoded = try WavCodec.decode(withList)

    #expect(decoded.count == 2)
    #expect(abs(decoded[0] - 0.5) < 0.001)
  }
}
