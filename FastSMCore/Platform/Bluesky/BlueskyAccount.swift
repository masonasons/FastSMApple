//
//  BlueskyAccount.swift
//  FastSMCore
//
//  SocialAccount implementation for Bluesky. Port of
//  platforms/bluesky/account.py (Milestone 1 surface). Bluesky posts are always
//  public, cap at 300 characters, and have no content warnings.
//

import Foundation

public final class BlueskyAccount: SocialAccount, @unchecked Sendable {
    public let platform: Platform = .bluesky
    public private(set) var me: User
    public let maxChars: Int = 300
    public let features: PlatformFeatures
    public let credentials: BlueskyCredentials

    private let client: BlueskyClient

    init(credentials: BlueskyCredentials, session: BlueskySession, me: User, http: HTTP = HTTP()) {
        self.credentials = credentials
        self.me = me
        self.client = BlueskyClient(session: session, http: http)

        var features = PlatformFeatures()
        features.quotePosts = true
        // Visibility/CW/polls/lists/DMs unsupported on Bluesky in this pass.
        self.features = features
    }

    /// Interactive sign-in with a handle + app password.
    public static func signIn(
        identifier rawIdentifier: String,
        appPassword: String,
        serviceURL: URL = BlueskyAuth.defaultService,
        http: HTTP = HTTP()
    ) async throws -> BlueskyAccount {
        let identifier = BlueskyAuth.normalizeIdentifier(rawIdentifier)
        guard !identifier.isEmpty, !appPassword.isEmpty else {
            throw PlatformError.message("Enter your handle and an app password.")
        }
        let session = try await BlueskyAuth.createSession(
            identifier: identifier,
            appPassword: appPassword,
            serviceURL: serviceURL,
            http: http
        )
        let client = BlueskyClient(session: session, http: http)
        let me = try await client.getProfile(actor: session.did)
        let credentials = BlueskyCredentials(
            serviceURL: serviceURL,
            identifier: identifier,
            appPassword: appPassword,
            did: session.did,
            handle: session.handle
        )
        return BlueskyAccount(credentials: credentials, session: session, me: me, http: http)
    }

    /// Sign in fresh from persisted credentials (re-creates a session).
    public static func restore(credentials: BlueskyCredentials, http: HTTP = HTTP()) async throws -> BlueskyAccount {
        let session = try await BlueskyAuth.createSession(
            identifier: credentials.identifier,
            appPassword: credentials.appPassword,
            serviceURL: credentials.serviceURL,
            http: http
        )
        let client = BlueskyClient(session: session, http: http)
        let me = try await client.getProfile(actor: session.did)
        return BlueskyAccount(credentials: credentials, session: session, me: me, http: http)
    }

    public var defaultTimelines: [TimelineSource] { [.home, .notifications, .mentions] }
    public var supportedTimelines: [TimelineSource] { [.home, .notifications, .mentions, .favorites] }

    public func items(for source: TimelineSource, limit: Int, cursor: PageCursor) async throws -> TimelinePage {
        switch source {
        case .home:
            let (statuses, next) = try await client.getTimeline(limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .notifications:
            let (notifications, next) = try await client.listNotifications(limit: limit, cursor: cursor.token)
            return TimelinePage(items: notifications.map(TimelineItem.notification), nextCursor: next.map(PageCursor.token))
        case .mentions:
            let (statuses, next) = try await client.mentions(limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .thread(let statusID, _):
            let statuses = try await client.thread(uri: statusID)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .userPosts(let userID, _):
            let (statuses, next) = try await client.authorFeed(actor: userID, limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .followers(let userID, _):
            let (users, next) = try await client.followers(actor: userID, limit: limit, cursor: cursor.token)
            return TimelinePage(items: users.map(TimelineItem.user), nextCursor: next.map(PageCursor.token))
        case .following(let userID, _):
            let (users, next) = try await client.follows(actor: userID, limit: limit, cursor: cursor.token)
            return TimelinePage(items: users.map(TimelineItem.user), nextCursor: next.map(PageCursor.token))
        case .hashtag(let tag):
            let (statuses, next) = try await client.searchPosts(query: "#\(tag)", limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .favorites:
            let (statuses, next) = try await client.actorLikes(actor: me.id, limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .search(let query, let kind):
            switch kind {
            case .posts:
                let (statuses, next) = try await client.searchPosts(query: query, limit: limit, cursor: cursor.token)
                return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
            case .users:
                let (users, next) = try await client.searchActors(query: query, limit: limit, cursor: cursor.token)
                return TimelinePage(items: users.map(TimelineItem.user), nextCursor: next.map(PageCursor.token))
            }
        case .feed(let uri, _):
            let (statuses, next) = try await client.getFeed(uri: uri, limit: limit, cursor: cursor.token)
            return TimelinePage(statuses: statuses, nextCursor: next.map(PageCursor.token))
        case .local, .federated, .conversations, .bookmarks, .list, .trending, .remoteLocal, .remoteUser:
            throw PlatformError.message("\(source.title) isn't available on Bluesky.")
        }
    }

    public func homeMarker() async throws -> String? { nil }
    public func setHomeMarker(_ statusID: String) async throws {}
    public func openStream(onEvent: @escaping @Sendable (StreamEvent) -> Void) -> StreamConnection? { nil }

    // Bluesky posts are addressed by global AT-URIs, so no resolution is needed.
    public func resolve(_ status: Status) async throws -> Status { status }

    public func lists() async throws -> [TimelineList] { [] }
    public func savedFeeds() async throws -> [TimelineList] { try await client.savedFeeds() }

    @discardableResult
    public func post(_ draft: PostDraft) async throws -> Status? {
        try await client.post(draft)
    }

    @discardableResult
    public func editPost(_ id: String, draft: PostDraft) async throws -> Status? {
        throw PlatformError.message("Bluesky doesn't support editing posts.")
    }

    public func postSource(_ id: String) async throws -> PostSource? { nil }

    public func resolveUser(handle: String) async throws -> User {
        let actor = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return try await client.getProfile(actor: actor)
    }

    public func boost(_ statusID: String) async throws { try await client.repost(statusID: statusID) }
    public func unboost(_ statusID: String) async throws { try await client.unrepost(statusID: statusID) }
    public func favorite(_ statusID: String) async throws { try await client.like(statusID: statusID) }
    public func unfavorite(_ statusID: String) async throws { try await client.unlike(statusID: statusID) }

    public func follow(_ userID: String) async throws { try await client.follow(did: userID) }
    public func unfollow(_ userID: String) async throws { try await client.unfollow(did: userID) }
    public func mute(_ userID: String) async throws { try await client.mute(did: userID) }
    public func unmute(_ userID: String) async throws { try await client.unmute(did: userID) }
    public func block(_ userID: String) async throws { try await client.block(did: userID) }
    public func unblock(_ userID: String) async throws { try await client.unblock(did: userID) }
    public func relationships(for userIDs: [String]) async throws -> [Relationship] {
        try await client.relationships(dids: userIDs)
    }
}
