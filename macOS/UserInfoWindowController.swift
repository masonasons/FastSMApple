//
//  UserInfoWindowController.swift
//  FastSM (macOS)
//
//  Dialog shown when pressing Enter on a user (in a followers/following list).
//  Reports the chosen action; spawning the resulting timeline happens in the
//  caller.
//

import AppKit
import FastSMCore

enum UserInfoAction {
    case viewPosts, followers, following, openInBrowser
}

@MainActor
final class UserInfoWindowController: NSWindowController {
    private let user: User
    private let onAction: (UserInfoAction) -> Void

    init(user: User, onAction: @escaping (UserInfoAction) -> Void) {
        self.user = user
        self.onAction = onAction
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = user.bestName
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, onDismiss: @escaping () -> Void) {
        parent.beginSheet(window!) { _ in onDismiss() }
    }

    /// All the profile info as multi-line text: name, handle, any flags, the bio,
    /// then follower/following/post counts.
    private var profileText: String {
        var lines: [String] = [user.bestName, "@\(user.acct)"]
        var flags: [String] = []
        if user.bot { flags.append("Bot") }
        if user.locked { flags.append("Locked account") }
        if !flags.isEmpty { lines.append(flags.joined(separator: " · ")) }
        let bio = HTMLStripper.strip(user.note)
        if !bio.isEmpty { lines.append(""); lines.append(bio) }
        lines.append("")
        lines.append("\(user.followersCount) followers · \(user.followingCount) following · \(user.statusesCount) posts")
        return lines.joined(separator: "\n")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // All the profile info (name, handle, flags, bio, counts) in a read-only,
        // selectable text view so VoiceOver can navigate it and the text can be
        // copied — instead of a static, unfocusable label.
        let infoScroll = NSTextView.scrollableTextView()
        infoScroll.translatesAutoresizingMaskIntoConstraints = false
        infoScroll.borderType = .bezelBorder
        infoScroll.hasVerticalScroller = true
        if let infoView = infoScroll.documentView as? NSTextView {
            infoView.isEditable = false
            infoView.isSelectable = true
            infoView.drawsBackground = true
            infoView.textContainerInset = NSSize(width: 6, height: 6)
            infoView.string = profileText
            infoView.setAccessibilityLabel("Profile")
        }
        stack.addArrangedSubview(infoScroll)
        NSLayoutConstraint.activate([
            infoScroll.widthAnchor.constraint(equalToConstant: 380),
            infoScroll.heightAnchor.constraint(equalToConstant: 140),
        ])

        for (title, action) in [("View Posts", UserInfoAction.viewPosts), ("Followers", .followers), ("Following", .following)] {
            let button = NSButton(title: title, target: self, action: #selector(chooseAction(_:)))
            button.tag = tag(for: action)
            button.bezelStyle = .rounded
            stack.addArrangedSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }

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

    private func tag(for action: UserInfoAction) -> Int {
        switch action {
        case .viewPosts: return 0
        case .followers: return 1
        case .following: return 2
        case .openInBrowser: return 3
        }
    }

    private func action(for tag: Int) -> UserInfoAction {
        switch tag {
        case 0: return .viewPosts
        case 1: return .followers
        case 2: return .following
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
