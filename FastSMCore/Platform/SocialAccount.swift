//
//  SocialAccount.swift
//  FastSMCore
//
//  Async port of FastSM's `PlatformAccount` ABC (platforms/base.py). Each
//  platform (Mastodon, Bluesky) implements this. Milestone 1 only requires the
//  home timeline + posting + boost/favorite surface; the remaining methods from
//  base.py are intentionally deferred to later milestones.
//

import Foundation

/// Capability flags, mirroring the `supports_*` booleans on `PlatformAccount`.
public struct PlatformFeatures: Sendable, Equatable {
    public var visibility: Bool = false
    public var contentWarning: Bool = false
    public var quotePosts: Bool = false
    public var polls: Bool = false
    public var lists: Bool = false
    public var directMessages: Bool = false
    public var mediaAttachments: Bool = false
    public var scheduling: Bool = false
    public var editing: Bool = false
    /// Per-account boost/reblog hiding (Mastodon `follow` with reblogs:false).
    public var hideBoosts: Bool = false

    public init() {}
}

/// An opaque pagination cursor. Mastodon paginates by `max_id`; Bluesky uses an
/// opaque `cursor` string. A timeline fetch returns the next cursor to use.
public enum PageCursor: Sendable, Equatable {
    case start
    /// Mastodon: fetch statuses older than this status id.
    case maxID(String)
    /// Bluesky: opaque cursor token.
    case token(String)

    public var maxID: String? {
        if case .maxID(let id) = self { return id }
        return nil
    }

    public var token: String? {
        if case .token(let value) = self { return value }
        return nil
    }
}

/// A page of timeline items plus the cursor for the following page.
public struct TimelinePage: Sendable {
    public var items: [TimelineItem]
    public var nextCursor: PageCursor?

    public init(items: [TimelineItem], nextCursor: PageCursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    /// Convenience for status-only timelines.
    public init(statuses: [Status], nextCursor: PageCursor?) {
        self.items = statuses.map(TimelineItem.status)
        self.nextCursor = nextCursor
    }
}

/// The authenticated user's relationship to another account, for labeling
/// Follow/Unfollow/Mute/Block actions. Mirrors Mastodon's relationship object.
public struct Relationship: Sendable, Hashable, Identifiable {
    public let id: String          // the other account's id
    public var following: Bool
    public var followedBy: Bool
    public var muting: Bool
    public var blocking: Bool
    public var showingReblogs: Bool // false == boosts hidden for this account

    public init(id: String, following: Bool = false, followedBy: Bool = false,
                muting: Bool = false, blocking: Bool = false, showingReblogs: Bool = true) {
        self.id = id
        self.following = following
        self.followedBy = followedBy
        self.muting = muting
        self.blocking = blocking
        self.showingReblogs = showingReblogs
    }
}

/// An action that can be applied to one or many users (single row or batch).
public enum UserAction: String, CaseIterable, Sendable, Identifiable {
    case follow, unfollow, mute, unmute, block, unblock, hideBoosts, showBoosts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .follow: return "Follow"
        case .unfollow: return "Unfollow"
        case .mute: return "Mute"
        case .unmute: return "Unmute"
        case .block: return "Block"
        case .unblock: return "Unblock"
        case .hideBoosts: return "Hide Boosts"
        case .showBoosts: return "Show Boosts"
        }
    }

    /// Only relevant on platforms with per-account boost hiding (Mastodon).
    public var needsHideBoosts: Bool { self == .hideBoosts || self == .showBoosts }

    /// The actions offered for a given account (drops boost hiding where unsupported).
    public static func applicable(to account: SocialAccount) -> [UserAction] {
        account.features.hideBoosts ? allCases : allCases.filter { !$0.needsHideBoosts }
    }
}

/// A user-defined list (Mastodon lists), for opening as a timeline.
public struct TimelineList: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// The editable source of a post (Mastodon /source) — the original text and
/// content warning, before HTML rendering.
public struct PostSource: Sendable {
    public var text: String
    public var spoilerText: String
    public init(text: String, spoilerText: String) {
        self.text = text
        self.spoilerText = spoilerText
    }
}

/// A poll to attach to a new post (Mastodon).
public struct PollDraft: Sendable {
    public var options: [String]
    public var multiple: Bool
    public var expiresInSeconds: Int

    public init(options: [String], multiple: Bool = false, expiresInSeconds: Int = 86_400) {
        self.options = options
        self.multiple = multiple
        self.expiresInSeconds = expiresInSeconds
    }
}

/// Parameters for composing a new post.
public struct PostDraft: Sendable {
    public var text: String
    public var replyToID: String?
    public var visibility: Visibility?
    public var spoilerText: String?
    /// The status being quoted, if this is a quote post.
    public var quotedStatusID: String?
    /// ISO language code for the post (e.g. "en").
    public var language: String?
    /// An attached poll (Mastodon only).
    public var poll: PollDraft?
    /// When set, schedule the post for this time instead of posting now
    /// (Mastodon only). No status is returned for scheduled posts.
    public var scheduledAt: Date?

    public init(
        text: String,
        replyToID: String? = nil,
        visibility: Visibility? = nil,
        spoilerText: String? = nil,
        quotedStatusID: String? = nil,
        language: String? = nil,
        poll: PollDraft? = nil,
        scheduledAt: Date? = nil
    ) {
        self.text = text
        self.replyToID = replyToID
        self.visibility = visibility
        self.spoilerText = spoilerText
        self.quotedStatusID = quotedStatusID
        self.language = language
        self.poll = poll
        self.scheduledAt = scheduledAt
    }
}

/// A logged-in account for one platform. Implementations are reference types so
/// the apps can hold a stable identity per account.
public protocol SocialAccount: AnyObject, Sendable {
    var platform: Platform { get }
    /// The authenticated user.
    var me: User { get }
    /// Maximum characters allowed in a post (Mastodon 500, Bluesky 300).
    var maxChars: Int { get }
    /// Capability flags for conditional UI.
    var features: PlatformFeatures { get }

    /// A stable identifier for this account: `platform:userID`. Used as a
    /// dictionary key and for persistence.
    var accountKey: String { get }

    /// Sources shown by default in the UI, in display order.
    var defaultTimelines: [TimelineSource] { get }
    /// Standing feeds this account also supports on demand (e.g. Local /
    /// Federated). Parameterized sources (threads, user lists) are always allowed.
    var supportedTimelines: [TimelineSource] { get }

    /// Refresh server-derived configuration (e.g. the instance character limit).
    /// Default is a no-op for platforms with a fixed limit.
    func loadConfiguration() async

    // MARK: Timeline

    /// Load a page of items for any source (feed, thread, user's posts, a
    /// followers/following list, …).
    func items(for source: TimelineSource, limit: Int, cursor: PageCursor) async throws -> TimelinePage

    // MARK: Actions

    /// Create a post. Returns the created status, or nil when there is no
    /// immediate status (e.g. a scheduled Mastodon post).
    @discardableResult
    func post(_ draft: PostDraft) async throws -> Status?

    /// Edit an existing post (Mastodon). Returns the updated status.
    @discardableResult
    func editPost(_ id: String, draft: PostDraft) async throws -> Status?

    /// The editable source (original text + CW) of a post, if available.
    func postSource(_ id: String) async throws -> PostSource?

    /// Resolve a handle (e.g. "@alice@example.social" or "alice.bsky.social") to
    /// a user, for spawning that user's timeline.
    func resolveUser(handle: String) async throws -> User

    /// The user's lists (empty if the platform/account has none).
    func lists() async throws -> [TimelineList]

    /// The user's saved custom feeds (Bluesky); empty elsewhere. `id` is the feed
    /// URI, used with `.feed`.
    func savedFeeds() async throws -> [TimelineList]

    /// The server-synced home-timeline read position (Mastodon markers). Returns
    /// the last-read status id, or nil if unsupported.
    func homeMarker() async throws -> String?
    func setHomeMarker(_ statusID: String) async throws

    /// Open a real-time stream (Mastodon), delivering events until stopped.
    /// Returns nil if the platform doesn't support streaming.
    func openStream(onEvent: @escaping @Sendable (StreamEvent) -> Void) -> StreamConnection?

    /// Map a status to one this account can interact with. For posts fetched from
    /// a remote instance (`status.instanceURL != nil`), resolves the post to the
    /// local copy on the user's own instance. Returns the status unchanged when
    /// no resolution is needed.
    func resolve(_ status: Status) async throws -> Status

    func boost(_ statusID: String) async throws
    func unboost(_ statusID: String) async throws
    func favorite(_ statusID: String) async throws
    func unfavorite(_ statusID: String) async throws

    // MARK: User actions

    func follow(_ userID: String) async throws
    func unfollow(_ userID: String) async throws
    func mute(_ userID: String) async throws
    func unmute(_ userID: String) async throws
    func block(_ userID: String) async throws
    func unblock(_ userID: String) async throws
    /// Hide or show this account's boosts/reposts in your home feed (Mastodon).
    func setBoostsHidden(_ hidden: Bool, for userID: String) async throws
    /// The relationships to a set of accounts, for labeling actions.
    func relationships(for userIDs: [String]) async throws -> [Relationship]
}

public extension SocialAccount {
    var accountKey: String { "\(platform.rawValue):\(me.id)" }
    func loadConfiguration() async {}

    // Default to "unsupported" so platforms only implement what they offer.
    func follow(_ userID: String) async throws { throw PlatformError.message("Following isn't supported here.") }
    func unfollow(_ userID: String) async throws { throw PlatformError.message("Unfollowing isn't supported here.") }
    func mute(_ userID: String) async throws { throw PlatformError.message("Muting isn't supported here.") }
    func unmute(_ userID: String) async throws { throw PlatformError.message("Unmuting isn't supported here.") }
    func block(_ userID: String) async throws { throw PlatformError.message("Blocking isn't supported here.") }
    func unblock(_ userID: String) async throws { throw PlatformError.message("Unblocking isn't supported here.") }
    func setBoostsHidden(_ hidden: Bool, for userID: String) async throws { throw PlatformError.message("Hiding boosts isn't supported here.") }
    func relationships(for userIDs: [String]) async throws -> [Relationship] { [] }

    /// Dispatch a `UserAction` to the matching method.
    func perform(_ action: UserAction, on userID: String) async throws {
        switch action {
        case .follow: try await follow(userID)
        case .unfollow: try await unfollow(userID)
        case .mute: try await mute(userID)
        case .unmute: try await unmute(userID)
        case .block: try await block(userID)
        case .unblock: try await unblock(userID)
        case .hideBoosts: try await setBoostsHidden(true, for: userID)
        case .showBoosts: try await setBoostsHidden(false, for: userID)
        }
    }
}

/// Errors surfaced by platform clients.
public enum PlatformError: Error, LocalizedError {
    case notAuthenticated
    case http(status: Int, body: String)
    case decoding(String)
    case network(String)
    case invalidInstance
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in."
        case .http(let status, let body):
            return "Server error \(status): \(body)"
        case .decoding(let detail):
            return "Couldn't read the server response. \(detail)"
        case .network(let detail):
            return "Network error. \(detail)"
        case .invalidInstance:
            return "That doesn't look like a valid server address."
        case .message(let text):
            return text
        }
    }
}
