//
//  Demojify.swift
//  FastSMCore
//
//  Optional emoji removal for displayed text and names (OG FastSM "demojify").
//  Two independent, granular controls (post text vs display names), each able to
//  strip standard unicode emoji, Mastodon custom `:shortcode:` emoji, or both.
//

import Foundation

/// What kind of emoji to strip from a piece of text.
public enum EmojiRemoval: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case unicode    // 😀 standard unicode emoji
    case mastodon   // :shortcode: custom emoji
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "Off"
        case .unicode: return "Unicode emoji"
        case .mastodon: return "Custom (:shortcode:)"
        case .both: return "Both"
        }
    }

    var stripsUnicode: Bool { self == .unicode || self == .both }
    var stripsMastodon: Bool { self == .mastodon || self == .both }
}

/// Text-display preferences threaded into the presenters: emoji removal for post
/// text and display names, plus how many leading @mentions to keep in a post.
public struct EmojiPrefs: Equatable, Sendable {
    public var post: EmojiRemoval
    public var name: EmojiRemoval
    /// Max leading @mentions to show in a post before truncating (0 = show all).
    public var maxMentions: Int

    public init(post: EmojiRemoval = .none, name: EmojiRemoval = .none, maxMentions: Int = 0) {
        self.post = post
        self.name = name
        self.maxMentions = maxMentions
    }

    public static let none = EmojiPrefs()
}

/// Compiled once; matches Mastodon custom emoji shortcodes like `:blobcat_hug:`.
private let customEmojiRegex = try! NSRegularExpression(pattern: ":[A-Za-z0-9_]+:")

private let handlePattern = "@[A-Za-z0-9_]+(?:@[A-Za-z0-9_.\\-]+)?"
private let leadingMentionsRegex = try! NSRegularExpression(pattern: "^(?:\(handlePattern)(?:\\s+|$))+")
private let singleHandleRegex = try! NSRegularExpression(pattern: handlePattern)

public extension String {
    /// Strip standard unicode emoji and collapse any doubled spaces.
    func demojified() -> String {
        guard unicodeScalars.contains(where: { $0.properties.isEmoji }) else { return self }
        var result = ""
        result.reserveCapacity(count)
        for scalar in unicodeScalars {
            // Drop emoji and the variation/zero-width joiners that compose them,
            // but keep plain ASCII digits/# that merely *can* form keycaps.
            let isEmoji = scalar.properties.isEmoji && (scalar.properties.isEmojiPresentation || scalar.value > 0x2000)
            let isJoiner = scalar.value == 0x200D || scalar.value == 0xFE0F
            if isEmoji || isJoiner { continue }
            result.unicodeScalars.append(scalar)
        }
        return result.collapsedSpaces()
    }

    /// Strip Mastodon custom emoji shortcodes (`:name:`).
    func decustomized() -> String {
        guard contains(":") else { return self }
        let range = NSRange(startIndex..., in: self)
        let stripped = customEmojiRegex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
        return stripped.collapsedSpaces()
    }

    /// Apply the requested emoji removal.
    func strippingEmoji(_ mode: EmojiRemoval) -> String {
        guard mode != .none else { return self }
        var s = self
        if mode.stripsMastodon { s = s.decustomized() }
        if mode.stripsUnicode { s = s.demojified() }
        return s
    }

    private func collapsedSpaces() -> String {
        replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Collapse a long leading run of @mentions (e.g. a big reply chain) down to
    /// the first `max`, replacing the rest with "and N others". `max <= 0` keeps
    /// everything. Mentions elsewhere in the text are untouched.
    func truncatingLeadingMentions(max: Int) -> String {
        guard max > 0 else { return self }
        let full = NSRange(startIndex..., in: self)
        guard let runMatch = leadingMentionsRegex.firstMatch(in: self, range: full),
              let runRange = Range(runMatch.range, in: self) else { return self }
        let run = String(self[runRange])
        let handles = singleHandleRegex
            .matches(in: run, range: NSRange(run.startIndex..., in: run))
            .compactMap { Range($0.range, in: run).map { String(run[$0]) } }
        guard handles.count > max else { return self }
        let kept = handles.prefix(max).joined(separator: " ")
        let others = handles.count - max
        let rest = self[runRange.upperBound...]
        return "\(kept) and \(others) other\(others == 1 ? "" : "s") \(rest)"
    }
}
