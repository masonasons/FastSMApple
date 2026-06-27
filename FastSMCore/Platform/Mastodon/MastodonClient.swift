//
//  MastodonClient.swift
//  FastSMCore
//
//  URLSession-based Mastodon REST client. Replaces the Mastodon.py dependency.
//  Only the endpoints needed for Milestone 1 are implemented; the structure
//  leaves room for the rest of platforms/mastodon/account.py later.
//

import Foundation

public struct MastodonClient: Sendable {
    let credentials: MastodonCredentials
    private let http: HTTP

    public init(credentials: MastodonCredentials, http: HTTP = HTTP()) {
        self.credentials = credentials
        self.http = http
    }

    private func authorizedRequest(
        path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        form: [String: String]? = nil
    ) -> URLRequest {
        var comps = URLComponents(
            url: credentials.instanceURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { comps.queryItems = query }
        var request = URLRequest(url: comps.url!)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTP.formBody(form)
        }
        return request
    }

    // MARK: Account

    /// The instance's maximum post length (Mastodon 4 `/api/v2/instance`).
    public func instanceMaxCharacters() async throws -> Int? {
        let request = authorizedRequest(path: "api/v2/instance")
        let dto = try await http.decode(MastodonInstanceDTO.self, from: request, decoder: MastodonJSON.decoder)
        return dto.configuration?.statuses?.maxCharacters
    }

    public func verifyCredentials() async throws -> User {
        let request = authorizedRequest(path: "api/v1/accounts/verify_credentials")
        let dto = try await http.decode(MastodonAccountDTO.self, from: request, decoder: MastodonJSON.decoder)
        guard let user = MastodonMapper.user(dto) else {
            throw PlatformError.decoding("Couldn't read account.")
        }
        return user
    }

    // MARK: Timeline

    public func homeTimeline(limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = authorizedRequest(path: "api/v1/timelines/home", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func publicTimeline(local: Bool, limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if local { query.append(URLQueryItem(name: "local", value: "true")) }
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = authorizedRequest(path: "api/v1/timelines/public", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func hashtagTimeline(tag: String, limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let request = authorizedRequest(path: "api/v1/timelines/tag/\(encodedTag)", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    // Favourites/bookmarks paginate by an opaque Link-header id, so we fetch the
    // first page only (no status-id scrollback).
    public func favourites(limit: Int) async throws -> [Status] {
        let request = authorizedRequest(path: "api/v1/favourites", query: [URLQueryItem(name: "limit", value: String(limit))])
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func bookmarks(limit: Int) async throws -> [Status] {
        let request = authorizedRequest(path: "api/v1/bookmarks", query: [URLQueryItem(name: "limit", value: String(limit))])
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func homeMarker() async throws -> String? {
        let request = authorizedRequest(path: "api/v1/markers", query: [URLQueryItem(name: "timeline[]", value: "home")])
        let dto = try await http.decode(MastodonMarkersDTO.self, from: request, decoder: MastodonJSON.decoder)
        return dto.home?.lastReadId
    }

    public func setHomeMarker(_ statusID: String) async throws {
        var request = authorizedRequest(path: "api/v1/markers", method: .post)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.orderedFormBody([("home[last_read_id]", statusID)])
        _ = try await http.data(for: request)
    }

    public func getLists() async throws -> [TimelineList] {
        let request = authorizedRequest(path: "api/v1/lists")
        let dtos = try await http.decode([MastodonListDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.map { TimelineList(id: $0.id, title: $0.title) }
    }

    public func listTimeline(id: String, limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = authorizedRequest(path: "api/v1/timelines/list/\(id)", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func trendingStatuses(limit: Int) async throws -> [Status] {
        let request = authorizedRequest(path: "api/v1/trends/statuses", query: [URLQueryItem(name: "limit", value: String(limit))])
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func searchStatuses(query searchQuery: String, limit: Int) async throws -> [Status] {
        let request = authorizedRequest(path: "api/v2/search", query: [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "type", value: "statuses"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let dto = try await http.decode(MastodonSearchDTO.self, from: request, decoder: MastodonJSON.decoder)
        return (dto.statuses ?? []).compactMap(MastodonMapper.status)
    }

    // MARK: Remote instances (unauthenticated, marked for resolve-on-interact)

    /// Normalize "mastodon.social" / "https://mastodon.social/" → base URL.
    static func instanceBaseURL(_ instance: String) -> URL? {
        var text = instance.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("@") { text.removeFirst() }
        if !text.hasPrefix("http") { text = "https://\(text)" }
        var comps = URLComponents(string: text)
        comps?.path = ""
        return comps?.url
    }

    private func unauthenticatedRequest(base: URL, path: String, query: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        return URLRequest(url: comps.url!)
    }

    public func remoteLocalTimeline(instance: String, limit: Int, maxID: String?) async throws -> [Status] {
        guard let base = Self.instanceBaseURL(instance) else { throw PlatformError.message("Invalid instance.") }
        var query = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "local", value: "true")]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = unauthenticatedRequest(base: base, path: "api/v1/timelines/public", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status).map { markRemote($0, base: base.absoluteString) }
    }

    public func remoteUserStatuses(instance: String, username: String, limit: Int, maxID: String?) async throws -> [Status] {
        guard let base = Self.instanceBaseURL(instance) else { throw PlatformError.message("Invalid instance.") }
        let acct = username.hasPrefix("@") ? String(username.dropFirst()) : username
        let lookup = unauthenticatedRequest(base: base, path: "api/v1/accounts/lookup", query: [URLQueryItem(name: "acct", value: acct)])
        let userDTO = try await http.decode(MastodonAccountDTO.self, from: lookup, decoder: MastodonJSON.decoder)
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = unauthenticatedRequest(base: base, path: "api/v1/accounts/\(userDTO.id)/statuses", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status).map { markRemote($0, base: base.absoluteString) }
    }

    private func markRemote(_ status: Status, base: String) -> Status {
        var copy = status
        copy.instanceURL = base
        return copy
    }

    /// Resolve a remote post's URL to the copy on the user's own instance.
    public func resolveStatus(url: String) async throws -> Status? {
        let request = authorizedRequest(path: "api/v2/search", query: [
            URLQueryItem(name: "q", value: url),
            URLQueryItem(name: "type", value: "statuses"),
            URLQueryItem(name: "resolve", value: "true"),
            URLQueryItem(name: "limit", value: "1"),
        ])
        let dto = try await http.decode(MastodonSearchDTO.self, from: request, decoder: MastodonJSON.decoder)
        return dto.statuses?.first.flatMap(MastodonMapper.status)
    }

    public func searchAccounts(query searchQuery: String, limit: Int) async throws -> [User] {
        let request = authorizedRequest(path: "api/v2/search", query: [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "type", value: "accounts"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let dto = try await http.decode(MastodonSearchDTO.self, from: request, decoder: MastodonJSON.decoder)
        return (dto.accounts ?? []).compactMap(MastodonMapper.user)
    }

    public func notifications(types: [String]?, excludeTypes: [String]? = nil, limit: Int, maxID: String?) async throws -> [Notification] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        types?.forEach { query.append(URLQueryItem(name: "types[]", value: $0)) }
        excludeTypes?.forEach { query.append(URLQueryItem(name: "exclude_types[]", value: $0)) }
        let request = authorizedRequest(path: "api/v1/notifications", query: query)
        let dtos = try await http.decode([MastodonNotificationDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.notification)
    }

    public func conversations(limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = authorizedRequest(path: "api/v1/conversations", query: query)
        let dtos = try await http.decode([MastodonConversationDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap { MastodonMapper.status($0.lastStatus) }
    }

    public func status(id: String) async throws -> Status? {
        let request = authorizedRequest(path: "api/v1/statuses/\(id)")
        let dto = try await http.decode(MastodonStatusDTO.self, from: request, decoder: MastodonJSON.decoder)
        return MastodonMapper.status(dto)
    }

    /// The full thread for a status: ancestors, the status itself, then replies.
    public func thread(id: String) async throws -> [Status] {
        async let focus = status(id: id)
        let contextRequest = authorizedRequest(path: "api/v1/statuses/\(id)/context")
        async let context = http.decode(MastodonContextDTO.self, from: contextRequest, decoder: MastodonJSON.decoder)
        let (focusStatus, ctx) = try await (focus, context)
        var result = ctx.ancestors.compactMap(MastodonMapper.status)
        if let focusStatus { result.append(focusStatus) }
        result.append(contentsOf: ctx.descendants.compactMap(MastodonMapper.status))
        return result
    }

    public func userStatuses(userID: String, limit: Int, maxID: String?) async throws -> [Status] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxID { query.append(URLQueryItem(name: "max_id", value: maxID)) }
        let request = authorizedRequest(path: "api/v1/accounts/\(userID)/statuses", query: query)
        let dtos = try await http.decode([MastodonStatusDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.status)
    }

    public func followers(userID: String, limit: Int) async throws -> [User] {
        let request = authorizedRequest(path: "api/v1/accounts/\(userID)/followers", query: [URLQueryItem(name: "limit", value: String(limit))])
        let dtos = try await http.decode([MastodonAccountDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.user)
    }

    public func following(userID: String, limit: Int) async throws -> [User] {
        let request = authorizedRequest(path: "api/v1/accounts/\(userID)/following", query: [URLQueryItem(name: "limit", value: String(limit))])
        let dtos = try await http.decode([MastodonAccountDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.compactMap(MastodonMapper.user)
    }

    // MARK: Actions

    public func post(_ draft: PostDraft) async throws -> Status? {
        var form: [(String, String)] = [("status", draft.text)]
        if let replyToID = draft.replyToID { form.append(("in_reply_to_id", replyToID)) }
        if let visibility = draft.visibility { form.append(("visibility", visibility.rawValue)) }
        if let spoiler = draft.spoilerText, !spoiler.isEmpty { form.append(("spoiler_text", spoiler)) }
        if let language = draft.language { form.append(("language", language)) }
        if let poll = draft.poll, poll.options.count >= 2 {
            for option in poll.options { form.append(("poll[options][]", option)) }
            form.append(("poll[expires_in]", String(poll.expiresInSeconds)))
            form.append(("poll[multiple]", poll.multiple ? "true" : "false"))
        }
        if let scheduledAt = draft.scheduledAt {
            form.append(("scheduled_at", ISO8601DateFormatter().string(from: scheduledAt)))
        }

        var request = authorizedRequest(path: "api/v1/statuses", method: .post)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.orderedFormBody(form)

        // A scheduled post returns a ScheduledStatus (no account/content), so we
        // don't try to decode it as a Status — there's nothing to show yet.
        if draft.scheduledAt != nil {
            _ = try await http.data(for: request)
            return nil
        }
        let dto = try await http.decode(MastodonStatusDTO.self, from: request, decoder: MastodonJSON.decoder)
        guard let status = MastodonMapper.status(dto) else {
            throw PlatformError.decoding("Couldn't read posted status.")
        }
        return status
    }

    public func lookupAccount(handle: String) async throws -> User {
        let acct = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let request = authorizedRequest(path: "api/v1/accounts/lookup", query: [URLQueryItem(name: "acct", value: acct)])
        let dto = try await http.decode(MastodonAccountDTO.self, from: request, decoder: MastodonJSON.decoder)
        guard let user = MastodonMapper.user(dto) else {
            throw PlatformError.message("Couldn't find @\(acct).")
        }
        return user
    }

    public func postSource(_ id: String) async throws -> PostSource? {
        let request = authorizedRequest(path: "api/v1/statuses/\(id)/source")
        let dto = try await http.decode(MastodonStatusSourceDTO.self, from: request, decoder: MastodonJSON.decoder)
        return PostSource(text: dto.text, spoilerText: dto.spoilerText ?? "")
    }

    public func editPost(_ id: String, draft: PostDraft) async throws -> Status? {
        var form: [(String, String)] = [("status", draft.text)]
        if let spoiler = draft.spoilerText { form.append(("spoiler_text", spoiler)) }
        if let language = draft.language { form.append(("language", language)) }
        var request = authorizedRequest(path: "api/v1/statuses/\(id)", method: .put)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.orderedFormBody(form)
        let dto = try await http.decode(MastodonStatusDTO.self, from: request, decoder: MastodonJSON.decoder)
        guard let status = MastodonMapper.status(dto) else {
            throw PlatformError.decoding("Couldn't read edited status.")
        }
        return status
    }

    public func reblog(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/statuses/\(id)/reblog", method: .post))
    }

    public func unreblog(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/statuses/\(id)/unreblog", method: .post))
    }

    public func favourite(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/statuses/\(id)/favourite", method: .post))
    }

    public func unfavourite(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/statuses/\(id)/unfavourite", method: .post))
    }

    // MARK: User actions

    /// Follow an account. Pass `reblogs` to also set boost visibility.
    public func follow(_ id: String, reblogs: Bool? = nil) async throws {
        var request = authorizedRequest(path: "api/v1/accounts/\(id)/follow", method: .post)
        if let reblogs {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTP.orderedFormBody([("reblogs", reblogs ? "true" : "false")])
        }
        _ = try await http.data(for: request)
    }

    public func unfollow(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/accounts/\(id)/unfollow", method: .post))
    }

    public func mute(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/accounts/\(id)/mute", method: .post))
    }

    public func unmute(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/accounts/\(id)/unmute", method: .post))
    }

    public func block(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/accounts/\(id)/block", method: .post))
    }

    public func unblock(_ id: String) async throws {
        _ = try await http.data(for: authorizedRequest(path: "api/v1/accounts/\(id)/unblock", method: .post))
    }

    public func relationships(ids: [String]) async throws -> [Relationship] {
        guard !ids.isEmpty else { return [] }
        let query = ids.map { URLQueryItem(name: "id[]", value: $0) }
        let request = authorizedRequest(path: "api/v1/accounts/relationships", query: query)
        let dtos = try await http.decode([MastodonRelationshipDTO].self, from: request, decoder: MastodonJSON.decoder)
        return dtos.map {
            Relationship(id: $0.id, following: $0.following ?? false, followedBy: $0.followedBy ?? false,
                         muting: $0.muting ?? false, blocking: $0.blocking ?? false,
                         showingReblogs: $0.showingReblogs ?? true)
        }
    }
}
