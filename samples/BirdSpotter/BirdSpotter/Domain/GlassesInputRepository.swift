/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesInputRepository.swift
//  birdspotter
//

import Foundation

/// Something the wearer did to the glasses that this app has a meaning for.
///
/// **Only the gestures the app acts on are named here.** The capability reports a good deal
/// more — drags with coordinates, a hold, a double press, the action button, the navigation
/// swipes, the Neural Band — and every one of them arrives at the data layer. What crosses into
/// the domain is the subset the session can honestly answer. A further gesture becomes a
/// further case here on the day something above this line knows what to do with it, and not
/// before: a case nothing consumes is a promise the screen has not made.
nonisolated enum GlassesInputEvent: Equatable, Sendable {

  /// The capture button on the temple, pressed once — the same ask as the shutter on
  /// screen, made from the wearer's own hand.
  case shutter

  /// Back, swiped on the temple — the wearer asking to leave, and the one gesture this app
  /// takes out of the system's hands.
  ///
  /// **Taking it is the point.** Left to the system, back means *leave the running
  /// experience*, and a wearer who swipes it mid-run takes the whole session down with them.
  /// The price of taking it is that back now owes the wearer an answer, and this is where the
  /// screen above says what that answer is.
  case back
}

/// What the wearer's hands are doing, for as long as a session is listening.
///
/// **The stream is scoped to a running session, not to a sensor of its own.** The inputs
/// capability rides the device session the way the camera does, so there is nothing to start
/// here and nothing to stop: iterating registers interest, and events arrive while a session
/// is up and holds the capability. Iterating with no session running is not an error — it is
/// simply quiet, which is the honest reading of a pair of glasses nobody is wearing.
///
/// **Deliberately not a throwing stream.** The capability has its own failures — a denied
/// grant, a closed channel, a disconnect — and every one of them is already a fact about the
/// *session*, which ``GlassesSessionRepository/sessionStream()`` reports and the screen
/// already draws. Surfacing them a second time here would give the pill two places to learn
/// the same news and two chances to disagree about it.
nonisolated protocol GlassesInputRepository: Sendable {

  /// Cold stream of the presses this app has a meaning for. Cancelling unsubscribes.
  func inputEventStream() -> AsyncStream<GlassesInputEvent>
}
