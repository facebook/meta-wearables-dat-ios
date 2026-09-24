/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  JournalFormatting.swift
//  birdspotter
//

import Foundation

/// Turns an outing's stored facts into the strings the Journal prints.
///
/// Display, not data: the database keeps degrees, epoch milliseconds and raw enums, and the
/// UI is where those become "WNW", "23 Jul 2026" and "14 min". Kept in one place, and out
/// of the views, so the Journal row and the detail screen word the same fact the same way —
/// and so the pieces with real logic, ``bearingLabel(_:)`` and ``durationLabel(_:)``, have
/// somewhere to be tested.
///
/// Dates use fixed patterns rather than the system's localized ordering, because the demo runs
/// two phones side by side and "23 Jul 2026" has to read identically on each.
enum JournalFormatting {

  /// The sixteen points of the compass, N at index 0, clockwise. Spelled out rather than
  /// localized — the label a bearing lands on has to match on both phones.
  private static let compassPoints = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
  ]

  /// A heading in degrees (0–360, true north) as a 16-point compass label — "WNW".
  ///
  /// 22.5° buckets, because that is the precision a magnetometer actually has: the values
  /// are routinely off by tens of degrees near metal, so a degree readout would imply a
  /// certainty that isn't there.
  ///
  /// The value is stored already normalized, but this folds again so a caller passing a raw
  /// reading still gets a sane answer. Rounding is half-away-from-zero, which for a bearing —
  /// normalized, so never negative — is the same thing as half-up.
  static func bearingLabel(_ degrees: Double) -> String {
    let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
      .truncatingRemainder(dividingBy: 360)
    let index = Int((normalized / 22.5).rounded()) % compassPoints.count
    return compassPoints[index]
  }

  /// Where the observer was looking, as one of the five strata.
  ///
  /// **The only place a ``GazeContext`` becomes words**, on either screen — the live session's
  /// chip over the viewfinder reads out of here too. That is the point of it living in one
  /// function: the chip used to make its own strings and said *Horizon* where this said *Eye
  /// level*, which is one stratum wearing two names depending on which screen you were on.
  static func gazeLabel(_ gaze: GazeContext) -> String {
    switch gaze {
    case .overhead: "Overhead"
    case .canopy: "Canopy"
    case .horizon: "Horizon"
    case .understory: "Understory"
    case .ground: "Ground"
    }
  }

  /// What shape the outing took — the detail page's eyebrow when no bird leads it.
  static func kindLabel(_ kind: OutingKind) -> String {
    switch kind {
    case .live: "Live outing"
    case .manual: "Wizard entry"
    }
  }

  /// Which device made a capture.
  static func sourceLabel(_ source: CaptureSource) -> String {
    switch source {
    case .glasses: "Glasses"
    case .phone: "Phone"
    }
  }

  /// A 0–1 confidence as a whole per-cent — "87%".
  static func confidenceLabel(_ confidence: Double) -> String {
    "\(Int((confidence * 100).rounded()))%"
  }

  /// An outing's length — "14 min", "1 hr 5 min". Whole minutes, rounded up, floored at
  /// one: the Journal's clock is a memory cue, and "0 min" is not a length anyone stood
  /// outside for. Integer arithmetic only, so the two platforms cannot round apart.
  static func durationLabel(_ durationMs: Int64) -> String {
    let totalMinutes = max((durationMs + 59_999) / 60_000, 1)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours <= 0 { return "\(totalMinutes) min" }
    if minutes <= 0 { return "\(hours) hr" }
    return "\(hours) hr \(minutes) min"
  }

  /// A `wizardAnswer` value as the detail page prints it, per trait: `size`'s digit
  /// becomes "4 of 7" (the sparrow-to-goose scale), `colors` and `behavior` unfold their
  /// SCREAMING_SNAKE tokens — "BLACK,RED" to "Black, red", "ON_FENCE_OR_WIRE" to
  /// "On fence or wire".
  static func wizardAnswerLabel(_ trait: WizardTrait, _ value: String) -> String {
    switch trait {
    case .size:
      return "\(value) of 7"
    case .colors:
      let words = value.split(separator: ",")
        .filter { !$0.isEmpty }
        .map { tokenWords(String($0)) }
        .joined(separator: ", ")
      return capitalizeFirst(words)
    case .behavior:
      return capitalizeFirst(tokenWords(value))
    }
  }

  /// The row label over a wizard answer — "Size", "Colors", "Behavior".
  static func wizardTraitLabel(_ trait: WizardTrait) -> String {
    switch trait {
    case .size: "Size"
    case .colors: "Colors"
    case .behavior: "Behavior"
    }
  }

  /// "BLACK" → "black", "ON_FENCE_OR_WIRE" → "on fence or wire". ASCII fold: enum tokens
  /// are ASCII by contract, so a locale-sensitive fold would be wrong here.
  private static func tokenWords(_ token: String) -> String {
    token.trimmingCharacters(in: .whitespaces)
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
  }

  private static func capitalizeFirst(_ words: String) -> String {
    guard let first = words.first else { return words }
    return first.uppercased() + words.dropFirst()
  }

  /// "39.1031, -84.5120" — the stamped point, fixed to four decimals (~11 m), which is all a
  /// phone fix is good for and all the map needs. `String(format:)` is locale-independent (a dot
  /// decimal), so the digits don't shift with the device's region.
  static func coordinates(_ coordinate: Coordinate) -> String {
    String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
  }

  /// "23 Jul 2026" — the date a Journal row prints.
  static func date(_ epochMs: Int64) -> String {
    dateFormatter.string(from: dateValue(epochMs))
  }

  /// "23 Jul 2026 at 7:14 AM" — the fuller stamp the detail screen prints.
  static func dateTime(_ epochMs: Int64) -> String {
    dateTimeFormatter.string(from: dateValue(epochMs))
  }

  /// A stable, sortable bucket for a timestamp's civil month — "2026-07".
  ///
  /// The bucketing that ``JournalViewModel/groupByMonth(_:calendar:)`` runs on, so it takes
  /// the same `calendar` seam a test pins to a fixed timezone.
  static func monthKey(_ epochMs: Int64, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month], from: dateValue(epochMs))
    return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
  }

  /// The heading over a month's outings — "July 2026".
  static func monthTitle(_ epochMs: Int64, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = calendar.locale ?? .current
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: dateValue(epochMs))
  }

  private static func dateValue(_ epochMs: Int64) -> Date {
    Date(timeIntervalSince1970: Double(epochMs) / 1000)
  }

  /// Fixed pattern rather than a localized style, so the day/month/year order is the same
  /// wherever the phone is set. The month name still localizes.
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "d MMM yyyy"
    return formatter
  }()

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
    return formatter
  }()
}
