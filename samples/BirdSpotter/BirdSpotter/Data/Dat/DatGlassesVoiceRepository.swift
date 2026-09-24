/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  DatGlassesVoiceRepository.swift
//  birdspotter
//

import Foundation
import MWDATCore

/// The DAT-backed ``GlassesVoiceRepository`` — where a "Hey Meta" launch is answered.
///
/// **The answer is the contract.** Meta AI holds every invocation open until the app replies
/// through its response handle, and announces the app as not responding when no reply comes
/// — opening on screen is not the answer, the reply is. So each invocation is answered here,
/// the moment it arrives: success for a launch, before anything upstream reacts to it, and
/// failure for a spoken action, because this app defines none and silence would read as a
/// hang. What the domain sees afterwards is only the events it can act on.
///
/// **Not a hat on the session link, unlike the other glasses repositories.** A launch is
/// what *asks* for a session, so the channel cannot ride one — it listens on a device of its
/// own choosing instead. The choice itself is still the link's ranking
/// (``DatGlassesSessionRepository/preferredIdentifier()``), so the pair a launch is answered
/// from is the pair the rest of the app is about; the channel follows the roster and moves
/// with it, because at launch the roster is usually still empty and the pair it names
/// arrives a beat later.
///
/// **It waits for registration, then keeps the channel up.** Meta AI routes an invocation
/// only to a registered app and holds the launch open until the app answers, so the open is
/// held back until registration lands — opening ahead of it is what leaves the channel
/// erroring with the launch still in Meta AI's hand and nothing left to catch it. A channel
/// that then drops is reopened rather than logged and left down: the drop arrives on the
/// error publisher, not by ending a stream, so a first drop that went unhandled would be
/// permanent and the held launch lost for the life of the process.
nonisolated final class DatGlassesVoiceRepository: GlassesVoiceRepository, @unchecked Sendable {

  /// The open channel, while a collector holds the stream open — what ``ensureListening()``
  /// starts and moves. Main-actor state because the channel is a main-actor object; there
  /// is one collector (the shell), so one channel.
  @MainActor private var stream: VoiceInvocationsStream?

  /// The pair the channel is started on, or `nil` while it has yet to take. `nil` is what
  /// makes ``ensureListening()`` ask again on the next change.
  @MainActor private var listeningOn: DeviceIdentifier?

  /// What ends the lease in flight, while there is one — the same signal a drop on the error
  /// publisher pulls, reachable from ``withChannelClosed(_:)``.
  @MainActor private var dropSignal: AsyncStream<Void>.Continuation?

  /// Set by ``withChannelClosed(_:)`` so the reopen that follows comes at the floor delay
  /// rather than wherever the backoff had climbed to: a lease closed on purpose is not a
  /// channel failing.
  @MainActor private var closedOnPurpose = false

  /// What holds the reopen back while ``withChannelClosed(_:)``'s body runs — the collector's
  /// loop waits on it before opening a fresh lease, so the new channel is opened on whatever
  /// the body left behind rather than on what it was about to take away.
  @MainActor private var reopenHold: AsyncStream<Void>?

  /// The shortest wait before reopening a dropped channel — the wearer is waiting on the
  /// launch — and the longest it grows to, so a channel that never recovers stays cheap.
  private static let reopenDelayFloorNanos: UInt64 = 500_000_000
  private static let reopenDelayCeilingNanos: UInt64 = 30_000_000_000

  func voiceEventStream() -> AsyncStream<GlassesVoiceEvent> {
    AsyncStream { continuation in
      // The channel is a main-actor object, so its whole life runs there; the work is
      // a handful of control messages, none of it worth a hop to account for.
      let task = Task { @MainActor in
        var reopenDelay = Self.reopenDelayFloorNanos
        while !Task.isCancelled {
          // Meta AI routes an invocation only to a registered app, and holds the
          // launch open until the app answers — so waiting for registration here
          // costs nothing and is exactly what a slower phone needs. Opening the
          // channel ahead of registration is what drops it, with the launch still
          // in Meta AI's hand and the channel gone before it could be caught.
          // Re-asked on every reopen, so a registration that drops and returns is
          // waited out afresh.
          await Self.awaitRegistered()
          if Task.isCancelled { break }

          let dropped = await self.listenOnce(yieldingTo: continuation)
          if !dropped { break }

          // Back off between reopens so a channel that keeps dropping does not
          // spin. The floor is short because the wearer is waiting on the launch;
          // the ceiling keeps a channel that never recovers cheap.
          if self.closedOnPurpose {
            self.closedOnPurpose = false
            reopenDelay = Self.reopenDelayFloorNanos
            // Held until whatever asked for the close is done — see
            // ``withChannelClosed(_:)``. A hold already released returns at once.
            if let hold = self.reopenHold {
              for await _ in hold { break }
            }
          }
          try? await Task.sleep(nanoseconds: reopenDelay)
          reopenDelay = min(reopenDelay * 2, Self.reopenDelayCeilingNanos)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Runs `body` with the channel closed: the lease in flight is ended and waited for, the
  /// body runs, and only then does the collector's loop open a fresh lease.
  ///
  /// **For the mock kit's flip, and nothing else.** The channel is a lease on a device, and
  /// swapping the SDK's providers underneath it leaves it listening on a pair that no longer
  /// exists — the same reason the session repository ends its leases before the flip. The
  /// body is the swap itself, held inside the closed window so the reopen cannot land on the
  /// providers about to be taken away. With no channel open the body simply runs; and the
  /// close is bounded: a channel that will not go inside a second is one the flip goes ahead
  /// without.
  @MainActor func withChannelClosed(_ body: () async -> Void) async {
    guard let dropSignal else {
      await body()
      return
    }
    let (hold, release) = AsyncStream<Void>.makeStream()
    reopenHold = hold
    closedOnPurpose = true
    dropSignal.yield()
    for _ in 0..<closeChannelPolls where stream != nil {
      try? await Task.sleep(for: .milliseconds(closeChannelPollMillis))
    }
    if stream != nil {
      BirdLog.error(.glasses, "voice channel — did not close in time for the mock kit's flip")
    }
    await body()
    release.finish()
    reopenHold = nil
  }

  /// Blocks until Meta AI reports the app registered — the point from which an invocation
  /// is routed at all. The launch is held on Meta AI's side meanwhile, so this is time the
  /// app has, not time it loses.
  private static func awaitRegistered() async {
    // The current reading first: the stream reports *changes*, so a channel reopened
    // while already registered would otherwise wait on a change that never comes.
    if case .registered = Wearables.shared.registrationState { return }
    for await state in Wearables.shared.registrationStateStream() {
      if case .registered = state { return }
    }
  }

  /// One lease of the channel: open it, answer what arrives, follow the roster, and return
  /// when it drops (`true` — reopen) or when the collector lets go (`false` — done).
  ///
  /// A drop arrives on the error publisher rather than by ending a stream, so it is turned
  /// into a signal that ends the lease — without which a first drop is permanent and the
  /// launch already held is lost for the life of the process.
  @MainActor private func listenOnce(
    yieldingTo continuation: AsyncStream<GlassesVoiceEvent>.Continuation
  ) async -> Bool {
    let stream: VoiceInvocationsStream
    do {
      stream = try VoiceInvocationsStream(wearables: Wearables.shared)
    } catch {
      BirdLog.error(.glasses, "voice channel — would not open", error)
      return true
    }
    self.stream = stream
    BirdLog.info(.glasses, "voice channel — open, waiting on Meta AI")

    let (drops, dropSignal) = AsyncStream<Void>.makeStream()
    self.dropSignal = dropSignal
    let tokens = ListenerTokenBag()
    stream.invocationsPublisher.listen { invocation in
      Task { await Self.answer(invocation, yieldingTo: continuation) }
    }.store(in: tokens)
    stream.errorPublisher.listen { error in
      // The specific case, not just its description: a channel that never connected, a
      // message the glasses sent that the SDK could not parse, and the unspecified
      // catch-all can all read alike through the bare description, and which one it is
      // is the whole of the diagnosis.
      BirdLog.error(.glasses, "voice channel — \(String(reflecting: error)): \(error.description)")
      dropSignal.yield()
    }.store(in: tokens)

    let dropped = await withTaskGroup(of: Bool.self) { group in
      // The channel listens on one pair at a time, and naming one is a race the roster
      // alone cannot settle: at a cold launch the pair is *listed* a beat before its
      // link is up, and a start asked in that window fails without the roster ever
      // saying anything more. So every device's link is watched too, and each change
      // asks again — the pattern the device snapshot already uses to keep itself live.
      group.addTask { @MainActor [weak self] in
        var deviceTokens: [any AnyListenerToken] = []
        for await identifiers in Wearables.shared.devicesStream() {
          for token in deviceTokens { await token.cancel() }
          deviceTokens.removeAll()

          self?.ensureListening()

          let devices = identifiers.compactMap {
            Wearables.shared.deviceForIdentifier($0)
          }
          for device in devices {
            deviceTokens.append(
              device.addLinkStateListener { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.ensureListening() }
              })
          }
        }
        for token in deviceTokens { await token.cancel() }
        return false
      }
      // The drop that ends the lease. A healthy channel never yields here.
      group.addTask {
        for await _ in drops { return true }
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }

    // The lease ends, the channel goes down with it — either torn down by a drop or let
    // go by the collector, per the cold-stream contract on the interface.
    if listeningOn != nil { stream.stop() }
    self.stream = nil
    self.dropSignal = nil
    listeningOn = nil
    await tokens.cancelAll()
    return dropped
  }

  /// Starts the channel on the preferred pair, or moves it there — asked on every roster
  /// and link change, and idempotent between them.
  ///
  /// A failed start leaves ``listeningOn`` empty on purpose: it is what makes the next
  /// change ask again, which is the whole repair for a launch spoken while the link was
  /// still coming up. Nothing here retries on a clock — the changes are the clock.
  @MainActor private func ensureListening() {
    guard let stream else { return }
    guard let preferred = DatGlassesSessionRepository.preferredIdentifier(),
      preferred != listeningOn
    else { return }
    if listeningOn != nil { stream.stop() }
    listeningOn = nil
    do {
      try stream.start(deviceIdentifier: preferred)
      listeningOn = preferred
      BirdLog.info(.glasses, "voice channel — listening on \(preferred)")
    } catch {
      BirdLog.error(.glasses, "voice channel — would not start", error)
    }
  }

  /// One invocation, answered — and, when the app has a meaning for it, passed upward.
  private static func answer(
    _ invocation: any VoiceInvocation,
    yieldingTo continuation: AsyncStream<GlassesVoiceEvent>.Continuation
  ) async {
    switch invocation {
    case let launch as LaunchApp:
      BirdLog.info(.glasses, "voice launch — answering Meta AI")
      // Answered before it is yielded: Meta AI is waiting on this, and what the app
      // does with the launch is not Meta AI's wait to sit through.
      if await launch.responseHandle.sendSuccess(actionOutput: nil) == false {
        BirdLog.warning(.glasses, "voice launch — the answer did not deliver")
      }
      continuation.yield(.launch)
    default:
      BirdLog.debug(.glasses, "voice — ignored \(String(describing: invocation))")
    }
  }
}

/// How long ``DatGlassesVoiceRepository/withChannelClosed(_:)`` waits for the lease to clear —
/// twenty polls of fifty milliseconds, the same second the session repository gives its own leases.
private let closeChannelPolls = 20
private let closeChannelPollMillis = 50
