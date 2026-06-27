//
//  DateParsing.swift
//  FastSMCore
//
//  Swift port of FastSM's `parse_datetime` (platforms/mastodon/models.py). Both
//  Mastodon and the AT Protocol emit ISO-8601 timestamps, sometimes with
//  fractional seconds and sometimes with a "Z" suffix.
//

import Foundation

public enum DateParsing {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parse an ISO-8601 timestamp, tolerating presence/absence of fractional
    /// seconds. Returns nil if the string can't be parsed.
    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return withFractional.date(from: value) ?? withoutFractional.date(from: value)
    }
}
