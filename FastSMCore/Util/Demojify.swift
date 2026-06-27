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

/// Emoji-removal preferences for post text and display names.
public struct EmojiPrefs: Equatable, Sendable {
    public var post: EmojiRemoval
    public var name: EmojiRemoval

    public init(post: EmojiRemoval = .none, name: EmojiRemoval = .none) {
        self.post = post
        self.name = name
    }

    public static let none = EmojiPrefs()
}

/// Compiled once; matches Mastodon custom emoji shortcodes like `:blobcat_hug:`.
private let customEmojiRegex = try! NSRegularExpression(pattern: ":[A-Za-z0-9_]+:")

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
}
