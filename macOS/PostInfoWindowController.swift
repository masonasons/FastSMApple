//
//  PostInfoWindowController.swift
//  FastSM (macOS)
//
//  The post info dialog shown when pressing Enter on a post. Presents the post
//  text plus action buttons; the chosen action is reported back to the caller,
//  which performs it (so spawning timelines etc. lives in one place).
//

import AppKit
import FastSMCore

enum PostAction {
    case reply, boost, favorite, quote
    case viewThread, viewAuthor, authorFollowers, authorFollowing, openInBrowser
}

@MainActor
final class PostInfoWindowController: NSWindowController {
    private let status: Status
    private let onAction: (PostAction) -> Void

    init(status: Status, onAction: @escaping (PostAction) -> Void) {
        self.status = status
        self.onAction = onAction
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Post"
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A readable, multi-line rendering of the post for review.
    private var reviewText: String {
        var lines: [String] = []
        lines.append("\(status.account.bestName) (@\(status.account.acct))")
        lines.append(RelativeDate.spoken(status.createdAt))
        if status.hasContentWarning, let cw = status.spoilerText, !cw.isEmpty {
            lines.append("Content warning: \(cw)")
        }
        lines.append("")
        lines.append(status.text)
        let descriptions = status.mediaAttachments.compactMap { $0.description }.filter { !$0.isEmpty }
        if !status.mediaAttachments.isEmpty {
            lines.append("")
            lines.append(descriptions.isEmpty
                ? "\(status.mediaAttachments.count) attachment(s)"
                : "Attachments: " + descriptions.joined(separator: "; "))
        }
        lines.append("")
        lines.append("\(status.repliesCount) replies, \(status.boostsCount) boosts, \(status.favouritesCount) favorites")
        return lines.joined(separator: "\n")
    }

    func beginSheet(for parent: NSWindow, onDismiss: @escaping () -> Void) {
        parent.beginSheet(window!) { _ in onDismiss() }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Read-only, selectable text view so the post is easy to review and copy.
        let textScroll = NSScrollView()
        textScroll.borderType = .bezelBorder
        textScroll.hasVerticalScroller = true
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = reviewText
        textView.setAccessibilityLabel("Post text")
        textScroll.documentView = textView
        stack.addArrangedSubview(textScroll)
        NSLayoutConstraint.activate([
            textScroll.widthAnchor.constraint(equalToConstant: 420),
            textScroll.heightAnchor.constraint(equalToConstant: 150),
        ])

        let grid = NSStackView()
        grid.orientation = .horizontal
        grid.spacing = 8
        let leftColumn = buttonColumn([
            ("Reply", .reply), ("Boost", .boost), ("Favorite", .favorite), ("Quote", .quote),
        ])
        let rightColumn = buttonColumn([
            ("View Thread", .viewThread), ("View Author", .viewAuthor),
            ("Author's Followers", .authorFollowers), ("Author's Following", .authorFollowing),
        ])
        grid.addArrangedSubview(leftColumn)
        grid.addArrangedSubview(rightColumn)
        stack.addArrangedSubview(grid)

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        let browser = NSButton(title: "Open in Browser", target: self, action: #selector(openInBrowser(_:)))
        bottom.addArrangedSubview(browser)
        bottom.addArrangedSubview(NSView())
        let close = NSButton(title: "Close", target: self, action: #selector(close(_:)))
        close.keyEquivalent = "\u{1b}"
        bottom.addArrangedSubview(close)
        stack.addArrangedSubview(bottom)
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
    }

    private func buttonColumn(_ entries: [(String, PostAction)]) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        for (title, action) in entries {
            let button = NSButton(title: title, target: self, action: #selector(chooseAction(_:)))
            button.tag = actionTag(action)
            button.bezelStyle = .rounded
            column.addArrangedSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }
        return column
    }

    // Map actions to/from button tags.
    private func actionTag(_ action: PostAction) -> Int {
        switch action {
        case .reply: return 0
        case .boost: return 1
        case .favorite: return 2
        case .quote: return 3
        case .viewThread: return 4
        case .viewAuthor: return 5
        case .authorFollowers: return 6
        case .authorFollowing: return 7
        case .openInBrowser: return 8
        }
    }

    private func action(for tag: Int) -> PostAction {
        switch tag {
        case 0: return .reply
        case 1: return .boost
        case 2: return .favorite
        case 3: return .quote
        case 4: return .viewThread
        case 5: return .viewAuthor
        case 6: return .authorFollowers
        case 7: return .authorFollowing
        default: return .openInBrowser
        }
    }

    @objc private func chooseAction(_ sender: NSButton) {
        let chosen = action(for: sender.tag)
        dismiss()
        onAction(chosen)
    }

    @objc private func openInBrowser(_ sender: Any?) {
        dismiss()
        onAction(.openInBrowser)
    }

    @objc private func close(_ sender: Any?) { dismiss() }

    private func dismiss() {
        window?.sheetParent?.endSheet(window!)
    }
}
