//
//  NotificationPresenter.swift
//  FastSMCore
//
//  Display + VoiceOver strings for notification rows, mirroring StatusPresenter
//  for the Notifications timeline.
//

import Foundation

public enum NotificationPresenter {
    private static func actionPhrase(_ type: Notification.Kind) -> String {
        switch type {
        case .follow: return "followed you"
        case .followRequest: return "requested to follow you"
        case .favourite: return "favorited your post"
        case .reblog: return "boosted your post"
        case .mention: return "mentioned you"
        case .poll: return "ran a poll that ended"
        case .status: return "posted"
        case .update: return "edited a post"
        case .unknown: return "sent a notification"
        }
    }

    public static func compactLine(for notification: Notification, now: Date = Date(), demojify: Bool = false) -> String {
        let who = notification.account.bestName
        let phrase = actionPhrase(notification.type)
        let time = RelativeDate.compact(notification.createdAt, now: now)
        if let text = notification.status?.displayStatus.text, !text.isEmpty {
            return "\(who) \(phrase) (\(time)): \(text.demojified(if: demojify))"
        }
        return "\(who) \(phrase) (\(time))"
    }

    public static func accessibilityLabel(for notification: Notification, now: Date = Date(), demojify: Bool = false) -> String {
        var parts: [String] = []
        parts.append("\(notification.account.bestName) \(actionPhrase(notification.type))")
        if !notification.account.acct.isEmpty {
            parts.append("@\(notification.account.acct)")
        }
        if let text = notification.status?.displayStatus.text, !text.isEmpty {
            parts.append(text.demojified(if: demojify))
        }
        parts.append(RelativeDate.spoken(notification.createdAt, now: now))
        return parts.joined(separator: ", ")
    }
}

public extension TimelineItem {
    /// One-line summary appropriate to the item type.
    func compactLine(now: Date = Date(), demojify: Bool = false) -> String {
        switch self {
        case .status(let status): return StatusPresenter.compactLine(for: status, now: now, demojify: demojify)
        case .notification(let notification): return NotificationPresenter.compactLine(for: notification, now: now, demojify: demojify)
        case .user(let user): return UserPresenter.compactLine(for: user)
        }
    }

    /// Full spoken VoiceOver label appropriate to the item type.
    func accessibilityLabel(now: Date = Date(), demojify: Bool = false) -> String {
        switch self {
        case .status(let status): return StatusPresenter.accessibilityLabel(for: status, now: now, demojify: demojify)
        case .notification(let notification): return NotificationPresenter.accessibilityLabel(for: notification, now: now, demojify: demojify)
        case .user(let user): return UserPresenter.accessibilityLabel(for: user)
        }
    }
}
