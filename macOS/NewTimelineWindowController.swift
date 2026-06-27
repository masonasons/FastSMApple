//
//  NewTimelineWindowController.swift
//  FastSM (macOS)
//
//  ⌘T: open a timeline — Local, Federated, a user's timeline, a hashtag,
//  favorites, or bookmarks (options depend on the active account's platform).
//

import AppKit
import FastSMCore

@MainActor
final class NewTimelineWindowController: NSWindowController {
    private let services: AppServices

    private enum Choice { case local, federated, user, hashtag, search, favorites, bookmarks, list, trending, feed, remoteLocal, remoteUser }

    private let typePopup = NSPopUpButton()
    private let valueField = NSTextField()
    private let valueLabel = NSTextField(labelWithString: "Handle:")
    private let valueRow = NSStackView()
    private let listPopup = NSPopUpButton()
    private let listRow = NSStackView()
    private let searchKindPopup = NSPopUpButton()
    private let kindRow = NSStackView()
    private let feedPopup = NSPopUpButton()
    private let feedRow = NSStackView()
    private let openButton = NSButton()
    private let errorLabel = NSTextField(labelWithString: "")

    private var options: [Choice] = []
    private var lists: [TimelineList] = []
    private var feeds: [TimelineList] = []

    init(services: AppServices) {
        self.services = services
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "New Timeline"
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginSheet(for parent: NSWindow, onDismiss: @escaping () -> Void) {
        parent.beginSheet(window!) { _ in onDismiss() }
        window?.makeFirstResponder(typePopup)
    }

    private var selected: Choice { options.indices.contains(typePopup.indexOfSelectedItem) ? options[typePopup.indexOfSelectedItem] : .user }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Build the available options for this account's platform.
        let isMastodon = services.activeAccount?.platform == .mastodon
        var entries: [(String, Choice)] = []
        if isMastodon {
            entries.append(("Local Timeline", .local))
            entries.append(("Federated Timeline", .federated))
        }
        entries.append(("User Timeline", .user))
        entries.append(("Hashtag", .hashtag))
        entries.append(("Search", .search))
        entries.append(("Favorites", .favorites))
        if isMastodon {
            entries.append(("Bookmarks", .bookmarks))
            entries.append(("List", .list))
            entries.append(("Trending", .trending))
            entries.append(("Remote Instance Timeline", .remoteLocal))
            entries.append(("Remote User Timeline", .remoteUser))
        } else {
            entries.append(("Feed", .feed))
        }
        options = entries.map { $0.1 }

        let typeRow = NSStackView()
        typeRow.orientation = .horizontal
        typeRow.spacing = 8
        typeRow.addArrangedSubview(NSTextField(labelWithString: "Timeline:"))
        for (title, _) in entries { typePopup.addItem(withTitle: title) }
        typePopup.target = self
        typePopup.action = #selector(typeChanged(_:))
        typePopup.setAccessibilityLabel("Timeline type")
        typeRow.addArrangedSubview(typePopup)
        stack.addArrangedSubview(typeRow)

        valueRow.orientation = .horizontal
        valueRow.spacing = 8
        valueRow.addArrangedSubview(valueLabel)
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        valueRow.addArrangedSubview(valueField)
        stack.addArrangedSubview(valueRow)

        listRow.orientation = .horizontal
        listRow.spacing = 8
        listRow.addArrangedSubview(NSTextField(labelWithString: "List:"))
        listPopup.setAccessibilityLabel("List")
        listRow.addArrangedSubview(listPopup)
        listRow.isHidden = true
        stack.addArrangedSubview(listRow)

        kindRow.orientation = .horizontal
        kindRow.spacing = 8
        kindRow.addArrangedSubview(NSTextField(labelWithString: "Search for:"))
        searchKindPopup.addItem(withTitle: "Posts")
        searchKindPopup.addItem(withTitle: "People")
        searchKindPopup.setAccessibilityLabel("Search for")
        kindRow.addArrangedSubview(searchKindPopup)
        kindRow.isHidden = true
        stack.addArrangedSubview(kindRow)

        feedRow.orientation = .horizontal
        feedRow.spacing = 8
        feedRow.addArrangedSubview(NSTextField(labelWithString: "Feed:"))
        feedPopup.setAccessibilityLabel("Feed")
        feedRow.addArrangedSubview(feedPopup)
        feedRow.isHidden = true
        stack.addArrangedSubview(feedRow)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(errorLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        openButton.title = "Open"
        openButton.target = self
        openButton.action = #selector(open(_:))
        openButton.keyEquivalent = "\r"
        openButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(openButton)
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        // Add to the stack BEFORE constraining to it (shared ancestor required).
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true

        updateValueRow()

        // Fetch lists (Mastodon) / saved feeds (Bluesky) to populate the pickers.
        if let account = services.activeAccount {
            if isMastodon {
                Task {
                    guard let fetched = try? await account.lists() else { return }
                    self.lists = fetched
                    self.listPopup.removeAllItems()
                    self.listPopup.addItems(withTitles: fetched.isEmpty ? ["No lists"] : fetched.map(\.title))
                }
            } else {
                Task {
                    guard let fetched = try? await account.savedFeeds() else { return }
                    self.feeds = fetched
                    self.feedPopup.removeAllItems()
                    self.feedPopup.addItems(withTitles: fetched.isEmpty ? ["No feeds"] : fetched.map(\.title))
                }
            }
        }
    }

    private func updateValueRow() {
        listRow.isHidden = selected != .list
        kindRow.isHidden = selected != .search
        feedRow.isHidden = selected != .feed
        switch selected {
        case .user:
            valueRow.isHidden = false
            valueLabel.stringValue = "Handle:"
            valueField.placeholderString = "@user@instance or handle.bsky.social"
            valueField.setAccessibilityLabel("User handle")
        case .hashtag:
            valueRow.isHidden = false
            valueLabel.stringValue = "Tag:"
            valueField.placeholderString = "swift"
            valueField.setAccessibilityLabel("Hashtag")
        case .search:
            valueRow.isHidden = false
            valueLabel.stringValue = "Query:"
            valueField.placeholderString = "search terms"
            valueField.setAccessibilityLabel("Search query")
        case .remoteLocal:
            valueRow.isHidden = false
            valueLabel.stringValue = "Instance:"
            valueField.placeholderString = "mastodon.social"
            valueField.setAccessibilityLabel("Instance domain")
        case .remoteUser:
            valueRow.isHidden = false
            valueLabel.stringValue = "User:"
            valueField.placeholderString = "user@instance.tld"
            valueField.setAccessibilityLabel("User at instance")
        default:
            valueRow.isHidden = true
        }
    }

    @objc private func typeChanged(_ sender: NSPopUpButton) {
        updateValueRow()
        if !valueRow.isHidden { window?.makeFirstResponder(valueField) }
    }

    @objc private func cancel(_ sender: Any?) { window?.sheetParent?.endSheet(window!) }

    @objc private func open(_ sender: Any?) {
        guard let account = services.activeAccount else { return }
        let value = valueField.stringValue.trimmingCharacters(in: .whitespaces)
        switch selected {
        case .local: services.showTimeline(source: .local); dismissSheet()
        case .federated: services.showTimeline(source: .federated); dismissSheet()
        case .favorites: services.spawnTimeline(.favorites, for: account); dismissSheet()
        case .bookmarks: services.spawnTimeline(.bookmarks, for: account); dismissSheet()
        case .trending: services.spawnTimeline(.trending, for: account); dismissSheet()
        case .hashtag:
            let tag = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard !tag.isEmpty else { return }
            services.spawnTimeline(.hashtag(tag: tag), for: account)
            dismissSheet()
        case .search:
            guard !value.isEmpty else { return }
            let kind: SearchKind = searchKindPopup.indexOfSelectedItem == 1 ? .users : .posts
            services.spawnTimeline(.search(query: value, kind: kind), for: account)
            dismissSheet()
        case .list:
            let index = listPopup.indexOfSelectedItem
            guard lists.indices.contains(index) else { return }
            let list = lists[index]
            services.spawnTimeline(.list(id: list.id, title: list.title), for: account)
            dismissSheet()
        case .feed:
            let index = feedPopup.indexOfSelectedItem
            guard feeds.indices.contains(index) else { return }
            let feed = feeds[index]
            services.spawnTimeline(.feed(uri: feed.id, title: feed.title), for: account)
            dismissSheet()
        case .remoteLocal:
            let instance = value.hasPrefix("@") ? String(value.dropFirst()) : value
            guard !instance.isEmpty else { return }
            services.spawnTimeline(.remoteLocal(instance: instance), for: account)
            dismissSheet()
        case .remoteUser:
            var handle = value
            if handle.hasPrefix("@") { handle.removeFirst() }
            guard let at = handle.lastIndex(of: "@") else { errorLabel.stringValue = "Use the form user@instance.tld"; return }
            let username = String(handle[handle.startIndex..<at])
            let instance = String(handle[handle.index(after: at)...])
            guard !username.isEmpty, !instance.isEmpty else { return }
            services.spawnTimeline(.remoteUser(instance: instance, username: username, title: "@\(handle)"), for: account)
            dismissSheet()
        case .user:
            guard !value.isEmpty else { return }
            openButton.isEnabled = false
            errorLabel.stringValue = "Looking up…"
            Task {
                do {
                    let user = try await account.resolveUser(handle: value)
                    services.spawnTimeline(.userPosts(userID: user.id, title: "@\(user.acct)"), for: account)
                    dismissSheet()
                } catch {
                    openButton.isEnabled = true
                    errorLabel.stringValue = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func dismissSheet() { window?.sheetParent?.endSheet(window!) }
}
