//
//  RelativeDate.swift
//  FastSMCore
//
//  Compact relative timestamps for timeline rows ("5m", "2h", "3d") plus a
//  spoken, VoiceOver-friendly long form.
//

import Foundation

public enum RelativeDate {
    /// Compact form for dense lists: "now", "5m", "2h", "3d", "2w", or a short
    /// date for anything older.
    public static func compact(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return "now"
        case ..<3600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3600))h"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d"
        case ..<2_592_000:
            return "\(Int(seconds / 604_800))w"
        default:
            return shortDateFormatter.string(from: date)
        }
    }

    /// Long, spoken form for accessibility labels ("5 minutes ago").
    public static func spoken(_ date: Date, now: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
