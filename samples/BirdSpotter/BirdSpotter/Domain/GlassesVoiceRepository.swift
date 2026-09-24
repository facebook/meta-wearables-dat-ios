/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  GlassesVoiceRepository.swift
//  birdspotter
//

import Foundation

/// Something the wearer said to Meta AI that this app has a meaning for.
///
/// **Only the invocations the app acts on are named here.** The channel can carry more — a
/// spoken action with a payload string is expressible at the SDK — and everything that
/// arrives is answered at the data layer, because Meta AI waits on an answer for each one.
/// What crosses into the domain is the subset something above this line knows what to do
/// with, which today is the launch and nothing else. An action becomes a case here on the
/// day a spoken command has a screen to land on, and not before.
nonisolated enum GlassesVoiceEvent: Equatable, Sendable {

  /// "Hey Meta, open BirdSpotter" — the app is on screen because the wearer asked for it
  /// out loud, from the glasses. The one open that should arrive already reaching for
  /// them: the voice came from a pair on a face, and a session that starts anywhere else
  /// makes the wearer walk to the phone they deliberately left in a pocket.
  case launch
}

/// What the wearer says to Meta AI about this app, for as long as something is listening.
///
/// **Every event here has already been answered.** Meta AI holds each invocation open until
/// the app replies, and tells the wearer the app is not responding when no reply comes — so
/// the acknowledgement is owed the moment the invocation arrives, whatever the app goes on
/// to do with it. The data layer answers on the spot, and what reaches this stream is the
/// acting-on half: the session the wearer asked for.
///
/// **The stream is cold, and iterating it is what opens the channel** — parity rule 4. The
/// collector is the lease: the channel to Meta AI comes up when iteration starts and goes
/// down when it is cancelled, so a launch spoken while nothing iterates is Meta AI's to
/// time out. The shell iterates for as long as it is up, which is what makes the answer
/// arrive whenever the app does.
///
/// **The stream reports events and never failures.** The channel has its own — a device out
/// of reach, a message that would not send — and none of them is anything a screen can act
/// on: the launch already happened, on Meta AI's side, and the app is already open. They go
/// to the log, where a launch that was announced as unanswered can be diagnosed.
nonisolated protocol GlassesVoiceRepository: Sendable {

  /// Cold stream of the invocations this app has a meaning for. Cancelling unsubscribes.
  func voiceEventStream() -> AsyncStream<GlassesVoiceEvent>
}
