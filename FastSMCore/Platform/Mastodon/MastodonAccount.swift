//
//  MastodonAccount.swift
//  FastSMCore
//
//  SocialAccount implementation for Mastodon. Port of
//  platforms/mastodon/account.py (Milestone 1 surface).
//

import Foundation

public final class MastodonAccount: SocialAccount, @unchecked Sendable {
    public let platform: Platform = .mastodon
    public private(set) var me: User
    private var _maxChars: Int
    public var maxChars: Int { _maxChars }
    public let features: PlatformFeatures
    public let credentials: MastodonCredentials

    private let client: MastodonClient

    public init(credentials: MastodonCredentials, me: User, maxChars: Int = 500) {
        self.credentials = credentials
        self.me = me
        self._maxChars = maxChars
        self.client = MastodonClient(credentials: credentials)

        var features = PlatformFeatures()
        features.visibility = true
        features.contentWarning = true
        features.quotePosts = true
        features.polls = true
        features.lists = true
        features.directMessages = true
        features.mediaAttachments = true
        features.scheduling = true
        features.editing = true
        features.hideBoosts = true
        self.features = features
    }

    public func loadConfiguration() async {
        if let max = try? await client.instanceMaxCharacters(), max > 0 {
            _maxChars = max
        }
    }

    public var defaultTimelines: [TimelineSource] { [.home, .notifications, .mentions, .conversations] }
    public var supportedTimelines: [TimelineSource] { [.home, .notifications, .mentions, .conversations, .local, .federated, .favorites, .bookmarks] }

    public func items(for source: TimelineSource, limit: Int, cursor: PageCursor) async throws -> TimelinePage {
        switch source {
        case .home:
            let statuses = try await client.homeTimeline(limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .local:
            let statuses = try await client.publicTimeline(local: true, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .federated:
            let statuses = try await client.publicTimeline(local: false, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .notifications:
            // Mentions live in their own timeline, so keep them out of here.
            let notifications = try await client.notifications(types: nil, excludeTypes: ["mention"], limit: limit, maxID: cursor.maxID)
            return TimelinePage(
                items: notifications.map(TimelineItem.notification),
                nextCursor: notifications.last.map { .maxID($0.id) }
            )
        case .mentions:
            // Mentions come from mention-type notifications; paginate by the
            // oldest notification id, but display the attached statuses.
            let notifications = try await client.notifications(types: ["mention"], limit: limit, maxID: cursor.maxID)
            let items = notifications.compactMap { $0.status.map(TimelineItem.status) }
            return TimelinePage(items: items, nextCursor: notifications.last.map { .maxID($0.id) })
        case .conversations:
            let statuses = try await client.conversations(limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .thread(let statusID, _):
            let statuses = try await client.thread(id: statusID)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .userPosts(let userID, _):
            let statuses = try await client.userStatuses(userID: userID, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .followers(let userID, _):
            let users = try await client.followers(userID: userID, limit: limit)
            return TimelinePage(items: users.map(TimelineItem.user), nextCursor: nil)
        case .following(let userID, _):
            let users = try await client.following(userID: userID, limit: limit)
            return TimelinePage(items: users.map(TimelineItem.user), nextCursor: nil)
        case .hashtag(let tag):
            let statuses = try await client.hashtagTimeline(tag: tag, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .favorites:
            let statuses = try await client.favourites(limit: limit)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .bookmarks:
            let statuses = try await client.bookmarks(limit: limit)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .list(let id, _):
            let statuses = try await client.listTimeline(id: id, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .trending:
            let statuses = try await client.trendingStatuses(limit: limit)
            return TimelinePage(statuses: statuses, nextCursor: nil)
        case .search(let query, let kind):
            switch kind {
            case .posts:
                let statuses = try await client.searchStatuses(query: query, limit: limit)
                return TimelinePage(statuses: statuses, nextCursor: nil)
            case .users:
                let users = try await client.searchAccounts(query: query, limit: limit)
                return TimelinePage(items: users.map(TimelineItem.user), nextCursor: nil)
            }
        case .feed:
            throw PlatformError.message("Custom feeds aren't available on Mastodon.")
        case .remoteLocal(let instance):
            let statuses = try await client.remoteLocalTimeline(instance: instance, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        case .remoteUser(let instance, let username, _):
            let statuses = try await client.remoteUserStatuses(instance: instance, username: username, limit: limit, maxID: cursor.maxID)
            return TimelinePage(statuses: statuses, nextCursor: statuses.last.map { .maxID($0.id) })
        }
    }

    public func homeMarker() async throws -> String? { try await client.homeMarker() }
    public func setHomeMarker(_ statusID: String) async throws { try await client.setHomeMarker(statusID) }

    public func openStream(onEvent: @escaping @Sendable (StreamEvent) -> Void) -> StreamConnection? {
        guard let stream = MastodonStream(credentials: credentials, onEvent: onEvent) else { return nil }
        stream.start()
        return stream
    }

    public func resolve(_ status: Status) async throws -> Status {
        guard status.instanceURL != nil, let url = status.url?.absoluteString else { return status }
        return (try? await client.resolveStatus(url: url)) ?? status
    }

    public func lists() async throws -> [TimelineList] {
        try await client.getLists()
    }

    public func savedFeeds() async throws -> [TimelineList] { [] }

    @discardableResult
    public func post(_ draft: PostDraft) async throws -> Status? {
        try await client.post(draft)
    }

    @discardableResult
    public func editPost(_ id: String, draft: PostDraft) async throws -> Status? {
        try await client.editPost(id, draft: draft)
    }

    public func postSource(_ id: String) async throws -> PostSource? {
        try await client.postSource(id)
    }

    public func resolveUser(handle: String) async throws -> User {
        try await client.lookupAccount(handle: handle)
    }

    public func boost(_ statusID: String) async throws { try await client.reblog(statusID) }
    public func unboost(_ statusID: String) async throws { try await client.unreblog(statusID) }
    public func favorite(_ statusID: String) async throws { try await client.favourite(statusID) }
    public func unfavorite(_ statusID: String) async throws { try await client.unfavourite(statusID) }

    public func follow(_ userID: String) async throws { try await client.follow(userID) }
    public func unfollow(_ userID: String) async throws { try await client.unfollow(userID) }
    public func mute(_ userID: String) async throws { try await client.mute(userID) }
    public func unmute(_ userID: String) async throws { try await client.unmute(userID) }
    public func block(_ userID: String) async throws { try await client.block(userID) }
    public func unblock(_ userID: String) async throws { try await client.unblock(userID) }
    public func setBoostsHidden(_ hidden: Bool, for userID: String) async throws {
        try await client.follow(userID, reblogs: !hidden)
    }
    public func relationships(for userIDs: [String]) async throws -> [Relationship] {
        try await client.relationships(ids: userIDs)
    }
}
