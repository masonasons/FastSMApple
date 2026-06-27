//
//  QuoteText.swift
//  FastSMCore
//
//  When a post carries a quoted post, its body text often also contains the
//  quoted post's URL (a "RE: <url>" prefix, or the bare status URL appended).
//  Since the quote is presented separately, that URL is noise — strip it from
//  the display text. Mirrors FastSM for Windows (application.py process_status).
//

import Foundation

public enum QuoteText {
    /// Remove the quoted post's URL from a status's display text. `quotedURL` is
    /// the quoted post's own URL, when known.
    public static func stripped(_ text: String, quotedURL: URL?) -> String {
        var result = text

        // Leading "RE:/QT: <url>" reference.
        result = replacing(#"^(RE|QT):\s*https?://\S+\s*"#, in: result, options: [.caseInsensitive])

        // The exact quoted URL appended at the end.
        if let quoted = quotedURL?.absoluteString, !quoted.isEmpty {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(quoted) {
                result = String(trimmed.dropLast(quoted.count))
            }
        }

        // Any trailing Mastodon-style status URL (https://instance/@user/123).
        result = replacing(#"\s*https?://[^\s]+/@[^\s]+/\d+\s*$"#, in: result, options: [])

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ pattern: String, in text: String, options: NSRegularExpression.Options) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
