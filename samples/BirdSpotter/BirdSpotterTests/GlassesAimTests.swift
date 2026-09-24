/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesAimTests.swift
//  birdspotterTests
//

import Testing
@testable import birdspotter

/// Where a wearer is aiming, out of one motion sample.
///
/// **This one is mirrored, unlike the phone providers' tests.** Those cover a line of sensor
/// plumbing and take the platform-plumbing carve-out; this covers the geometry both apps derive
/// identically from the same two vectors, which is design and belongs under the testing-parity
/// rule.
///
/// The poses below are built by hand rather than captured, so each one says what it means: gravity
/// is whichever way *up* is in the glasses' own axes, and the field is whichever way north is from
/// there.
@Suite("GlassesAim")
struct GlassesAimTests {

  // MARK: - Elevation

  @Test func elevation_withALevelHead_readsTheHorizon() throws {
    // Level: up runs along the glasses' own up axis, and the forward axis lies flat.
    let degrees = try #require(elevation(fromAcceleration: Vector3(x: gravity, y: 0, z: 0)))

    #expect(abs(degrees) < tolerance)
  }

  @Test func elevation_withAHeadTiltedUp_readsAboveTheHorizon() throws {
    // Pitched up 30°: up leans back over the wearer, which tips the forward axis at the sky.
    let up = Vector3(x: gravity * 0.8660254, y: 0, z: gravity * 0.5)

    let degrees = try #require(elevation(fromAcceleration: up))

    #expect(abs(degrees - 30) < tolerance)
  }

  @Test func elevation_withAHeadTiltedDown_readsBelowTheHorizon() throws {
    // The mirror of the pose above, and the reading mirrors with it.
    let up = Vector3(x: gravity * 0.8660254, y: 0, z: gravity * -0.5)

    let degrees = try #require(elevation(fromAcceleration: up))

    #expect(abs(degrees + 30) < tolerance)
  }

  @Test func elevation_inFreefall_saysNothing() {
    // No gravity, no up, no answer — the one case where there is genuinely nothing to report
    // rather than something to report badly.
    #expect(elevation(fromAcceleration: Vector3(x: 0, y: 0, z: 0)) == nil)
  }

  // MARK: - Bearing

  @Test func bearing_facingNorth_readsNorth() throws {
    // Level head, field running out along the forward axis: the wearer is looking up the
    // field lines, which is what facing north is.
    let sample = GlassesMotionSample(
      acceleration: Vector3(x: gravity, y: 0, z: 0),
      magneticField: Vector3(x: 0, y: 0, z: fieldStrength)
    )

    let degrees = try #require(bearing(fromMotion: sample))

    #expect(abs(degrees) < tolerance)
  }

  @Test func bearing_facingEast_readsAQuarterTurn() throws {
    // Same level head, north now off the wearer's left shoulder — so they are facing east.
    let sample = GlassesMotionSample(
      acceleration: Vector3(x: gravity, y: 0, z: 0),
      magneticField: Vector3(x: 0, y: -fieldStrength, z: 0)
    )

    let degrees = try #require(bearing(fromMotion: sample))

    #expect(abs(degrees - 90) < tolerance)
  }

  @Test func bearing_withATiltedHeadInADippingField_stillReadsNorth() throws {
    // **The test the whole tilt compensation exists for.** The field dips 60° into the ground
    // at these latitudes and the wearer is looking 30° up, so the raw reading is nowhere near
    // horizontal — and the bearing is still due north, because gravity is what flattens it.
    // Without the compensation this is the sample that reads wildly wrong while looking
    // perfectly reasonable.
    let sample = GlassesMotionSample(
      acceleration: Vector3(x: gravity * 0.8660254, y: 0, z: gravity * 0.5),
      magneticField: Vector3(x: -fieldStrength, y: 0, z: 0)
    )

    let degrees = try #require(bearing(fromMotion: sample))

    #expect(abs(degrees) < tolerance)
  }

  @Test func bearing_withNoFieldReported_saysNothing() {
    // Optional at the sensor, so a pair that reports motion without a magnetometer has no
    // compass to offer and says so rather than guessing from gravity alone.
    let sample = GlassesMotionSample(acceleration: Vector3(x: gravity, y: 0, z: 0))

    #expect(bearing(fromMotion: sample) == nil)
  }

  @Test func bearing_lookingStraightUp_saysNothing() {
    // The forward axis is vertical, so it has no shadow on the ground to take a bearing from.
    // *Which way* stops having an answer here rather than getting a wrong one.
    //
    // The field is deliberately left horizontal, so north is perfectly findable and the forward
    // axis is the only thing that has run out — otherwise this would pass for the wrong reason.
    let sample = GlassesMotionSample(
      acceleration: Vector3(x: 0, y: 0, z: gravity),
      magneticField: Vector3(x: fieldStrength, y: 0, z: 0)
    )

    #expect(bearing(fromMotion: sample) == nil)
  }
}

/// Roughly what a still pair reads, in m/s². The exact value never matters — only the direction
/// does — but a realistic magnitude keeps the poses honest.
private let gravity: Double = 9.81

/// Roughly the Earth's field in µT. Same story: only the direction is read.
private let fieldStrength: Double = 48

/// In degrees: wide enough to absorb the trig constants above being written to seven places rather
/// than exactly, and still four orders of magnitude tighter than the nearest thing that would
/// change an answer — a band boundary 17.5° away.
private let tolerance: Double = 1e-4
