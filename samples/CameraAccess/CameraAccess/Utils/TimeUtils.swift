/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TimeUtils.swift
//
// Utility types for managing time limits in streaming sessions.
//

import Foundation

enum StreamTimeLimit: Equatable {
    case noLimit
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case custom(TimeInterval)
    
    var durationInSeconds: TimeInterval? {
        switch self {
        case .noLimit:
            return nil
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 5 * 60
        case .tenMinutes:
            return 10 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .oneHour:
            return 60 * 60
        case .custom(let seconds):
            return seconds
        }
    }
    
    var isTimeLimited: Bool {
        return durationInSeconds != nil
    }
    
    var displayName: String {
        switch self {
        case .noLimit:
            return "No Limit"
        case .oneMinute:
            return "1 Minute"
        case .fiveMinutes:
            return "5 Minutes"
        case .tenMinutes:
            return "10 Minutes"
        case .thirtyMinutes:
            return "30 Minutes"
        case .oneHour:
            return "1 Hour"
        case .custom(let seconds):
            let minutes = Int(seconds) / 60
            return "\(minutes) Minutes"
        }
    }
}

// MARK: - Time Formatting Helpers

extension TimeInterval {
    var formattedTime: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
