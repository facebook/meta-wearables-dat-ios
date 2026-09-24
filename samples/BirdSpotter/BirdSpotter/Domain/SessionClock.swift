/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SessionClock.swift
//  birdspotter
//

import Foundation

/// How often the strip is told that now has moved — thirty a second.
///
/// This is a **redraw rate, not the clock**. Nothing is measured with it and no stamp is read off
/// it; it exists because a strip whose right edge is *now* has to be told when now has moved, and
/// during a gap in the audio there is nothing else to tell it.
///
/// Thirty rather than the sixty it used to be, because every tick re-rasterises the visible window
/// on the main thread and the tick never stops — it runs behind the camera panel's scrim too, where
/// it was competing with a pinch for the same thread. The window crosses the screen in eight
/// seconds, about four pixels a tick at thirty; nobody's eye finds the step. Sixty was priced for a
/// screen with nothing else on it, and this screen now has a live camera.
nonisolated let timelineTick = Duration.milliseconds(33)

/// How far the audio may fall behind the clock before the strip calls it a gap — about a quarter
/// of a second.
///
/// Under it is ordinary jitter: a microphone hands over buffers when it feels like it, and closing
/// up a column or two would cost more than it bought. Over it the microphone genuinely stopped —
/// it was taken, it dropped, or it is being handed between the glasses and the phone — and that
/// silence belongs on the strip at the second it happened rather than closed up as though the
/// session had simply been shorter.
nonisolated let audioGapColumns = 16

/// The session's clock, and the only authority on *when*: the strip's live edge, a log row's
/// stamp and an audio segment's offset are all readings of it.
///
/// **It used to be the sonogram.** Elapsed was `count / sonogramColumnsPerSecond`, which made a
/// stamp and the sound underneath it the same measurement — a genuinely good property, and one
/// that holds only while a single microphone runs from the first second to the last. It does not
/// survive failover. With the audio as the clock a four-second dropout is four seconds of no
/// columns, so the strip stops scrolling, elapsed stops moving, and every event after the gap is
/// stamped four seconds early: the timeline silently deletes exactly the interval it exists to
/// record, and nothing throws.
///
/// So the clock is its own thing and the sonogram is aligned to it — the clock anchors a
/// stretch of recording, and samples place themselves within one.
@MainActor protocol SessionClock: AnyObject {

  /// Seconds since ``start()``.
  var elapsed: Double { get }

  /// Starts the clock, or restarts it from zero for a new session.
  func start()
}

extension SessionClock {

  /// Where the session is on the strip — the one multiplication that turns the clock into a
  /// column, and the only place the two meet.
  var column: Int { Int(elapsed * sonogramColumnsPerSecond) }
}

/// Which column audio heard *now* belongs at: where the write head already is, or where the clock
/// says, once the two have come far enough apart to mean the microphone stopped.
///
/// Ordinary jitter is left alone. A microphone hands over buffers when it feels like it, and
/// closing up a column or two costs more than it buys — it is also the harmless direction, because
/// audio running fractionally *ahead* of the clock is invisible where audio running behind it
/// would leave a permanent sliver of black at the live edge.
nonisolated func placement(clockColumn: Int, written: Int) -> Int {
  clockColumn - written > audioGapColumns ? clockColumn : written
}
