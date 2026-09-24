/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemSpokenOutput.swift
//  birdspotter
//

import AVFoundation
import Foundation

/// The ``SpokenOutput`` the app ships: the platform's own speech synthesiser, playing into the
/// audio session a session's microphone is already holding.
///
/// **It never takes the session from a capture**, which is the whole of how it coexists with
/// ``MicrophoneCapture``. That class owns the session for as long as the phone's microphone is
/// open — category, mode and preferred input — and two objects setting a category between them is
/// how a working microphone gets silenced by something that only wanted to make a noise. The one
/// thing the capture does on this feature's behalf is ask for `.playAndRecord` rather than
/// `.record`, so the session it brings up can speak; everything here rides that.
///
/// **The one category this sets is for a session that no capture has shaped.** When the glasses
/// are doing the listening, their microphone arrives on the camera stream and nothing here has
/// touched the audio session — which leaves it on the system default, a category the ring/silent
/// switch mutes. A demo that went quiet because a phone in a pocket was on silent is the failure
/// that avoids, so a session still on that default is given `.playback` before the first line.
///
/// **The consequence is that the app can only speak inside a live session**, which is also the
/// only time it has anything to say. An identification is a thing a session makes.
///
/// `@unchecked Sendable` for the reason ``MicrophoneCapture`` is: the delegate callbacks arrive on
/// AVFoundation's own thread, and everything they touch is behind ``lock``.
nonisolated final class SystemSpokenOutput: NSObject, SpokenOutput, @unchecked Sendable {

  private let synthesizer = AVSpeechSynthesizer()
  private let lock = NSLock()

  /// Who is waiting on which line, so a finished utterance resumes the right caller.
  private var waiting: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

  /// Lines handed over and not yet finished — the count rather than a flag, because lines
  /// queue: the second one's caller must not clear a state the first one is still in.
  private var linesInFlight = 0

  var isSpeaking: Bool { lock.withLock { linesInFlight > 0 } }

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ words: String) async {
    let line = words.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return }

    // The device-presence rule, at the one place that can read the actual route — see
    // ``SpokenOutput``. A dropped line is worth a log entry and nothing else: the timeline
    // has already said the same thing in writing, and the session goes on unchanged.
    guard hasSomewhereToSpeak else {
      BirdLog.info(.audio, "nowhere to speak — the line stays unsaid")
      return
    }

    // Only ever away from the system default — see the type's own note. Anything else is a
    // category somebody chose, and a capture's is not this class's to change.
    let session = AVAudioSession.sharedInstance()
    if session.category == .soloAmbient {
      try? session.setCategory(.playback, mode: .spokenAudio)
    }

    let utterance = AVSpeechUtterance(string: line)
    utterance.voice = Self.voice

    await withCheckedContinuation { continuation in
      // Registered before the synthesiser is handed the line, so a fast finish cannot
      // arrive at an empty table and leave the caller waiting forever.
      lock.withLock {
        waiting[ObjectIdentifier(utterance)] = continuation
        linesInFlight += 1
      }
      synthesizer.speak(utterance)
    }
  }

  func silence() {
    // `.immediate` rather than `.word`: this is the stop, and a stop that finishes the
    // syllable it was on is a stop the wearer notices twice.
    synthesizer.stopSpeaking(at: .immediate)
  }

  /// Whether anything said now would land in an ear rather than in the open air.
  ///
  /// **The route is the question, not the pairing.** A pair of glasses that has a session and no
  /// audio profile is not somewhere to speak, and a Bluetooth output that is not a pair of
  /// glasses is still an ear rather than a field full of birds — so what is asked is what the
  /// audio actually has in front of it. The media profile is where a line lands; the hands-free
  /// one still counts, because a headset that only offers that is an ear all the same.
  private var hasSomewhereToSpeak: Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
      switch output.portType {
      case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: true
      default: false
      }
    }
  }

  /// Resumes whoever was waiting on this line, however it ended.
  ///
  /// Finished and cancelled are the same event from up here — the words are no longer being
  /// said — and the removal is what makes the pair of them idempotent.
  private func finish(_ utterance: AVSpeechUtterance) {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard let waiter = waiting.removeValue(forKey: ObjectIdentifier(utterance)) else {
        return nil
      }
      linesInFlight -= 1
      return waiter
    }
    continuation?.resume()
  }

  /// The voice that reads the lines.
  ///
  /// **Asked for in English rather than taken from the device**, because the words being read
  /// are a catalog's own — "Green Jay" is a name, and a voice built for another language sounds
  /// it out phonetically rather than saying it. A device with no English voice installed falls
  /// back to whatever the synthesiser would have chosen, which is a strange accent rather than
  /// silence.
  private static let voice = AVSpeechSynthesisVoice(language: "en-US")
}

extension SystemSpokenOutput: AVSpeechSynthesizerDelegate {

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    finish(utterance)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    finish(utterance)
  }
}
