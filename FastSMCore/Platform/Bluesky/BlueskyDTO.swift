//
//  BlueskyDTO.swift
//  FastSMCore
//
//  Codable mirrors of the AT Protocol / app.bsky JSON, plus mapping into
//  FastSMCore's universal models. Port of platforms/bluesky/models.py.
//  AT Proto JSON is already camelCase, so no key-decoding strategy is used.
//

import Foundation

enum BlueskyJSON {
    static let decoder = JSONDecoder()
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
}

struct BskyProfileDTO: Decodable {
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let avatar: String?
    let banner: String?
    let followersCount: Int?
    let followsCount: Int?
    let postsCount: Int?
    let createdAt: String?
    let viewer: BskyProfileViewerDTO?
}

/// Viewer relationship state on a profile (record URIs when following/blocking).
struct BskyProfileViewerDTO: Decodable {
    let muted: Bool?
    let blocking: String?    // block record URI
    let following: String?   // follow record URI
    let followedBy: String?
}

struct BskyProfilesDTO: Decodable {
    let profiles: [BskyProfileDTO]
}

struct BskyProfileBasicDTO: Decodable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: String?
}

struct BskyViewerStateDTO: Decodable {
    /// Record URI of the current user's like, if liked.
    let like: String?
    /// Record URI of the current user's repost, if reposted.
    let repost: String?
}

struct BskyReplyRefRecordDTO: Decodable {
    let root: BskyStrongRefDTO?
    let parent: BskyStrongRefDTO?
}

struct BskyStrongRefDTO: Codable {
    let uri: String
    let cid: String
}

/// The app.bsky.feed.post record body embedded in a PostView.
struct BskyPostRecordDTO: Decodable {
    let text: String?
    let createdAt: String?
    let reply: BskyReplyRefRecordDTO?
}

struct BskyPostViewDTO: Decodable {
    let uri: String
    let cid: String
    let author: BskyProfileBasicDTO
    let record: BskyPostRecordDTO?
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    let indexedAt: String?
    let viewer: BskyViewerStateDTO?
}

struct BskyReasonDTO: Decodable {
    let by: BskyProfileBasicDTO?
    let indexedAt: String?
}

struct BskyFeedViewPostDTO: Decodable {
    let post: BskyPostViewDTO
    let reason: BskyReasonDTO?
}

struct BskyTimelineDTO: Decodable {
    let feed: [BskyFeedViewPostDTO]
    let cursor: String?
}

struct BskyGetPostsDTO: Decodable {
    let posts: [BskyPostViewDTO]
}

struct BskySearchPostsDTO: Decodable {
    let posts: [BskyPostViewDTO]
    let cursor: String?
}

struct BskySearchActorsDTO: Decodable {
    let actors: [BskyProfileDTO]
    let cursor: String?
}

struct BskyPreferencesDTO: Decodable {
    let preferences: [BskyPrefItemDTO]
}

struct BskyPrefItemDTO: Decodable {
    let type: String
    let items: [BskySavedFeedItemDTO]?
    enum CodingKeys: String, CodingKey { case type = "$type"; case items }
}

struct BskySavedFeedItemDTO: Decodable {
    let type: String   // "feed", "list", or "timeline"
    let value: String
}

struct BskyFeedGeneratorsDTO: Decodable {
    let feeds: [BskyFeedGeneratorDTO]
}

struct BskyFeedGeneratorDTO: Decodable {
    let uri: String
    let displayName: String?
}

struct BskyNotificationDTO: Decodable {
    let uri: String
    let cid: String
    let author: BskyProfileBasicDTO
    let reason: String
    let reasonSubject: String?
    let record: BskyPostRecordDTO?
    let isRead: Bool?
    let indexedAt: String?
}

struct BskyListNotificationsDTO: Decodable {
    let notifications: [BskyNotificationDTO]
    let cursor: String?
}

/// Recursive thread node. `post` is nil for not-found / blocked nodes.
final class BskyThreadViewPostDTO: Decodable {
    let post: BskyPostViewDTO?
    let parent: BskyThreadViewPostDTO?
    let replies: [BskyThreadViewPostDTO]?
}

struct BskyGetPostThreadDTO: Decodable {
    let thread: BskyThreadViewPostDTO
}

struct BskyFollowersDTO: Decodable {
    let followers: [BskyProfileDTO]
    let cursor: String?
}

struct BskyFollowsDTO: Decodable {
    let follows: [BskyProfileDTO]
    let cursor: String?
}

// MARK: - Mapping

enum BlueskyMapper {
    private static func handleUsername(_ handle: String) -> String {
        handle.split(separator: ".").first.map(String.init) ?? handle
    }

    static func user(_ dto: BskyProfileDTO) -> User {
        User(
            id: dto.did,
            acct: dto.handle,
            username: handleUsername(dto.handle),
            displayName: (dto.displayName?.isEmpty == false) ? dto.displayName! : dto.handle,
            note: dto.description ?? "",
            avatarURL: dto.avatar.flatMap(URL.init(string:)),
            headerURL: dto.banner.flatMap(URL.init(string:)),
            followersCount: dto.followersCount ?? 0,
            followingCount: dto.followsCount ?? 0,
            statusesCount: dto.postsCount ?? 0,
            createdAt: DateParsing.parse(dto.createdAt),
            url: URL(string: "https://bsky.app/profile/\(dto.handle)"),
            platform: .bluesky
        )
    }

    static func user(_ dto: BskyProfileBasicDTO) -> User {
        User(
            id: dto.did,
            acct: dto.handle,
            username: handleUsername(dto.handle),
            displayName: (dto.displayName?.isEmpty == false) ? dto.displayName! : dto.handle,
            avatarURL: dto.avatar.flatMap(URL.init(string:)),
            url: URL(string: "https://bsky.app/profile/\(dto.handle)"),
            platform: .bluesky
        )
    }

    /// Map a bare post (no repost wrapper) to a Status.
    static func status(_ post: BskyPostViewDTO) -> Status {
        let text = post.record?.text ?? ""
        let date = DateParsing.parse(post.record?.createdAt)
            ?? DateParsing.parse(post.indexedAt)
            ?? Date()
        return Status(
            id: post.uri,
            account: user(post.author),
            content: text,
            text: text,
            createdAt: date,
            favouritesCount: post.likeCount ?? 0,
            boostsCount: post.repostCount ?? 0,
            repliesCount: post.replyCount ?? 0,
            inReplyToID: post.record?.reply?.parent?.uri,
            url: postWebURL(uri: post.uri, handle: post.author.handle),
            visibility: .public,
            favourited: post.viewer?.like != nil,
            boosted: post.viewer?.repost != nil,
            platform: .bluesky
        )
    }

    /// Map a feed entry, honoring a repost reason by wrapping the original in a
    /// boost authored by the reposter (mirrors bluesky_post_to_universal).
    static func feedEntry(_ entry: BskyFeedViewPostDTO) -> Status {
        let inner = status(entry.post)
        guard let reason = entry.reason, let by = reason.by else {
            return inner
        }
        let reposter = user(by)
        let repostDate = DateParsing.parse(reason.indexedAt) ?? inner.createdAt
        return Status(
            id: entry.post.uri + ":repost",
            account: reposter,
            content: "",
            text: "",
            createdAt: repostDate,
            reblog: Reblog(inner),
            visibility: .public,
            platform: .bluesky
        )
    }

    static func notificationKind(_ reason: String) -> Notification.Kind {
        switch reason {
        case "like": return .favourite
        case "repost": return .reblog
        case "follow": return .follow
        case "mention", "reply", "quote": return .mention
        default: return .unknown
        }
    }

    static func notification(_ dto: BskyNotificationDTO) -> Notification {
        Notification(
            id: dto.uri,
            type: notificationKind(dto.reason),
            account: user(dto.author),
            createdAt: DateParsing.parse(dto.indexedAt) ?? Date(),
            status: nil,
            platform: .bluesky
        )
    }

    /// Reasons that represent someone talking *to* you (the Mentions timeline).
    static let mentionReasons: Set<String> = ["mention", "reply", "quote"]

    static func postWebURL(uri: String, handle: String) -> URL? {
        // at://did/app.bsky.feed.post/rkey  ->  https://bsky.app/profile/handle/post/rkey
        guard let rkey = uri.split(separator: "/").last else { return nil }
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }
}
