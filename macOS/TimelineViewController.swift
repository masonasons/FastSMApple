//
//  TimelineViewController.swift
//  FastSM (macOS)
//
//  The home timeline as a view-based NSTableView — the fastest, most VoiceOver-
//  friendly way to present a navigable list on the Mac. Each row exposes a rich
//  accessibility label built by StatusPresenter. Arrow-key navigation is native;
//  actions are driven from the main menu via the first responder.
//

import AppKit
import FastSMCore

@MainActor
final class TimelineViewController: NSViewController {
    private let services: AppServices
    private let tableView = NavigableTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let cellIdentifier = NSUserInterfaceItemIdentifier("StatusCell")
    private var composeController: ComposeWindowController?
    private var postInfoController: PostInfoWindowController?
    private var userInfoController: UserInfoWindowController?

    /// Called when the user presses Tab to move to the timelines pane.
    var onMoveToTimelines: (() -> Void)?

    /// The account whose context spawned timelines (threads, user lists) belong to.
    private var currentAccount: (any SocialAccount)? { services.selectedRef?.account }

    private var items: [TimelineItem] { services.selectedController?.items ?? [] }

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        column.title = "Posts"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.usesAutomaticRowHeights = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.style = .inset
        tableView.setAccessibilityLabel("Posts")
        tableView.onTab = { [weak self] in self?.onMoveToTimelines?() }
        tableView.onLeftArrow = { [weak self] in
            self?.services.playEarcon(.navigate)
            self?.services.previousTimeline()
        }
        tableView.onRightArrow = { [weak self] in
            self?.services.playEarcon(.navigate)
            self?.services.nextTimeline()
        }
        tableView.onReturn = { [weak self] in self?.handleReturn() }
        tableView.onCommandReturn = { [weak self] in self?.openLinksForSelection(nil) }
        tableView.onShiftReturn = { [weak self] in self?.playMediaForSelection(nil) }
        tableView.onSpace = { [weak self] in self?.openThreadForSelection() }
        tableView.onDelete = { [weak self] in
            guard let self else { return }
            self.services.closeCurrentTimeline()
            self.focusTable()
        }
        tableView.onCommandDelete = { [weak self] in self?.clearTimeline(nil) }
        tableView.onBoundary = { [weak self] in self?.services.playEarcon(.boundary) }
        tableView.onCharacter = { [weak self] character in
            self?.handleShortcut(character) ?? false
        }
        tableView.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.stringValue = "Loading…"

        container.addSubview(scrollView)
        container.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        services.onSelectedItemsChanged = { [weak self] in self?.reload() }
        services.onError = { [weak self] error in self?.present(error: error) }
    }

    private var isRestoringSelection = false
    /// The item ids currently rendered, so a no-op reload (e.g. a background
    /// refresh that added nothing) doesn't rebuild the table and make VoiceOver
    /// re-announce the focused row over and over.
    private var renderedIDs: [String] = []

    func reload() {
        // Only user lists allow multi-select (for batch follow/mute/block); post
        // timelines stay single-select so navigation drives the saved position.
        tableView.allowsMultipleSelection = services.selectedRef?.source.isUserList ?? false
        let ids = items.map(\.id)
        if ids != renderedIDs {
            renderedIDs = ids
            tableView.reloadData()
            restoreSelection()
        }
        updateStatusLabel()
    }

    /// Restore the selected row to the current timeline's remembered item (by id),
    /// so each timeline keeps its place across switches and restarts. Falls back
    /// to the first row. Only moves the selection if it actually needs to change,
    /// so it doesn't trigger a redundant VoiceOver announcement.
    private func restoreSelection() {
        isRestoringSelection = true
        defer { isRestoringSelection = false }
        let targetRow: Int
        if let targetID = services.selectedController?.selectedID,
           let index = items.firstIndex(where: { $0.id == targetID }) {
            targetRow = index
        } else if !items.isEmpty {
            targetRow = 0
            // No remembered item (or it's gone): adopt the top item as the new
            // position so future incoming posts track it instead of the index.
            services.recordSelection(items[0].id, fromUser: false)
        } else {
            return
        }
        if tableView.selectedRow != targetRow {
            tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        }
        tableView.scrollRowToVisible(targetRow)
    }

    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    private func updateStatusLabel() {
        if services.selectedController?.isLoading == true {
            statusLabel.stringValue = "Loading…"
        } else if items.isEmpty {
            statusLabel.stringValue = "No posts. Press ⌘R to refresh or add an account."
        } else {
            statusLabel.stringValue = "\(items.count) items"
        }
    }

    private var selectedItem: TimelineItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    /// The actionable status of the selected row (a post, or the post a
    /// notification refers to), if any.
    private var selectedStatus: Status? { selectedItem?.actionableStatus }

    // MARK: Actions (menu → first responder)

    @objc func refreshTimeline(_ sender: Any?) {
        // No earcon here — a refresh chimes the timeline's "new posts" sound only
        // if it actually receives new posts (see AppServices.playNewItems).
        Task { await services.selectedController?.refresh() }
    }

    @objc func composePost(_ sender: Any?) {
        guard let account = currentAccount ?? services.accountStore.selectedAccount else {
            present(error: PlatformError.notAuthenticated)
            return
        }
        presentCompose(account: account, replyTo: nil, quoting: nil)
    }

    @objc func replyToSelection(_ sender: Any?) { composeAgainstSelection(quoting: false) }

    /// Reply to / quote the selected post, resolving it to the local instance
    /// first if it came from a remote-instance timeline.
    private func composeAgainstSelection(quoting: Bool) {
        guard let account = currentAccount, let status = selectedStatus else { return }
        let row = tableView.selectedRow
        if status.instanceURL == nil {
            presentCompose(account: account, replyTo: quoting ? nil : status, quoting: quoting ? status : nil)
            return
        }
        Task {
            let resolved = await services.selectedController?.resolvedStatus(at: row) ?? status
            presentCompose(account: account, replyTo: quoting ? nil : resolved, quoting: quoting ? resolved : nil)
        }
    }

    @objc func boostSelection(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, let status = selectedItem?.actionableStatus else { return }
        let boosting = !status.boosted
        let act = { [weak self] in
            // FastSM has no un-repost sound; only cue when boosting.
            if boosting { self?.services.playEarcon(.boost) }
            Task { await self?.services.selectedController?.toggleBoost(at: row) }
        }
        if boosting, services.settings.settings.confirmBoost {
            confirm(message: "Boost this post?", confirmTitle: "Boost", perform: act)
        } else { act() }
    }

    @objc func favoriteSelection(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, let status = selectedItem?.actionableStatus else { return }
        let favoriting = !status.favourited
        let act = { [weak self] in
            self?.services.playEarcon(favoriting ? .favorite : .unfavorite)
            Task { await self?.services.selectedController?.toggleFavorite(at: row) }
        }
        if favoriting, services.settings.settings.confirmFavorite {
            confirm(message: "Favorite this post?", confirmTitle: "Favorite", perform: act)
        } else { act() }
    }

    @objc func clearTimeline(_ sender: Any?) {
        let act = { [weak self] in
            guard let self else { return }
            self.services.playEarcon(.delete)
            Task { await self.services.selectedController?.clear() }
        }
        if services.settings.settings.confirmClearTimeline {
            confirm(
                message: "Clear this timeline?",
                info: "This removes the loaded posts and this timeline's cache. Refresh to load them again.",
                confirmTitle: "Clear",
                perform: act
            )
        } else { act() }
    }

    private func confirm(message: String, info: String = "", confirmTitle: String, perform: @escaping () -> Void) {
        guard let window = view.window else { perform(); return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { perform() }
        }
    }

    @objc func quoteSelection(_ sender: Any?) { composeAgainstSelection(quoting: true) }

    @objc func openSelectionInBrowser(_ sender: Any?) {
        guard let url = selectedStatus?.displayStatus.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showPostInfo(_ sender: Any?) { showInfoForSelection() }
    @objc func viewThread(_ sender: Any?) { openThreadForSelection() }

    @objc func viewAuthorOfSelection(_ sender: Any?) {
        guard let account = currentAccount, let status = selectedStatus else { return }
        spawn(.userPosts(userID: status.account.id, title: "@\(status.account.acct)"), for: account)
    }

    @objc func editSelection(_ sender: Any?) {
        guard canEditSelection, let account = currentAccount, let status = selectedStatus else {
            services.sound.play(.error)
            return
        }
        presentCompose(account: account, replyTo: nil, quoting: nil, editing: status)
    }

    private var mediaPlayer: MediaPlayerWindowController?

    /// ⌘Return: pick a link from the post (text links, card, media, post URL).
    @objc func openLinksForSelection(_ sender: Any?) {
        guard let status = selectedStatus else { return }
        let links = PostLinks.links(for: status)
        guard !links.isEmpty else { services.sound.play(.error); return }
        let menu = NSMenu(title: "Open Link")
        for link in links {
            let item = menu.addItem(withTitle: link.title, action: #selector(openLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link.url
        }
        popUpAtSelectedRow(menu)
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    /// Shift+Return: play the post's video/audio (a menu if there's more than one).
    @objc func playMediaForSelection(_ sender: Any?) {
        guard let status = selectedStatus else { return }
        let media = PostLinks.playableMedia(for: status)
        guard !media.isEmpty else { services.sound.play(.error); return }
        if media.count == 1, let url = media[0].url {
            play(url: url, title: media[0].description ?? "Media")
            return
        }
        let menu = NSMenu(title: "Play Media")
        for (index, item) in media.enumerated() {
            guard let url = item.url else { continue }
            let title = item.description?.isEmpty == false ? item.description! : "\(item.type.rawValue.capitalized) \(index + 1)"
            let menuItem = menu.addItem(withTitle: title, action: #selector(playMediaItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = url
        }
        popUpAtSelectedRow(menu)
    }

    @objc private func playMediaItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { play(url: url, title: sender.title) }
    }

    private func play(url: URL, title: String) {
        let controller = MediaPlayerWindowController(url: url, title: title)
        controller.onClose = { [weak self] in self?.mediaPlayer = nil }
        mediaPlayer = controller
        controller.show()
    }

    private func popUpAtSelectedRow(_ menu: NSMenu) {
        let row = tableView.selectedRow
        let rowRect = row >= 0 ? tableView.rect(ofRow: row) : tableView.visibleRect
        let point = NSPoint(x: rowRect.minX + 8, y: rowRect.maxY)
        menu.popUp(positioning: nil, at: point, in: tableView)
    }

    @objc func viewSelectedUserPosts(_ sender: Any?) {
        guard let account = currentAccount, let user = selectedItem?.user else { return }
        spawn(.userPosts(userID: user.id, title: "@\(user.acct)"), for: account)
    }

    @objc func viewSelectedUserFollowers(_ sender: Any?) {
        guard let account = currentAccount, let user = selectedItem?.user else { return }
        spawn(.followers(userID: user.id, title: "Followers: @\(user.acct)"), for: account)
    }

    @objc func viewSelectedUserFollowing(_ sender: Any?) {
        guard let account = currentAccount, let user = selectedItem?.user else { return }
        spawn(.following(userID: user.id, title: "Following: @\(user.acct)"), for: account)
    }

    // MARK: User actions (single + batch)

    /// Users in the current (possibly multiple) selection.
    private var selectedUsers: [User] {
        tableView.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].user : nil }
    }

    /// Enter on a user list pops a menu of follow/mute/block actions for the
    /// selected user(s); on other timelines it opens the info dialog.
    private func handleReturn() {
        if services.selectedRef?.source.isUserList == true, !selectedUsers.isEmpty {
            presentUserActions(nil)
        } else {
            showInfoForSelection()
        }
    }

    @objc private func presentUserActions(_ sender: Any?) {
        guard let account = currentAccount else { return }
        let count = selectedUsers.count
        guard count > 0 else { return }
        let menu = NSMenu(title: "User Actions")
        for action in UserAction.applicable(to: account) {
            let title = count > 1 ? "\(action.title) (\(count))" : action.title
            let item = menu.addItem(withTitle: title, action: #selector(applyUserAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
        }
        popUpAtSelectedRow(menu)
    }

    @objc private func applyUserAction(_ sender: NSMenuItem) {
        guard let account = currentAccount,
              let raw = sender.representedObject as? String,
              let action = UserAction(rawValue: raw) else { return }
        let ids = selectedUsers.map(\.id)
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            var failures = 0
            for id in ids {
                do { try await account.perform(action, on: id) } catch { failures += 1 }
            }
            guard let self else { return }
            if failures > 0 {
                self.present(error: PlatformError.message("\(action.title) failed for \(failures) of \(ids.count) user\(ids.count == 1 ? "" : "s")."))
            } else {
                self.announce("\(action.title): \(ids.count) user\(ids.count == 1 ? "" : "s")")
            }
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: view.window ?? NSApp, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Right-click menu

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < items.count else { return nil }
        // Act on the right-clicked row.
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let item = items[row]
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let menuItem = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            menuItem.target = self
        }
        if let status = item.actionableStatus {
            add("Reply", #selector(replyToSelection(_:)))
            add(status.boosted ? "Unboost" : "Boost", #selector(boostSelection(_:)))
            add(status.favourited ? "Unfavorite" : "Favorite", #selector(favoriteSelection(_:)))
            add("Quote", #selector(quoteSelection(_:)))
            if canEditSelection { add("Edit", #selector(editSelection(_:))) }
            menu.addItem(.separator())
            if !PostLinks.links(for: status).isEmpty { add("Open Link…", #selector(openLinksForSelection(_:))) }
            if !PostLinks.playableMedia(for: status).isEmpty { add("Play Media…", #selector(playMediaForSelection(_:))) }
            add("View Thread", #selector(viewThread(_:)))
            add("View Author", #selector(viewAuthorOfSelection(_:)))
            add("Post Info…", #selector(showPostInfo(_:)))
            add("Open in Browser", #selector(openSelectionInBrowser(_:)))
        } else if item.user != nil {
            add("View Posts", #selector(viewSelectedUserPosts(_:)))
            add("Followers", #selector(viewSelectedUserFollowers(_:)))
            add("Following", #selector(viewSelectedUserFollowing(_:)))
            if let account = currentAccount {
                menu.addItem(.separator())
                for userAction in UserAction.applicable(to: account) {
                    let menuItem = menu.addItem(withTitle: userAction.title, action: #selector(applyUserAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = userAction.rawValue
                }
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    // MARK: Single-key shortcuts (R/B/Q/F), Return, Space

    private func handleShortcut(_ character: Character) -> Bool {
        switch character {
        case "r", "R": replyToSelection(nil); return true
        case "b", "B": boostSelection(nil); return true
        case "q", "Q": quoteSelection(nil); return true
        case "f", "F": favoriteSelection(nil); return true
        case "e", "E": editSelection(nil); return true
        case "u", "U": openUserTimelineForSelection(nil); return true
        default: return false
        }
    }

    /// U: open the focused post's author's timeline, or a menu of all users in
    /// the post (author + mentions) if there's more than one.
    @objc func openUserTimelineForSelection(_ sender: Any?) {
        guard let account = currentAccount, let status = selectedStatus else { return }
        var seen = Set<String>()
        var users: [(id: String, acct: String)] = []
        func add(_ id: String, _ acct: String) {
            guard !id.isEmpty, !seen.contains(id) else { return }
            seen.insert(id); users.append((id, acct))
        }
        add(status.account.id, status.account.acct)
        for mention in status.mentions { add(mention.id, mention.acct) }
        guard !users.isEmpty else { return }
        if users.count == 1 {
            spawn(.userPosts(userID: users[0].id, title: "@\(users[0].acct)"), for: account)
            return
        }
        let menu = NSMenu(title: "User Timeline")
        for user in users {
            let item = menu.addItem(withTitle: "@\(user.acct)", action: #selector(openUserFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = user.id
        }
        popUpAtSelectedRow(menu)
    }

    @objc private func openUserFromMenu(_ sender: NSMenuItem) {
        guard let account = currentAccount, let id = sender.representedObject as? String else { return }
        spawn(.userPosts(userID: id, title: sender.title), for: account)
    }

    /// Whether the selected post can be edited (own post, platform supports it).
    private var canEditSelection: Bool {
        guard let account = currentAccount, let status = selectedStatus else { return false }
        return account.features.editing && status.account.id == account.me.id
    }

    /// Enter: a post info dialog, or a user info dialog for user rows.
    private func showInfoForSelection() {
        guard let item = selectedItem else { return }
        switch item {
        case .user(let user):
            presentUserInfo(user)
        default:
            if let status = item.actionableStatus { presentPostInfo(status) }
        }
    }

    /// Space: view the thread for a post, or the user's posts for a user row.
    private func openThreadForSelection() {
        guard let account = currentAccount, let item = selectedItem else { return }
        switch item {
        case .user(let user):
            spawn(.userPosts(userID: user.id, title: "@\(user.acct)"), for: account)
        default:
            guard let status = item.actionableStatus else { return }
            spawn(.thread(statusID: status.id, title: "Thread: \(status.account.bestName)"), for: account)
        }
    }

    private func spawn(_ source: TimelineSource, for account: any SocialAccount) {
        services.spawnTimeline(source, for: account)
        focusTable()
    }

    // MARK: Dialogs

    private func presentPostInfo(_ status: Status) {
        guard let window = view.window else { return }
        let controller = PostInfoWindowController(status: status) { [weak self] action in
            self?.handle(action, for: status)
        }
        postInfoController = controller
        controller.beginSheet(for: window) { [weak self] in self?.postInfoController = nil }
    }

    private func presentUserInfo(_ user: User) {
        guard let window = view.window else { return }
        let controller = UserInfoWindowController(user: user) { [weak self] action in
            self?.handle(action, for: user)
        }
        userInfoController = controller
        controller.beginSheet(for: window) { [weak self] in self?.userInfoController = nil }
    }

    private func handle(_ action: PostAction, for status: Status) {
        guard let account = currentAccount else { return }
        switch action {
        case .reply: presentCompose(account: account, replyTo: status, quoting: nil)
        case .quote: presentCompose(account: account, replyTo: nil, quoting: status)
        case .boost: boostSelection(nil)
        case .favorite: favoriteSelection(nil)
        case .viewThread: spawn(.thread(statusID: status.id, title: "Thread: \(status.account.bestName)"), for: account)
        case .viewAuthor: spawn(.userPosts(userID: status.account.id, title: "@\(status.account.acct)"), for: account)
        case .authorFollowers: spawn(.followers(userID: status.account.id, title: "Followers: @\(status.account.acct)"), for: account)
        case .authorFollowing: spawn(.following(userID: status.account.id, title: "Following: @\(status.account.acct)"), for: account)
        case .openInBrowser: if let url = status.url { NSWorkspace.shared.open(url) }
        }
    }

    private func handle(_ action: UserInfoAction, for user: User) {
        guard let account = currentAccount else { return }
        switch action {
        case .viewPosts: spawn(.userPosts(userID: user.id, title: "@\(user.acct)"), for: account)
        case .followers: spawn(.followers(userID: user.id, title: "Followers: @\(user.acct)"), for: account)
        case .following: spawn(.following(userID: user.id, title: "Following: @\(user.acct)"), for: account)
        case .openInBrowser: if let url = user.url { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Compose / errors

    private func presentCompose(account: any SocialAccount, replyTo: Status?, quoting: Status?, editing: Status? = nil) {
        guard let window = view.window else { return }
        let compose = ComposeWindowController(services: services, account: account, replyTo: replyTo, quoting: quoting, editing: editing)
        composeController = compose // retain for the sheet's lifetime
        compose.beginSheet(for: window) { [weak self] in
            self?.composeController = nil
        }
    }

    private var isPresentingError = false

    private func present(error: Error) {
        // Don't stack alerts — a flood of background errors would otherwise queue
        // dozens of sheets and freeze the app.
        guard !isPresentingError, let window = view.window else { return }
        isPresentingError = true
        services.sound.play(.error)
        let alert = NSAlert()
        alert.messageText = "Something went wrong"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] _ in self?.isPresentingError = false }
    }
}

// MARK: - Data source / delegate

extension TimelineViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier
            let textField = NSTextField(wrappingLabelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.drawsBackground = false
            textField.isBordered = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -6),
            ])
        }

        let item = items[row]
        let demojify = services.settings.settings.demojify
        cell.textField?.stringValue = item.compactLine(demojify: demojify)
        let label = item.accessibilityLabel(demojify: demojify)
        cell.setAccessibilityLabel(label)
        cell.textField?.setAccessibilityLabel(label)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Foundation.Notification) {
        guard !isRestoringSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        services.playEarcon(.navigate)
        services.recordSelection(items[row].id)
        // Near the bottom — pull the next page.
        if row >= items.count - 5 {
            Task { await services.selectedController?.loadOlder() }
        }
    }
}
