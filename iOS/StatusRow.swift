//
//  StatusRow.swift
//  FastSM (iOS)
//
//  A single timeline row. The visible layout is light; the screen-reader label
//  is the full StatusPresenter string so VoiceOver users hear one coherent unit.
//

import SwiftUI
import FastSMCore

struct StatusRow: View {
    let status: Status
    var demojify: Bool = false

    private var display: Status { status.displayStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.isBoost {
                Text("\(status.account.bestName) boosted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(display.account.bestName)
                    .font(.subheadline.bold())
                Text("@\(display.account.acct)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(RelativeDate.compact(display.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if display.hasContentWarning, let spoiler = display.spoilerText {
                Text("⚠️ \(spoiler)")
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
            }

            Text(display.text.demojified(if: demojify))
                .font(.body)

            if !display.mediaAttachments.isEmpty {
                Label("\(display.mediaAttachments.count) attachment\(display.mediaAttachments.count == 1 ? "" : "s")",
                      systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                stat("arrow.2.squarepath", display.boostsCount, active: display.boosted, color: .green)
                stat("star", display.favouritesCount, active: display.favourited, color: .yellow)
                stat("bubble.right", display.repliesCount, active: false, color: .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatusPresenter.accessibilityLabel(for: status, demojify: demojify))
    }

    private func stat(_ symbol: String, _ count: Int, active: Bool, color: Color) -> some View {
        Label("\(count)", systemImage: symbol)
            .foregroundStyle(active ? color : .secondary)
    }
}
