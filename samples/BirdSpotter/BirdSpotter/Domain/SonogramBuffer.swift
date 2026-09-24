/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  SonogramBuffer.swift
//  birdspotter
//

import Foundation

/// Columns per second of session — ``captureSampleRate`` over ``sonogramHop``, which is 62.5.
///
/// The rate that turns a moment into a column and back. It is **not** the session's clock: that is
/// ``SessionClock``, which goes on counting when the audio does not.
nonisolated let sonogramColumnsPerSecond = Double(captureSampleRate) / Double(sonogramHop)

/// Ten minutes of columns. Long past any demo, and only 9.6 MB — a byte per bin is plenty for
/// something that ends up as one pixel.
nonisolated let sonogramCapacity = 37_500

/// Somewhere to keep a session's sonogram: a ring of columns, written at one end and read from
/// anywhere still inside it.
///
/// **Bytes, not floats.** A magnitude becomes one pixel's brightness, and a pixel has 256 of those
/// — carrying 32-bit precision to a destination with 8 would cost four times the memory to draw
/// the identical strip.
///
/// Indices are **absolute**: column 0 is the first of the session and stays column 0 forever, even
/// after it has been overwritten. That is what lets an event's timestamp turn into a column number
/// with one multiplication, and it is why ``oldest`` exists — to say which of those numbers are
/// still answerable.
///
/// Not thread-safe, and not required to be: one producer appends on the session's task, and the
/// strip reads on the main actor after being told there is something new.
@MainActor
final class SonogramBuffer {

  private let capacity: Int
  private var data: [UInt8]

  /// One byte per column: how loud it was. The ring the **waveform** reading is drawn from — see
  /// ``waveform(from:columns:)``. Kept beside the bins rather than derived from them, because a
  /// column's loudness is a fact the analyzer measured and summing its magnitudes back up would
  /// be an estimate of a number we already had.
  private var levels: [UInt8]

  /// How many columns the session has produced, ever.
  private(set) var count = 0

  init(capacity: Int = sonogramCapacity) {
    self.capacity = capacity
    data = [UInt8](repeating: 0, count: capacity * sonogramBins)
    levels = [UInt8](repeating: 0, count: capacity)
  }

  /// The oldest column still in the ring. Below this, ``magnitude(column:bin:)`` answers zero.
  var oldest: Int { max(0, count - capacity) }

  func append(_ column: SonogramColumn) {
    let slot = (count % capacity) * sonogramBins
    for bin in 0..<sonogramBins {
      data[slot + bin] = UInt8(min(max(column.magnitudes[bin] * 255, 0), 255))
    }
    levels[count % capacity] = UInt8(min(max(column.level * 255, 0), 255))
    count += 1
  }

  /// Moves the write head forward to an absolute column, leaving silence behind it — what a gap
  /// in the audio looks like on the strip.
  ///
  /// ``append(_:)`` can only ever write at ``count``, so without this the columns either side of
  /// a dropout end up adjacent and the session reads as though the silence never happened.
  ///
  /// **The skipped columns are cleared, not merely stepped over.** This is a ring: the slots a
  /// gap passes over still hold whatever was written there a full buffer ago, and leaving them
  /// would draw ten-minute-old song inside the silence.
  ///
  /// Never moves backwards. A column that has been written is a column that happened, and audio
  /// running fractionally ahead of the clock is the harmless direction — see ``audioGapColumns``.
  func advance(to column: Int) {
    guard column > count else { return }
    // Anything more than a whole ring back is already unreachable, so clearing it would only
    // be clearing what this skip is about to overwrite.
    let first = max(count, column - capacity)
    for skipped in first..<column {
      let slot = (skipped % capacity) * sonogramBins
      for bin in 0..<sonogramBins { data[slot + bin] = 0 }
      levels[skipped % capacity] = 0
    }
    count = column
  }

  /// Forgets the session. A new one starts on an empty strip.
  ///
  /// **Two things keep this off the frame that opens the screen.** A buffer nobody has written to
  /// is already blank, so the first session of an app's life pays nothing at all; and the clear
  /// itself is one `update` rather than a loop, which is a `memset` where the loop was 9.6 million
  /// bounds-checked stores — enough, in a debug build, to be the hitch between tapping Real-Time
  /// and seeing it.
  func reset() {
    guard count > 0 else { return }
    count = 0
    data.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    levels.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
  }

  /// The magnitude at an absolute column, 0..1 — or zero for a column that has not happened yet
  /// or has already been overwritten. Out of range is silence rather than an error: the strip
  /// scrolls past both ends of the session and drawing needs an answer, not a trap.
  func magnitude(column: Int, bin: Int) -> Float {
    guard column >= oldest, column < count else { return 0 }
    let slot = (column % capacity) * sonogramBins
    return Float(data[slot + bin]) / 255
  }

  /// How loud an absolute column was, 0..1 — or zero for one that has not happened yet or has
  /// already been overwritten, on the same terms ``magnitude(column:bin:)`` answers.
  func level(column: Int) -> Float {
    guard column >= oldest, column < count else { return 0 }
    return Float(levels[column % capacity]) / 255
  }

  /// The visible window as 8-bit greyscale, row-major, `columns` wide and ``sonogramBins`` tall,
  /// lowest frequency at the **bottom** — which is how a sonogram is read, and the opposite of
  /// how a bitmap is stored.
  ///
  /// Building the whole window in one pass rather than asking per pixel is what keeps the strip
  /// cheap: one allocation and one loop per redraw, no matter how long the session has run.
  func window(from first: Int, columns: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: columns * sonogramBins)
    for x in 0..<columns {
      let column = first + x
      guard column >= oldest, column < count else { continue }
      let slot = (column % capacity) * sonogramBins
      for bin in 0..<sonogramBins {
        pixels[(sonogramBins - 1 - bin) * columns + x] = data[slot + bin]
      }
    }
    return pixels
  }

  /// The newest `columns` columns, averaged bin by bin — the spectrum the **live trace** is drawn
  /// from. See ``LiveWaveform``.
  ///
  /// **Averaged rather than simply the newest one, and this is the whole of the trace's
  /// smoothing.** A single column is 32 ms of a bird, and drawing it raw gives a shape that
  /// changes completely sixty times a second — legible as motion, illegible as a picture. Four
  /// columns is about a tenth of a second, which is roughly how long the eye wants a shape to
  /// hold still. Doing it here rather than in the drawing keeps the smoothing a fact about the
  /// *data* — one arithmetic mean, identical on both platforms — instead of an animation with a
  /// clock in it that the two apps would have to be trusted to run at the same rate.
  ///
  /// A session with nothing in it yet answers zeros, which is a flat trace.
  func recentBins(columns: Int) -> [Float] {
    var bins = [Float](repeating: 0, count: sonogramBins)
    let first = max(oldest, count - columns)
    guard first < count else { return bins }

    for column in first..<count {
      let slot = (column % capacity) * sonogramBins
      for bin in 0..<sonogramBins {
        bins[bin] += Float(data[slot + bin]) / 255
      }
    }
    let taken = Float(count - first)
    for bin in 0..<sonogramBins { bins[bin] /= taken }
    return bins
  }

  /// How loud the newest `columns` columns were, averaged — the trace's amplitude, smoothed over
  /// exactly the span ``recentBins(columns:)`` smooths the shape over.
  func recentLevel(columns: Int) -> Float {
    let first = max(oldest, count - columns)
    guard first < count else { return 0 }

    var total: Float = 0
    for column in first..<count { total += Float(levels[column % capacity]) / 255 }
    return total / Float(count - first)
  }

  // MARK: - Keeping it

  /// The strip as bytes: a header naming its shape, then every column's bins, then every
  /// column's level.
  ///
  /// **The greyscale, not a picture of it.** A rendered strip would bake in the palette and one
  /// chosen size; these are the numbers the analyzer measured, and every destination still
  /// rasterises them for itself at whatever width it has.
  ///
  /// Only the columns still in the ring are written, and ``oldest`` rides along, so absolute
  /// column numbers survive the round trip and an event's timestamp still lands where it did
  /// during the session.
  func encoded() -> Data {
    let first = oldest
    let kept = count - first

    var out = Data()
    out.reserveCapacity(sonogramHeaderBytes + kept * sonogramBins + kept)
    out.append(contentsOf: sonogramMagic)
    out.append(littleEndian: UInt16(sonogramFormatVersion))
    out.append(littleEndian: UInt16(sonogramBins))
    out.append(littleEndian: UInt32(first))
    out.append(littleEndian: UInt32(count))

    for column in first..<count {
      let slot = (column % capacity) * sonogramBins
      out.append(contentsOf: data[slot..<(slot + sonogramBins)])
    }
    for column in first..<count {
      out.append(levels[column % capacity])
    }
    return out
  }

  /// Rebuilds a strip written by ``encoded()``.
  ///
  /// **Nil is the ordinary answer, not an error.** Bytes that are not a strip, a version this
  /// build does not know, a bin count from before someone changed ``sonogramWindow``, or a file
  /// truncated by a crash all land here — and every one of them means the caller recomputes from
  /// the audio, which is what it did before this file existed. Nothing downstream has to tell
  /// those cases apart.
  static func decoded(from bytes: Data) -> SonogramBuffer? {
    guard bytes.count >= sonogramHeaderBytes else { return nil }
    let raw = [UInt8](bytes)
    guard Array(raw[0..<4]) == sonogramMagic,
      readLittleEndian16(raw, at: 4) == UInt16(sonogramFormatVersion),
      readLittleEndian16(raw, at: 6) == UInt16(sonogramBins)
    else { return nil }

    let first = Int(readLittleEndian32(raw, at: 8))
    let total = Int(readLittleEndian32(raw, at: 12))
    guard total >= first else { return nil }
    let kept = total - first
    // Nothing Save writes is longer than the live ring, and the bound is also what keeps the
    // size arithmetic below from overflowing on a corrupt header.
    guard kept <= sonogramCapacity else { return nil }
    guard raw.count == sonogramHeaderBytes + kept * sonogramBins + kept else { return nil }
    guard kept > 0 else { return SonogramBuffer(capacity: 1) }

    // Sized to exactly what was kept, which is what puts `oldest` back where it was: the ring
    // reports `count - capacity`, and capacity is the number of columns in the file.
    let buffer = SonogramBuffer(capacity: kept)
    let binsAt = sonogramHeaderBytes
    let levelsAt = binsAt + kept * sonogramBins
    for i in 0..<kept {
      let column = first + i
      let slot = (column % kept) * sonogramBins
      let source = binsAt + i * sonogramBins
      for bin in 0..<sonogramBins {
        buffer.data[slot + bin] = raw[source + bin]
      }
      buffer.levels[column % kept] = raw[levelsAt + i]
    }
    buffer.count = total
    return buffer
  }
}

/// Four bytes that say this is one of ours before anything reads a length off it — "BirdSpotter
/// SonoGram".
private let sonogramMagic: [UInt8] = Array("BSSG".utf8)

/// The layout's version. Bump it when the bytes after the header change meaning, and every strip
/// written by an older build is quietly recomputed instead of drawn wrong.
private let sonogramFormatVersion = 1

/// Magic, version, bins, oldest, count.
private let sonogramHeaderBytes = 16

private func readLittleEndian16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
  UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func readLittleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
  UInt32(bytes[offset])
    | (UInt32(bytes[offset + 1]) << 8)
    | (UInt32(bytes[offset + 2]) << 16)
    | (UInt32(bytes[offset + 3]) << 24)
}

private extension Data {

  /// Little-endian on both platforms, written out a byte at a time rather than reinterpreting
  /// memory — the host's own order is a fact about the phone, and this file is read by two.
  mutating func append(littleEndian value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
  }

  mutating func append(littleEndian value: UInt32) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8((value >> 16) & 0xFF))
    append(UInt8((value >> 24) & 0xFF))
  }
}
