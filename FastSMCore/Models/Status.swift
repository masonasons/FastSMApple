//
//  Status.swift
//  FastSMCore
//
//  Port of FastSM's `UniversalStatus` (models/status.py). The central
//  platform-agnostic post type used throughout the apps.
//

import Foundation

/// Mastodon post visibility. Bluesky posts are always `.public`.
public enum Visibility: String, Codable, Sendable, CaseIterable {
    case `public`
    case unlisted
    case `private`
    case direct

    public var displayName: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Followers only"
        case .direct: return "Direct"
        }
    }
}

/// A platform-agnostic post/status.
///
/// A status can embed a `reblog`/`quote` of the same type; that recursion is
/// broken by the boxed `Reblog` value type defined at the bottom of this file.
public struct Status: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var account: User
    /// Raw HTML content (Mastodon). May be empty on Bluesky.
    public var content: String
    /// Clean, display-ready plain text (HTML stripped).
    public var text: String
    public var createdAt: Date

    public var favouritesCount: Int
    public var boostsCount: Int
    public var repliesCount: Int

    public var inReplyToID: String?
    public var inReplyToAccountID: String?

    /// The boosted/reblogged status, if this is a boost.
    public var reblog: Reblog?
    /// The quoted status, if any.
    public var quote: Reblog?

    public var mediaAttachments: [MediaAttachment]
    public var mentions: [Mention]
    public var url: URL?

    public var visibility: Visibility?
    /// Content warning / spoiler text (Mastodon).
    public var spoilerText: String?
    public var card: Card?
    public var poll: Poll?
    public var pinned: Bool

    /// Whether the current user has favourited this status.
    public var favourited: Bool
    /// Whether the current user has boosted this status.
    public var boosted: Bool
    /// Whether the current user has bookmarked this status.
    public var bookmarked: Bool

    /// Posting client/source app, e.g. "FastSM for Mac" (Mastodon, when present).
    public var applicationName: String?

    /// Set when this status was fetched directly from a remote instance (its `id`
    /// is local to that instance). Interactions must first resolve it to a local
    /// copy on the user's own instance. nil for normal (home-instance) statuses.
    public var instanceURL: String? = nil

    public var platform: Platform

    public init(
        id: String,
        account: User,
        content: String = "",
        text: String,
        createdAt: Date,
        favouritesCount: Int = 0,
        boostsCount: Int = 0,
        repliesCount: Int = 0,
        inReplyToID: String? = nil,
        inReplyToAccountID: String? = nil,
        reblog: Reblog? = nil,
        quote: Reblog? = nil,
        mediaAttachments: [MediaAttachment] = [],
        mentions: [Mention] = [],
        url: URL? = nil,
        visibility: Visibility? = nil,
        spoilerText: String? = nil,
        card: Card? = nil,
        poll: Poll? = nil,
        pinned: Bool = false,
        favourited: Bool = false,
        boosted: Bool = false,
        bookmarked: Bool = false,
        applicationName: String? = nil,
        platform: Platform
    ) {
        self.id = id
        self.account = account
        self.content = content
        self.text = text
        self.createdAt = createdAt
        self.favouritesCount = favouritesCount
        self.boostsCount = boostsCount
        self.repliesCount = repliesCount
        self.inReplyToID = inReplyToID
        self.inReplyToAccountID = inReplyToAccountID
        self.reblog = reblog
        self.quote = quote
        self.mediaAttachments = mediaAttachments
        self.mentions = mentions
        self.url = url
        self.visibility = visibility
        self.spoilerText = spoilerText
        self.card = card
        self.poll = poll
        self.pinned = pinned
        self.favourited = favourited
        self.boosted = boosted
        self.bookmarked = bookmarked
        self.applicationName = applicationName
        self.platform = platform
    }

    /// The status that should actually be displayed: the boosted status if this
    /// is a pure boost, otherwise self. Mirrors FastSM's reblog handling.
    public var displayStatus: Status {
        if let reblog { return reblog.status }
        return self
    }

    /// True when this status is a boost wrapper (reblog with no extra text).
    public var isBoost: Bool { reblog != nil }

    /// True when there is a content warning to honor.
    public var hasContentWarning: Bool {
        guard let spoilerText else { return false }
        return !spoilerText.isEmpty
    }

    /// Optimistically set the favourited state on the displayed status (the
    /// boosted status if this is a boost wrapper), adjusting the count.
    public mutating func setFavourited(_ value: Bool) {
        mutateDisplay { status in
            guard status.favourited != value else { return }
            status.favourited = value
            status.favouritesCount = max(0, status.favouritesCount + (value ? 1 : -1))
        }
    }

    /// Optimistically set the boosted state on the displayed status.
    public mutating func setBoosted(_ value: Bool) {
        mutateDisplay { status in
            guard status.boosted != value else { return }
            status.boosted = value
            status.boostsCount = max(0, status.boostsCount + (value ? 1 : -1))
        }
    }

    /// Optimistically set the bookmarked state on the displayed status.
    /// (Bookmarks have no public count.)
    public mutating func setBookmarked(_ value: Bool) {
        mutateDisplay { status in status.bookmarked = value }
    }

    private mutating func mutateDisplay(_ body: (inout Status) -> Void) {
        if let reblog {
            var inner = reblog.status
            body(&inner)
            self.reblog = Reblog(inner)
        } else {
            body(&self)
        }
    }
}

/// A boxed `Status` used for `reblog`/`quote`. Modeled as an `indirect enum`
/// so `Status` can transitively contain another `Status` without becoming an
/// infinitely-sized value type.
public indirect enum Reblog: Codable, Sendable, Hashable {
    case wrap(Status)

    public init(_ status: Status) { self = .wrap(status) }

    public var status: Status {
        switch self {
        case .wrap(let status): return status
        }
    }
}
