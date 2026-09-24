/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  FailoverAudioSourceTests.swift
//  birdspotterTests
//

import Foundation
import Testing
@testable import birdspotter

/// One microphone stream over two real ones: the phone until the glasses are asked for, the
/// glasses while they answer, and the phone again — opened once — the moment they give out.
///
/// Scenario names are fixed by the testing-parity rule.
@Suite("FailoverAudioSource")
struct FailoverAudioSourceTests {

  @Test func audioStream_whenTheGlassesGiveOut_opensThePhoneOnce() async {
    // The glasses fail on the spot; the phone answers for as long as it is asked to.
    let glasses = CountingAudioSource(kind: .glasses, fails: true)
    let phone = CountingAudioSource(kind: .phone, fails: false)
    let failover = FailoverAudioSource(preferred: glasses, fallback: phone)
    failover.usePreferred(true)

    var heard: [CaptureSourceKind] = []
    do {
      for try await chunk in failover.audioStream() {
        heard.append(chunk.source)
        if heard.count == 3 { break }
      }
    } catch {
      Issue.record("the stream failed: \(error)")
    }

    // The whole bug: a failover that reopened the phone once per chunk — or thousands of
    // times a second between chunks — instead of once.
    #expect(heard == [.phone, .phone, .phone])
    #expect(glasses.opens == 1)
    #expect(phone.opens == 1)
  }

  @Test func audioStream_whenTheRequestChanges_handsOverOnce() async {
    let glasses = CountingAudioSource(kind: .glasses, fails: false)
    let phone = CountingAudioSource(kind: .phone, fails: false)
    let failover = FailoverAudioSource(preferred: glasses, fallback: phone)

    var heard: [CaptureSourceKind] = []
    do {
      for try await chunk in failover.audioStream() {
        heard.append(chunk.source)
        if heard.count == 2 { failover.usePreferred(true) }
        if heard.last == .glasses && heard.filter({ $0 == .glasses }).count == 2 { break }
      }
    } catch {
      Issue.record("the stream failed: \(error)")
    }

    #expect(heard.prefix(2) == [.phone, .phone])
    #expect(heard.suffix(2) == [.glasses, .glasses])
    #expect(phone.opens == 1)
    #expect(glasses.opens == 1)
  }

  @Test func audioStream_whenThePhoneWillNotOpen_keepsWaitingForIt() async {
    // A phone locked in a pocket refuses its recorder until the first unlock, and a phone
    // call takes it mid-walk: neither is the session ending. The phone is asked again until
    // it answers, and the stream never fails.
    let glasses = CountingAudioSource(kind: .glasses, fails: false)
    let phone = CountingAudioSource(kind: .phone, failsFirst: 2)
    let failover = FailoverAudioSource(
      preferred: glasses,
      fallback: phone,
      fallbackRetryDelay: .milliseconds(5)
    )

    var heard: [CaptureSourceKind] = []
    do {
      for try await chunk in failover.audioStream() {
        heard.append(chunk.source)
        if heard.count == 2 { break }
      }
    } catch {
      Issue.record("the stream failed: \(error)")
    }

    #expect(heard == [.phone, .phone])
    #expect(phone.opens == 3)
    #expect(glasses.opens == 0)
  }

  @Test func audioStream_whenMicrophoneAccessIsRevoked_endsTheSession() async {
    // The one refusal nothing waits out: the grant is gone, and no amount of asking again
    // brings it back — that is the Identify gate's to fix.
    let glasses = CountingAudioSource(kind: .glasses, fails: false)
    let phone = CountingAudioSource(kind: .phone, failsWith: .accessDenied)
    let failover = FailoverAudioSource(
      preferred: glasses,
      fallback: phone,
      fallbackRetryDelay: .milliseconds(5)
    )

    var failure: AudioCaptureError?
    do {
      for try await _ in failover.audioStream() {}
    } catch {
      failure = error as? AudioCaptureError
    }

    #expect(failure == .accessDenied)
    #expect(phone.opens == 1)
  }
}

/// A microphone that counts how many times it was opened, and either fails — at once, for the
/// first few opens, or with a particular refusal — or yields a chunk every few milliseconds
/// until it is cancelled.
private final class CountingAudioSource: AudioCaptureSource, @unchecked Sendable {
  let kind: CaptureSourceKind
  private let failsFirst: Int
  private let failsWith: AudioCaptureError
  private let lock = NSLock()
  private var count = 0

  var opens: Int { lock.withLock { count } }

  convenience init(kind: CaptureSourceKind, fails: Bool) {
    self.init(kind: kind, failsFirst: fails ? .max : 0)
  }

  init(kind: CaptureSourceKind, failsFirst: Int, failsWith: AudioCaptureError = .unavailable) {
    self.kind = kind
    self.failsFirst = failsFirst
    self.failsWith = failsWith
  }

  convenience init(kind: CaptureSourceKind, failsWith: AudioCaptureError) {
    self.init(kind: kind, failsFirst: .max, failsWith: failsWith)
  }

  func audioStream() -> AsyncThrowingStream<AudioChunk, Error> {
    let opened = lock.withLock { () -> Int in
      count += 1
      return count
    }
    return AsyncThrowingStream { continuation in
      if opened <= failsFirst {
        continuation.finish(throwing: failsWith)
        return
      }
      let task = Task { [kind] in
        while !Task.isCancelled {
          continuation.yield(AudioChunk(samples: [0.1], source: kind))
          try? await Task.sleep(for: .milliseconds(5))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
