//
//  TimelineSource.swift
//  FastSMCore
//
//  Describes what a timeline shows. As well as the standing feeds (home,
//  notifications, …), a source can be parameterized — a thread, a user's posts, a
//  followers/following list. This is what lets the UI spawn new timelines for
//  threads and user lists instead of opening separate windows. A source's
//  content may be posts, notifications, or users (see `TimelineItem`).
//

import Foundation

/// What a search timeline searches for.
public enum SearchKind: String, Codable, Sendable, Hashable {
    case posts, users
}

public enum TimelineSource: Hashable, Sendable, Codable {
    // Standing feeds
    case home
    case notifications
    case mentions
    case conversations
    case local
    case federated

    // Parameterized, spawnable timelines
    case thread(statusID: String, title: String)
    case userPosts(userID: String, title: String)
    case followers(userID: String, title: String)
    case following(userID: String, title: String)

    // On-demand openable feeds
    case hashtag(tag: String)
    case favorites
    case bookmarks
    case list(id: String, title: String)
    case trending
    case search(query: String, kind: SearchKind)
    case feed(uri: String, title: String)   // Bluesky custom feed
    case remoteLocal(instance: String)      // a remote instance's local timeline
    case remoteUser(instance: String, username: String, title: String)

    /// Human-facing title shown in the timelines list.
    public var title: String {
        switch self {
        case .home: return "Home"
        case .notifications: return "Notifications"
        case .mentions: return "Mentions"
        case .conversations: return "Conversations"
        case .local: return "Local"
        case .federated: return "Federated"
        case .thread(_, let title): return title
        case .userPosts(_, let title): return title
        case .followers(_, let title): return title
        case .following(_, let title): return title
        case .hashtag(let tag): return "#\(tag)"
        case .favorites: return "Favorites"
        case .bookmarks: return "Bookmarks"
        case .list(_, let title): return title
        case .trending: return "Trending"
        case .search(let query, let kind): return "\(kind == .users ? "People" : "Search"): \(query)"
        case .feed(_, let title): return title
        case .remoteLocal(let instance): return "\(instance) (Local)"
        case .remoteUser(_, _, let title): return title
        }
    }

    /// Stable string used to namespace the on-disk cache.
    public var cacheKey: String {
        switch self {
        case .home: return "home"
        case .notifications: return "notifications"
        case .mentions: return "mentions"
        case .conversations: return "conversations"
        case .local: return "local"
        case .federated: return "federated"
        case .thread(let id, _): return "thread:\(id)"
        case .userPosts(let id, _): return "userPosts:\(id)"
        case .followers(let id, _): return "followers:\(id)"
        case .following(let id, _): return "following:\(id)"
        case .hashtag(let tag): return "hashtag:\(tag.lowercased())"
        case .favorites: return "favorites"
        case .bookmarks: return "bookmarks"
        case .list(let id, _): return "list:\(id)"
        case .trending: return "trending"
        case .search(let query, let kind): return "search:\(kind.rawValue):\(query.lowercased())"
        case .feed(let uri, _): return "feed:\(uri)"
        case .remoteLocal(let instance): return "remoteLocal:\(instance.lowercased())"
        case .remoteUser(let instance, let username, _): return "remoteUser:\(instance.lowercased()):\(username.lowercased())"
        }
    }

    /// Standing feeds are cached for instant startup; ephemeral spawned timelines
    /// (threads, user lists) are not.
    public var isCacheable: Bool {
        switch self {
        case .home, .notifications, .mentions, .conversations, .local, .federated:
            return true
        case .thread, .userPosts, .followers, .following, .hashtag, .favorites, .bookmarks,
             .list, .trending, .search, .feed, .remoteLocal, .remoteUser:
            return false
        }
    }

    /// True for notification feeds (rows are notifications, not statuses).
    public var isNotificationTimeline: Bool {
        if case .notifications = self { return true }
        return false
    }

    /// True when rows are users (followers/following lists, people search), so
    /// the UI can offer multi-select and batch follow/mute/block actions.
    public var isUserList: Bool {
        switch self {
        case .followers, .following: return true
        case .search(_, let kind): return kind == .users
        default: return false
        }
    }

    /// Whether items are ordered newest-first by time (so merges should re-sort
    /// and the cache cap drops the oldest). Threads keep conversation order, user
    /// lists keep server order, and favorites/bookmarks keep action order.
    public var isTimeOrdered: Bool {
        switch self {
        case .home, .local, .federated, .notifications, .mentions, .conversations, .userPosts, .hashtag, .list,
             .remoteLocal, .remoteUser:
            return true
        case .thread, .followers, .following, .favorites, .bookmarks, .trending, .search, .feed:
            return false
        }
    }

    /// Soundpack file (base name) played when this timeline receives new posts
    /// on refresh. nil for timelines that shouldn't chime (threads, lists).
    public var newItemsSoundName: String? {
        switch self {
        case .home, .local, .federated, .hashtag, .list, .feed, .remoteLocal, .remoteUser: return "home"
        case .notifications: return "notification"
        case .mentions: return "mentions"
        case .conversations: return "messages"
        case .thread, .userPosts, .followers, .following, .favorites, .bookmarks, .trending, .search: return nil
        }
    }

    /// Spawned/opened timelines can be closed by the user; the standing feeds
    /// (home, notifications, mentions, conversations) cannot.
    public var isDismissable: Bool {
        switch self {
        case .thread, .userPosts, .followers, .following, .local, .federated, .hashtag, .favorites, .bookmarks,
             .list, .trending, .search, .feed, .remoteLocal, .remoteUser:
            return true
        case .home, .notifications, .mentions, .conversations:
            return false
        }
    }
}
