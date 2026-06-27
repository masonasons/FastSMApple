//
//  SpeechSettings.swift
//  FastSMCore
//
//  User-configurable ordering + on/off for the pieces of information VoiceOver
//  reads for a post and for a user. Edited in Settings → Speech; consumed by
//  StatusPresenter / UserPresenter.
//

import Foundation

/// A field that can be spoken for a post, in the order it appears.
public enum StatusSpeechField: String, Codable, CaseIterable, Sendable, Hashable {
    case boostedBy, author, handle, contentWarning, text, quote, media, poll, time, stats, favorited, boosted, visibility, replyIndicator, source

    public var displayName: String {
        switch self {
        case .boostedBy: return "Boosted by"
        case .author: return "Author name"
        case .handle: return "Handle (@user)"
        case .contentWarning: return "Content warning"
        case .text: return "Post text"
        case .quote: return "Quoted post"
        case .media: return "Media / attachments"
        case .poll: return "Poll"
        case .time: return "Time"
        case .stats: return "Reply / boost / favorite counts"
        case .favorited: return "Favorited state"
        case .boosted: return "Boosted state"
        case .visibility: return "Visibility"
        case .replyIndicator: return "Reply indicator"
        case .source: return "Posting app / source"
        }
    }
}

/// A field that can be spoken for a user row.
public enum UserSpeechField: String, Codable, CaseIterable, Sendable, Hashable {
    case author, handle, bot, locked, bio, followers, following, posts

    public var displayName: String {
        switch self {
        case .author: return "Display name"
        case .handle: return "Handle (@user)"
        case .bot: return "Bot indicator"
        case .locked: return "Locked indicator"
        case .bio: return "Bio"
        case .followers: return "Followers count"
        case .following: return "Following count"
        case .posts: return "Posts count"
        }
    }
}

/// One orderable, toggleable field.
public struct SpeechItem<Field: Codable & Equatable & Sendable & Hashable>: Codable, Equatable, Sendable, Hashable {
    public var field: Field
    public var enabled: Bool
    public init(_ field: Field, _ enabled: Bool = true) {
        self.field = field
        self.enabled = enabled
    }
}

public struct SpeechSettings: Codable, Sendable, Equatable {
    public var status: [SpeechItem<StatusSpeechField>]
    public var user: [SpeechItem<UserSpeechField>]

    public init(status: [SpeechItem<StatusSpeechField>], user: [SpeechItem<UserSpeechField>]) {
        self.status = status
        self.user = user
    }

    /// Matches the original hard-coded VoiceOver order; a few extra fields are
    /// available but off by default.
    public static let `default` = SpeechSettings(
        status: [
            SpeechItem(.boostedBy), SpeechItem(.author), SpeechItem(.handle, false),
            SpeechItem(.contentWarning), SpeechItem(.text), SpeechItem(.quote),
            SpeechItem(.media), SpeechItem(.poll), SpeechItem(.replyIndicator, false),
            SpeechItem(.time), SpeechItem(.stats), SpeechItem(.favorited),
            SpeechItem(.boosted), SpeechItem(.visibility, false), SpeechItem(.source, false),
        ],
        user: [
            SpeechItem(.author), SpeechItem(.handle), SpeechItem(.bot), SpeechItem(.locked),
            SpeechItem(.bio), SpeechItem(.followers), SpeechItem(.following, false),
            SpeechItem(.posts, false),
        ]
    )

    /// Guarantee every field appears exactly once: keep saved order, drop
    /// dupes/unknowns, and append any fields added in a newer version (using the
    /// default's enabled state) so old settings files keep working.
    public func normalized() -> SpeechSettings {
        SpeechSettings(
            status: Self.merge(status, defaults: Self.default.status),
            user: Self.merge(user, defaults: Self.default.user)
        )
    }

    private static func merge<F>(_ items: [SpeechItem<F>], defaults: [SpeechItem<F>]) -> [SpeechItem<F>] {
        var result: [SpeechItem<F>] = []
        var seen = Set<F>()
        for item in items where !seen.contains(item.field) {
            result.append(item)
            seen.insert(item.field)
        }
        for item in defaults where !seen.contains(item.field) {
            result.append(item)
            seen.insert(item.field)
        }
        return result
    }
}

/// The current speech configuration, read by the presenters. Updated by
/// SettingsStore whenever settings load or change. (UI-thread read-mostly.)
public enum SpeechConfig {
    public static var current: SpeechSettings = .default
}
