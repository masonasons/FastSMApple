//
//  UserInfoWindowController.swift
//  FastSM (macOS)
//
//  Profile dialog for a user: shows the full profile text and offers navigation
//  (posts/followers/following) plus relationship actions (follow, mute, block,
//  hide boosts) whose labels reflect the current relationship.
//

import AppKit
import FastSMCore

enum UserInfoAction {
    case viewPosts, followers, following, openInBrowser
}

@MainActor
final class UserInfoWindowController: NSWindowController {
    private let user: User
    private let account: any SocialAccount
    private let onAction: (UserInfoAction) -> Void

    /// Set by the presenter so a failed relationship action can play the app's
    /// error earcon; falls back to a system beep when nil.
    var sound: SoundManager?

    /// The current relationship; nil until the async fetch returns.
    private var relationship: Relationship?

    private let followButton = NSButton()
    private let muteButton = NSButton()
    private let blockButton = NSButton()
    private let boostsButton = NSButton()

    init(user: User, account: any SocialAccount, onAction: @escaping (UserInfoAction) -> Void) {
        self.user = user
        self.account = account
        self.onAction = onAction
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = user.bestName
        buildUI()
        loadRelationship()
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
            infoScroll.widthAnchor.constraint(equalToConstant: 420),
            infoScroll.heightAnchor.constraint(equalToConstant: 130),
        ])

        // Navigation actions.
        let nav = NSStackView()
        nav.orientation = .horizontal
        nav.spacing = 8
        for (title, action) in [("View Posts", UserInfoAction.viewPosts), ("Followers", .followers), ("Following", .following)] {
            let button = NSButton(title: title, target: self, action: #selector(chooseAction(_:)))
            button.tag = tag(for: action)
            button.bezelStyle = .rounded
            nav.addArrangedSubview(button)
        }
        stack.addArrangedSubview(nav)

        // Relationship actions; labels filled in once the relationship loads.
        configure(followButton, action: #selector(toggleFollow(_:)))
        configure(muteButton, action: #selector(toggleMute(_:)))
        configure(blockButton, action: #selector(toggleBlock(_:)))
        configure(boostsButton, action: #selector(toggleBoosts(_:)))
        let actions = NSStackView(views: relationshipButtons())
        actions.orientation = .horizontal
        actions.spacing = 8
        stack.addArrangedSubview(actions)
        updateActionButtons()

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

    private func configure(_ button: NSButton, action: Selector) {
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    /// Boosts hiding is Mastodon-only, so omit that button where unsupported.
    private func relationshipButtons() -> [NSButton] {
        var buttons = [followButton, muteButton, blockButton]
        if account.features.hideBoosts { buttons.append(boostsButton) }
        return buttons
    }

    // MARK: Relationship

    private func loadRelationship() {
        Task { [weak self] in
            guard let self else { return }
            let fetched = try? await self.account.relationships(for: [self.user.id]).first
            self.relationship = fetched ?? Relationship(id: self.user.id)
            self.updateActionButtons()
        }
    }

    private func updateActionButtons() {
        let r = relationship ?? Relationship(id: user.id)
        followButton.title = (r.following ? UserAction.unfollow : .follow).title
        muteButton.title = (r.muting ? UserAction.unmute : .mute).title
        blockButton.title = (r.blocking ? UserAction.unblock : .block).title
        boostsButton.title = (r.showingReblogs ? UserAction.hideBoosts : .showBoosts).title
        // Only actionable once we know the real relationship.
        relationshipButtons().forEach { $0.isEnabled = (relationship != nil) }
    }

    @objc private func toggleFollow(_ sender: Any?) {
        perform(relationship?.following == true ? .unfollow : .follow) { $0.following.toggle() }
    }

    @objc private func toggleMute(_ sender: Any?) {
        perform(relationship?.muting == true ? .unmute : .mute) { $0.muting.toggle() }
    }

    @objc private func toggleBlock(_ sender: Any?) {
        perform(relationship?.blocking == true ? .unblock : .block) { $0.blocking.toggle() }
    }

    @objc private func toggleBoosts(_ sender: Any?) {
        perform(relationship?.showingReblogs == true ? .hideBoosts : .showBoosts) { $0.showingReblogs.toggle() }
    }

    /// Optimistically flip the relationship + relabel, perform the action, and
    /// re-sync from the server on failure.
    private func perform(_ action: UserAction, optimistic: (inout Relationship) -> Void) {
        var r = relationship ?? Relationship(id: user.id)
        optimistic(&r)
        relationship = r
        updateActionButtons()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.account.perform(action, on: self.user.id)
            } catch {
                // Roll the optimistic change back to the server's truth, then tell
                // the user exactly why the action failed (copyable), not just a beep.
                self.relationship = (try? await self.account.relationships(for: [self.user.id]).first)
                    ?? Relationship(id: self.user.id)
                self.updateActionButtons()
                ErrorAlert.present(error, context: action.title, sound: self.sound, in: self.window)
            }
        }
    }

    // MARK: Navigation

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
