/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SystemOutingAudioPlayer.swift
//  birdspotter
//

import AVFoundation
import Foundation

/// The ``OutingAudioPlayer`` the app ships: an `AVAudioEngine` whose source node pulls the
/// timeline straight out of an ``OutingPlayback``.
///
/// A source node rather than scheduled buffers, because the schedule *is* a pull: the render
/// callback asks for frames and ``OutingPlayback/read(fromFrame:into:)`` answers with sound
/// or the zeros a gap already is, so the engine never knows the outing had any. The engine
/// resamples 16 kHz mono up to whatever the hardware runs at.
///
/// The render callback runs on the audio thread, so the playhead lives in a lock-guarded
/// box the callback and the main actor share; position is the frames actually rendered,
/// which is as close to the truth as a streamed engine says out loud.
///
/// The engine is plumbing, not the mirror. See ``OutingAudioPlayer``.
@MainActor final class SystemOutingAudioPlayer: OutingAudioPlayer {

  private let engine = AVAudioEngine()
  private let playhead = Playhead()
  private var source: AVAudioSourceNode?

  private(set) var isPlaying = false

  var positionMs: Int64 {
    Int64(playhead.currentFrame()) * 1000 / Int64(captureSampleRate)
  }

  var onFinish: (() -> Void)?

  func load(_ playback: OutingPlayback) {
    stopRun()
    playhead.load(playback)
    attachSourceIfNeeded()
  }

  func play() {
    guard let playback = playhead.playbackOrNil(), !isPlaying else { return }
    guard playhead.currentFrame() < playback.totalFrames else { return }

    // `.playback` for the same reason the clip player sets it: this is the speaker's
    // moment, and a session left in `.record` would route the outing into silence.
    try? AVAudioSession.sharedInstance().setCategory(.playback)
    try? AVAudioSession.sharedInstance().setActive(true)

    playhead.onPlayedOut = { [weak self] in
      Task { @MainActor in self?.playedOut() }
    }
    do {
      try engine.start()
    } catch {
      return
    }
    playhead.setPlaying(true)
    isPlaying = true
  }

  func pause() {
    guard isPlaying else { return }
    playhead.setPlaying(false)
    engine.pause()
    isPlaying = false
  }

  func seek(toMs: Int64) {
    guard let playback = playhead.playbackOrNil() else { return }
    if isPlaying { pause() }
    let frame = min(max(OutingPlayback.frameOf(ms: toMs), 0), playback.totalFrames)
    playhead.moveTo(frame)
  }

  func release() {
    stopRun()
    engine.stop()
    // Politeness: whatever was playing before the page opened gets to resume.
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  /// The timeline played out under the render callback: the transport stops where it is.
  private func playedOut() {
    guard isPlaying else { return }
    playhead.setPlaying(false)
    engine.pause()
    isPlaying = false
    onFinish?()
  }

  private func stopRun() {
    playhead.setPlaying(false)
    if engine.isRunning { engine.pause() }
    isPlaying = false
  }

  private func attachSourceIfNeeded() {
    guard source == nil else { return }
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(captureSampleRate),
        channels: 1
      )
    else { return }

    let playhead = playhead
    let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
        return noErr
      }
      playhead.render(into: out, frames: Int(frameCount))
      return noErr
    }
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    source = node
  }
}

/// The playhead the audio thread and the main actor share: which frame is next, whether the
/// transport is rolling, and the schedule to pull from. Everything behind one lock, because
/// the render callback may not block on anything slower and the main actor may not tear a
/// read.
private final class Playhead: @unchecked Sendable {

  private let lock = NSLock()
  private var playback: OutingPlayback?
  private var frame = 0
  private var playing = false
  private var announcedEnd = false
  private var scratch: [Float] = []

  /// Called once, off the audio thread, when a run reaches the timeline's end.
  var onPlayedOut: (@Sendable () -> Void)?

  func load(_ playback: OutingPlayback) {
    lock.withLock {
      self.playback = playback
      frame = 0
      playing = false
      announcedEnd = false
    }
  }

  func playbackOrNil() -> OutingPlayback? {
    lock.withLock { playback }
  }

  func currentFrame() -> Int {
    lock.withLock { frame }
  }

  func moveTo(_ newFrame: Int) {
    lock.withLock {
      frame = newFrame
      announcedEnd = false
    }
  }

  func setPlaying(_ wanted: Bool) {
    lock.withLock { playing = wanted }
  }

  /// Fills one render quantum: timeline while rolling, silence while not — and exactly one
  /// played-out signal when the end crosses under the callback.
  func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
    let signalEnd: Bool = lock.withLock {
      guard playing, let playback else {
        for i in 0..<frames { out[i] = 0 }
        return false
      }
      if scratch.count != frames { scratch = [Float](repeating: 0, count: frames) }
      let valid = playback.read(fromFrame: frame, into: &scratch)
      for i in 0..<frames { out[i] = i < valid ? scratch[i] : 0 }
      frame += valid
      if valid == 0 && !announcedEnd {
        announcedEnd = true
        playing = false
        return true
      }
      return false
    }
    if signalEnd { onPlayedOut?() }
  }
}
