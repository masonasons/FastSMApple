//
//  TimelineItem.swift
//  FastSMCore
//
//  A row in a timeline. Most timelines are made of statuses, but the
//  Notifications timeline is made of notifications (follows, favorites, boosts,
//  …) which aren't statuses. This enum lets one timeline pipeline carry either.
//

import Foundation

public enum TimelineItem: Identifiable, Codable, Sendable, Hashable {
    case status(Status)
    case notification(Notification)
    case user(User)

    public var id: String {
        switch self {
        case .status(let status): return "s:\(status.id)"
        case .notification(let notification): return "n:\(notification.id)"
        case .user(let user): return "u:\(user.id)"
        }
    }

    /// The status this item carries, if any: the status itself, or the status
    /// attached to a notification (e.g. the post that was favorited). Used for
    /// boost/favorite/reply actions.
    public var status: Status? {
        switch self {
        case .status(let status): return status
        case .notification(let notification): return notification.status
        case .user: return nil
        }
    }

    /// The user this item represents, if it's a user-list row.
    public var user: User? {
        if case .user(let user) = self { return user }
        return nil
    }

    /// Timestamp used to keep chronological timelines newest-first. Uses the
    /// top-level status time (a boost's repost time, not the original), or the
    /// notification time. nil for user rows (not time-ordered).
    public var sortDate: Date? {
        switch self {
        case .status(let status): return status.createdAt
        case .notification(let notification): return notification.createdAt
        case .user: return nil
        }
    }

    /// The status that should actually be acted on / displayed (unwraps boosts).
    public var actionableStatus: Status? { status?.displayStatus }

    // Optimistic action mutation, applied to the carried status if present.

    public mutating func setFavourited(_ value: Bool) {
        switch self {
        case .status(var status):
            status.setFavourited(value)
            self = .status(status)
        case .notification(var notification):
            guard var status = notification.status else { return }
            status.setFavourited(value)
            notification.status = status
            self = .notification(notification)
        case .user:
            break
        }
    }

    public mutating func setBoosted(_ value: Bool) {
        switch self {
        case .status(var status):
            status.setBoosted(value)
            self = .status(status)
        case .notification(var notification):
            guard var status = notification.status else { return }
            status.setBoosted(value)
            notification.status = status
            self = .notification(notification)
        case .user:
            break
        }
    }
}
