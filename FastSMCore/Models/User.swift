//
//  User.swift
//  FastSMCore
//
//  Port of FastSM's `UniversalUser` (models/user.py). A platform-agnostic
//  account/profile value type.
//

import Foundation

/// A platform-agnostic representation of a user/account.
public struct User: Identifiable, Codable, Sendable, Hashable {
    /// Platform-native id.
    public let id: String
    /// `username@instance` or just `username` (Mastodon `acct`, Bluesky handle).
    public var acct: String
    /// Local username without the instance part.
    public var username: String
    public var displayName: String
    /// Bio / description. May contain HTML (Mastodon) — strip for display.
    public var note: String
    public var avatarURL: URL?
    public var headerURL: URL?
    public var followersCount: Int
    public var followingCount: Int
    public var statusesCount: Int
    public var createdAt: Date?
    public var url: URL?
    public var bot: Bool
    public var locked: Bool
    public var platform: Platform

    public init(
        id: String,
        acct: String,
        username: String,
        displayName: String,
        note: String = "",
        avatarURL: URL? = nil,
        headerURL: URL? = nil,
        followersCount: Int = 0,
        followingCount: Int = 0,
        statusesCount: Int = 0,
        createdAt: Date? = nil,
        url: URL? = nil,
        bot: Bool = false,
        locked: Bool = false,
        platform: Platform
    ) {
        self.id = id
        self.acct = acct
        self.username = username
        self.displayName = displayName
        self.note = note
        self.avatarURL = avatarURL
        self.headerURL = headerURL
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount = statusesCount
        self.createdAt = createdAt
        self.url = url
        self.bot = bot
        self.locked = locked
        self.platform = platform
    }

    /// Best display name, falling back to the handle. Mirrors FastSM's
    /// `display_name or acct` fallback.
    public var bestName: String {
        displayName.isEmpty ? acct : displayName
    }

    // Equality/hashing by identity + platform, matching UniversalUser.__eq__.
    public static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id && lhs.platform == rhs.platform
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(platform)
    }
}
