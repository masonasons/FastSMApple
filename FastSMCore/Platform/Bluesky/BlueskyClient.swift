//
//  BlueskyClient.swift
//  FastSMCore
//
//  AT Protocol XRPC client. Replaces the `atproto` dependency. An actor so the
//  mutable session (access/refresh JWTs) is updated safely and refreshes are
//  serialized. Implements the Milestone 1 surface from
//  platforms/bluesky/account.py.
//

import Foundation

actor BlueskyClient {
    private var session: BlueskySession
    private let http: HTTP

    init(session: BlueskySession, http: HTTP = HTTP()) {
        self.session = session
        self.http = http
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func nowTimestamp() -> String { Self.iso8601.string(from: Date()) }

    // MARK: Request plumbing (with one refresh-and-retry on 401)

    private func authorizedRequest(
        endpoint: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) throws -> URLRequest {
        var comps = URLComponents(
            url: session.pdsURL.appendingPathComponent("xrpc/\(endpoint)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(session.accessJwt)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        return request
    }

    private func performData(
        endpoint: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        let request = try authorizedRequest(endpoint: endpoint, method: method, query: query, jsonBody: jsonBody)
        do {
            return try await http.data(for: request)
        } catch PlatformError.http(let status, let body) where Self.isExpiredToken(status: status, body: body) {
            // Access token expired — Bluesky returns 401 OR 400 with "ExpiredToken".
            // Refresh the session once and retry.
            session = try await BlueskyAuth.refreshSession(session, http: http)
            let retry = try authorizedRequest(endpoint: endpoint, method: method, query: query, jsonBody: jsonBody)
            do {
                return try await http.data(for: retry)
            } catch PlatformError.http(let retryStatus, let retryBody) {
                throw PlatformError.http(status: retryStatus, body: retryBody.isEmpty ? body : retryBody)
            }
        }
    }

    private static func isExpiredToken(status: Int, body: String) -> Bool {
        status == 401 || (status == 400 && body.contains("ExpiredToken"))
    }

    private func perform<T: Decodable>(
        _ type: T.Type,
        endpoint: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> T {
        let data = try await performData(endpoint: endpoint, method: method, query: query, jsonBody: jsonBody)
        do {
            return try BlueskyJSON.decoder.decode(T.self, from: data)
        } catch {
            throw PlatformError.decoding(String(describing: error))
        }
    }

    // MARK: Reads

    func getProfile(actor: String) async throws -> User {
        let dto = try await perform(
            BskyProfileDTO.self,
            endpoint: "app.bsky.actor.getProfile",
            method: .get,
            query: [URLQueryItem(name: "actor", value: actor)]
        )
        return BlueskyMapper.user(dto)
    }

    func getTimeline(limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(
            BskyTimelineDTO.self,
            endpoint: "app.bsky.feed.getTimeline",
            method: .get,
            query: query
        )
        return (dto.feed.map(BlueskyMapper.feedEntry), dto.cursor)
    }

    func listNotifications(limit: Int, cursor: String?) async throws -> (notifications: [Notification], cursor: String?) {
        let dto = try await fetchNotifications(limit: limit, cursor: cursor)
        // Mentions/replies/quotes belong to the Mentions timeline; keep them out
        // of Notifications. (AT Proto has no server-side reason filter here.)
        let filtered = dto.notifications.filter { !BlueskyMapper.mentionReasons.contains($0.reason) }
        return (filtered.map(BlueskyMapper.notification), dto.cursor)
    }

    /// Mentions/replies/quotes, resolved to the actual posts for display.
    func mentions(limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        let dto = try await fetchNotifications(limit: limit, cursor: cursor)
        let uris = dto.notifications
            .filter { BlueskyMapper.mentionReasons.contains($0.reason) }
            .map(\.uri)
        guard !uris.isEmpty else { return ([], dto.cursor) }
        let posts = try await getPosts(uris)
        return (posts.map(BlueskyMapper.status), dto.cursor)
    }

    private func fetchNotifications(limit: Int, cursor: String?) async throws -> BskyListNotificationsDTO {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await perform(
            BskyListNotificationsDTO.self,
            endpoint: "app.bsky.notification.listNotifications",
            method: .get,
            query: query
        )
    }

    func authorFeed(actor: String, limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        var query = [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskyTimelineDTO.self, endpoint: "app.bsky.feed.getAuthorFeed", method: .get, query: query)
        return (dto.feed.map(BlueskyMapper.feedEntry), dto.cursor)
    }

    func searchPosts(query searchQuery: String, limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        var query = [URLQueryItem(name: "q", value: searchQuery), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskySearchPostsDTO.self, endpoint: "app.bsky.feed.searchPosts", method: .get, query: query)
        return (dto.posts.map(BlueskyMapper.status), dto.cursor)
    }

    func searchActors(query searchQuery: String, limit: Int, cursor: String?) async throws -> (users: [User], cursor: String?) {
        var query = [URLQueryItem(name: "q", value: searchQuery), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskySearchActorsDTO.self, endpoint: "app.bsky.actor.searchActors", method: .get, query: query)
        return (dto.actors.map(BlueskyMapper.user), dto.cursor)
    }

    func getFeed(uri: String, limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        var query = [URLQueryItem(name: "feed", value: uri), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskyTimelineDTO.self, endpoint: "app.bsky.feed.getFeed", method: .get, query: query)
        return (dto.feed.map(BlueskyMapper.feedEntry), dto.cursor)
    }

    func savedFeeds() async throws -> [TimelineList] {
        let prefs = try await perform(BskyPreferencesDTO.self, endpoint: "app.bsky.actor.getPreferences", method: .get, query: [])
        let uris = prefs.preferences
            .flatMap { $0.items ?? [] }
            .filter { $0.type == "feed" }
            .map(\.value)
        guard !uris.isEmpty else { return [] }
        let query = uris.map { URLQueryItem(name: "feeds", value: $0) }
        let gens = try await perform(BskyFeedGeneratorsDTO.self, endpoint: "app.bsky.feed.getFeedGenerators", method: .get, query: query)
        return gens.feeds.map { TimelineList(id: $0.uri, title: $0.displayName ?? "Feed") }
    }

    func actorLikes(actor: String, limit: Int, cursor: String?) async throws -> (statuses: [Status], cursor: String?) {
        var query = [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskyTimelineDTO.self, endpoint: "app.bsky.feed.getActorLikes", method: .get, query: query)
        return (dto.feed.map(BlueskyMapper.feedEntry), dto.cursor)
    }

    func thread(uri: String) async throws -> [Status] {
        let dto = try await perform(
            BskyGetPostThreadDTO.self,
            endpoint: "app.bsky.feed.getPostThread",
            method: .get,
            query: [URLQueryItem(name: "uri", value: basePostURI(uri))]
        )
        var ancestors: [Status] = []
        var node = dto.thread.parent
        while let current = node {
            if let post = current.post { ancestors.append(BlueskyMapper.status(post)) }
            node = current.parent
        }
        var result = Array(ancestors.reversed())
        if let post = dto.thread.post { result.append(BlueskyMapper.status(post)) }
        appendReplies(dto.thread.replies, into: &result)
        return result
    }

    private func appendReplies(_ nodes: [BskyThreadViewPostDTO]?, into result: inout [Status]) {
        for node in nodes ?? [] {
            if let post = node.post { result.append(BlueskyMapper.status(post)) }
            appendReplies(node.replies, into: &result)
        }
    }

    func followers(actor: String, limit: Int, cursor: String?) async throws -> (users: [User], cursor: String?) {
        var query = [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskyFollowersDTO.self, endpoint: "app.bsky.graph.getFollowers", method: .get, query: query)
        return (dto.followers.map(BlueskyMapper.user), dto.cursor)
    }

    func follows(actor: String, limit: Int, cursor: String?) async throws -> (users: [User], cursor: String?) {
        var query = [URLQueryItem(name: "actor", value: actor), URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let dto = try await perform(BskyFollowsDTO.self, endpoint: "app.bsky.graph.getFollows", method: .get, query: query)
        return (dto.follows.map(BlueskyMapper.user), dto.cursor)
    }

    private func getPosts(_ uris: [String]) async throws -> [BskyPostViewDTO] {
        guard !uris.isEmpty else { return [] }
        let query = uris.map { URLQueryItem(name: "uris", value: $0) }
        let dto = try await perform(
            BskyGetPostsDTO.self,
            endpoint: "app.bsky.feed.getPosts",
            method: .get,
            query: query
        )
        return dto.posts
    }

    // MARK: Writes

    private struct CreateRecordResponse: Decodable {
        let uri: String
        let cid: String
    }

    /// Strip the synthetic ":repost" suffix used on boost-wrapper status ids.
    private func basePostURI(_ id: String) -> String {
        id.hasSuffix(":repost") ? String(id.dropLast(":repost".count)) : id
    }

    @discardableResult
    private func createRecord(collection: String, record: [String: Any]) async throws -> CreateRecordResponse {
        try await perform(
            CreateRecordResponse.self,
            endpoint: "com.atproto.repo.createRecord",
            method: .post,
            jsonBody: ["repo": session.did, "collection": collection, "record": record]
        )
    }

    private func deleteRecord(collection: String, rkey: String) async throws {
        _ = try await performData(
            endpoint: "com.atproto.repo.deleteRecord",
            method: .post,
            jsonBody: ["repo": session.did, "collection": collection, "rkey": rkey]
        )
    }

    private static func rkey(from uri: String) -> String {
        String(uri.split(separator: "/").last ?? "")
    }

    private func buildReplyRef(parentURI: String) async throws -> [String: Any]? {
        let posts = try await getPosts([parentURI])
        guard let parent = posts.first else { return nil }
        let parentRef: [String: Any] = ["uri": parent.uri, "cid": parent.cid]
        // Root is the parent's own root if it's itself a reply, else the parent.
        let rootRef: [String: Any]
        if let root = parent.record?.reply?.root {
            rootRef = ["uri": root.uri, "cid": root.cid]
        } else {
            rootRef = parentRef
        }
        return ["root": rootRef, "parent": parentRef]
    }

    func post(_ draft: PostDraft) async throws -> Status? {
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": draft.text,
            "createdAt": nowTimestamp(),
        ]
        if let language = draft.language { record["langs"] = [language] }
        if let replyTo = draft.replyToID {
            if let reply = try await buildReplyRef(parentURI: basePostURI(replyTo)) {
                record["reply"] = reply
            }
        }
        if let quotedID = draft.quotedStatusID, let quoted = try await getPosts([basePostURI(quotedID)]).first {
            record["embed"] = [
                "$type": "app.bsky.embed.record",
                "record": ["uri": quoted.uri, "cid": quoted.cid],
            ]
        }
        let created = try await createRecord(collection: "app.bsky.feed.post", record: record)
        // Re-fetch for full data; Bluesky indexing can lag, so fall back to a
        // minimal status built from what we already know.
        if let view = try? await getPosts([created.uri]).first {
            return BlueskyMapper.status(view)
        }
        return Status(
            id: created.uri,
            account: try await getProfile(actor: session.did),
            content: draft.text,
            text: draft.text,
            createdAt: Date(),
            url: BlueskyMapper.postWebURL(uri: created.uri, handle: session.handle),
            visibility: .public,
            platform: .bluesky
        )
    }

    func like(statusID: String) async throws {
        let uri = basePostURI(statusID)
        guard let post = try await getPosts([uri]).first else {
            throw PlatformError.message("Couldn't find that post to like.")
        }
        _ = try await createRecord(collection: "app.bsky.feed.like", record: [
            "$type": "app.bsky.feed.like",
            "subject": ["uri": post.uri, "cid": post.cid],
            "createdAt": nowTimestamp(),
        ])
    }

    func unlike(statusID: String) async throws {
        let uri = basePostURI(statusID)
        guard let post = try await getPosts([uri]).first, let likeURI = post.viewer?.like else { return }
        try await deleteRecord(collection: "app.bsky.feed.like", rkey: Self.rkey(from: likeURI))
    }

    func repost(statusID: String) async throws {
        let uri = basePostURI(statusID)
        guard let post = try await getPosts([uri]).first else {
            throw PlatformError.message("Couldn't find that post to repost.")
        }
        _ = try await createRecord(collection: "app.bsky.feed.repost", record: [
            "$type": "app.bsky.feed.repost",
            "subject": ["uri": post.uri, "cid": post.cid],
            "createdAt": nowTimestamp(),
        ])
    }

    func unrepost(statusID: String) async throws {
        let uri = basePostURI(statusID)
        guard let post = try await getPosts([uri]).first, let repostURI = post.viewer?.repost else { return }
        try await deleteRecord(collection: "app.bsky.feed.repost", rkey: Self.rkey(from: repostURI))
    }

    // MARK: User actions

    private func rawProfile(_ actor: String) async throws -> BskyProfileDTO {
        try await perform(BskyProfileDTO.self, endpoint: "app.bsky.actor.getProfile", method: .get,
                          query: [URLQueryItem(name: "actor", value: actor)])
    }

    func follow(did: String) async throws {
        _ = try await createRecord(collection: "app.bsky.graph.follow", record: [
            "$type": "app.bsky.graph.follow", "subject": did, "createdAt": nowTimestamp(),
        ])
    }

    func unfollow(did: String) async throws {
        guard let uri = try await rawProfile(did).viewer?.following else { return }
        try await deleteRecord(collection: "app.bsky.graph.follow", rkey: Self.rkey(from: uri))
    }

    func block(did: String) async throws {
        _ = try await createRecord(collection: "app.bsky.graph.block", record: [
            "$type": "app.bsky.graph.block", "subject": did, "createdAt": nowTimestamp(),
        ])
    }

    func unblock(did: String) async throws {
        guard let uri = try await rawProfile(did).viewer?.blocking else { return }
        try await deleteRecord(collection: "app.bsky.graph.block", rkey: Self.rkey(from: uri))
    }

    func mute(did: String) async throws {
        _ = try await performData(endpoint: "app.bsky.graph.muteActor", method: .post, jsonBody: ["actor": did])
    }

    func unmute(did: String) async throws {
        _ = try await performData(endpoint: "app.bsky.graph.unmuteActor", method: .post, jsonBody: ["actor": did])
    }

    func relationships(dids: [String]) async throws -> [Relationship] {
        guard !dids.isEmpty else { return [] }
        var result: [Relationship] = []
        var index = 0
        while index < dids.count {
            let chunk = Array(dids[index..<min(index + 25, dids.count)])
            index += 25
            let query = chunk.map { URLQueryItem(name: "actors", value: $0) }
            let dto = try await perform(BskyProfilesDTO.self, endpoint: "app.bsky.actor.getProfiles", method: .get, query: query)
            for p in dto.profiles {
                result.append(Relationship(
                    id: p.did,
                    following: p.viewer?.following != nil,
                    followedBy: p.viewer?.followedBy != nil,
                    muting: p.viewer?.muted ?? false,
                    blocking: p.viewer?.blocking != nil))
            }
        }
        return result
    }
}
