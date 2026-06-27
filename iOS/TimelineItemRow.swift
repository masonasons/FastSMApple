//
//  TimelineItemRow.swift
//  FastSM (iOS)
//
//  Renders a timeline row, which is either a status or a notification.
//

import SwiftUI
import FastSMCore

struct TimelineItemRow: View {
    let item: TimelineItem
    var demojify: Bool = false

    var body: some View {
        switch item {
        case .status(let status):
            StatusRow(status: status, demojify: demojify)
        case .notification(let notification):
            NotificationRow(notification: notification, demojify: demojify)
        case .user(let user):
            UserRow(user: user)
        }
    }
}

struct UserRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.bestName).font(.subheadline.bold())
            Text("@\(user.acct)").font(.caption).foregroundStyle(.secondary)
            let bio = HTMLStripper.strip(user.note)
            if !bio.isEmpty {
                Text(bio).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UserPresenter.accessibilityLabel(for: user))
    }
}

struct NotificationRow: View {
    let notification: FastSMCore.Notification
    var demojify: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(NotificationPresenter.compactLine(for: notification, demojify: demojify))
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NotificationPresenter.accessibilityLabel(for: notification, demojify: demojify))
    }

    private var symbol: String {
        switch notification.type {
        case .follow, .followRequest: return "person.badge.plus"
        case .favourite: return "star.fill"
        case .reblog: return "arrow.2.squarepath"
        case .mention: return "at"
        case .poll: return "chart.bar"
        case .status, .update: return "bell"
        case .unknown: return "bell"
        }
    }

    private var tint: Color {
        switch notification.type {
        case .favourite: return .yellow
        case .reblog: return .green
        case .mention: return .blue
        default: return .secondary
        }
    }
}
