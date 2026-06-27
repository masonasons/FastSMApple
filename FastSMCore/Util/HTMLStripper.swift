//
//  HTMLStripper.swift
//  FastSMCore
//
//  Swift port of FastSM's `strip_html` (platforms/mastodon/models.py). Mastodon
//  serves status content as HTML; we need clean plain text for display and for
//  VoiceOver. We deliberately avoid NSAttributedString's HTML importer because
//  it is slow and must run on the main thread.
//

import Foundation

public enum HTMLStripper {
    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")
    // Block-level closers and <br> become spaces so text doesn't run together.
    private static let blockRegex = try! NSRegularExpression(
        pattern: "</(p|div)>|<br\\s*/?>",
        options: [.caseInsensitive]
    )
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+")

    /// Strip HTML tags and decode entities, preserving spacing for block
    /// elements. Inline elements (e.g. `<span>`) are removed without adding
    /// spaces — Mastodon wraps URL fragments in spans, and inserting spaces
    /// there would break links (`https:// example.com`).
    public static func strip(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = replace(blockRegex, in: html, with: " ")
        text = replace(tagRegex, in: text, with: "")
        text = decodeEntities(text)
        text = replace(whitespaceRegex, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ regex: NSRegularExpression, in string: String, with template: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    /// Decode HTML entities (named + numeric). Covers the entities Mastodon and
    /// Bluesky actually emit; falls through unknown entities unchanged.
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]
            guard char == "&" else {
                result.append(char)
                index = string.index(after: index)
                continue
            }

            // Find the terminating ';' within a reasonable window.
            guard let semicolon = string[index...].firstIndex(of: ";"),
                  string.distance(from: index, to: semicolon) <= 10 else {
                result.append(char)
                index = string.index(after: index)
                continue
            }

            let entityBody = String(string[string.index(after: index)..<semicolon])
            if let decoded = decodeEntityBody(entityBody) {
                result.append(decoded)
                index = string.index(after: semicolon)
            } else {
                result.append(char)
                index = string.index(after: index)
            }
        }
        return result
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°",
    ]

    private static func decodeEntityBody(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let numberPart = body.dropFirst()
            let scalarValue: UInt32?
            if numberPart.first == "x" || numberPart.first == "X" {
                scalarValue = UInt32(numberPart.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(numberPart, radix: 10)
            }
            if let value = scalarValue, let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
            return nil
        }
        return namedEntities[body]
    }
}
