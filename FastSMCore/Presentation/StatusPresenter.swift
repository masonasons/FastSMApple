//
//  StatusPresenter.swift
//  FastSMCore
//
//  Builds the strings the apps show and, crucially, the spoken VoiceOver labels
//  for timeline rows. Centralizing this keeps the macOS (NSTableView) and iOS
//  (SwiftUI) presentations identical for screen-reader users. This is the Swift
//  analogue of FastSM's display templates.
//

import Foundation

public enum StatusPresenter {
    /// A compact, single-line summary for dense list rows:
    /// "Display Name (5m): post text".
    public static func compactLine(for status: Status, now: Date = Date(), emoji: EmojiPrefs = .none) -> String {
        let display = status.displayStatus
        let time = RelativeDate.compact(display.createdAt, now: now)
        let prefix = status.isBoost ? "\(status.account.bestName.strippingEmoji(emoji.name)) ♺ " : ""
        let body = display.hasContentWarning ? "[CW] \(display.spoilerText ?? "")" : display.text.strippingEmoji(emoji.post)
        return "\(prefix)\(display.account.bestName.strippingEmoji(emoji.name)) (\(time)): \(body)"
    }

    /// The full, comma-separated label read by VoiceOver, built from the user's
    /// configured field order/visibility (Settings → Speech).
    public static func accessibilityLabel(
        for status: Status, now: Date = Date(), emoji: EmojiPrefs = .none,
        speech: [SpeechItem<StatusSpeechField>] = SpeechConfig.current.status
    ) -> String {
        let display = status.displayStatus
        var parts: [String] = []
        for item in speech where item.enabled {
            if let part = string(for: item.field, status: status, display: display, now: now, emoji: emoji),
               !part.isEmpty {
                parts.append(part)
            }
        }
        return parts.joined(separator: ", ")
    }

    private static func string(for field: StatusSpeechField, status: Status, display: Status,
                               now: Date, emoji: EmojiPrefs) -> String? {
        switch field {
        case .boostedBy:
            return status.isBoost ? "\(status.account.bestName.strippingEmoji(emoji.name)) boosted" : nil
        case .author:
            return display.account.bestName.strippingEmoji(emoji.name)
        case .handle:
            return "@\(display.account.acct)"
        case .contentWarning:
            guard display.hasContentWarning, let spoiler = display.spoilerText, !spoiler.isEmpty else { return nil }
            return "Content warning: \(spoiler)"
        case .text:
            return display.text.isEmpty ? nil : display.text.strippingEmoji(emoji.post)
        case .quote:
            guard let quoted = display.quote?.status else { return nil }
            return "Quoting \(quoted.account.bestName.strippingEmoji(emoji.name)): \(quoted.text.strippingEmoji(emoji.post))"
        case .media:
            return display.mediaAttachments.isEmpty ? nil : mediaSummary(display.mediaAttachments)
        case .poll:
            guard let poll = display.poll else { return nil }
            return "Poll with \(poll.options.count) options"
        case .time:
            return RelativeDate.spoken(display.createdAt, now: now)
        case .stats:
            return statsSummary(display)
        case .favorited:
            return display.favourited ? "Favorited" : nil
        case .boosted:
            return display.boosted ? "Boosted" : nil
        case .visibility:
            return display.visibility?.displayName
        case .replyIndicator:
            return display.inReplyToID != nil ? "Reply" : nil
        case .source:
            // Intelligently included: only when the posting app/source is known.
            guard let app = display.applicationName, !app.isEmpty else { return nil }
            return "via \(app)"
        }
    }

    private static func mediaSummary(_ media: [MediaAttachment]) -> String {
        let described = media.compactMap { $0.description }.filter { !$0.isEmpty }
        if described.isEmpty {
            let noun = media.count == 1 ? "attachment" : "attachments"
            return "\(media.count) \(noun)"
        }
        return "Attachments: " + described.joined(separator: "; ")
    }

    private static func statsSummary(_ status: Status) -> String {
        func plural(_ count: Int, _ singular: String) -> String {
            "\(count) \(singular)\(count == 1 ? "" : "s")"
        }
        return [
            plural(status.repliesCount, "reply").replacingOccurrences(of: "replys", with: "replies"),
            plural(status.boostsCount, "boost"),
            plural(status.favouritesCount, "favorite"),
        ].joined(separator: ", ")
    }
}
