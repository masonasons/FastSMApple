//
//  MainWindowController.swift
//  FastSM (macOS)
//
//  Owns the main window. Hosts a split view with the timelines pane (left) and
//  the posts pane (right). Tab moves focus between the two; left/right (in the
//  posts pane) switch timelines. Toolbar: New Post / Refresh / Add Account.
//
//  Post actions are also implemented here as forwarders so the menu commands
//  work no matter which pane currently has focus (the window controller is
//  always in the responder chain; the posts view controller is not when the
//  timelines pane is focused).
//

import AppKit
import FastSMCore

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let services: AppServices
    private let timelinesViewController: TimelinesViewController
    private let postsViewController: TimelineViewController
    private var hasFocusedInitially = false

    init(services: AppServices) {
        self.services = services
        self.timelinesViewController = TimelinesViewController(services: services)
        self.postsViewController = TimelineViewController(services: services)

        let splitViewController = NSSplitViewController()
        let timelinesItem = NSSplitViewItem(sidebarWithViewController: timelinesViewController)
        timelinesItem.minimumThickness = 180
        timelinesItem.maximumThickness = 340
        timelinesItem.canCollapse = false
        let postsItem = NSSplitViewItem(viewController: postsViewController)
        splitViewController.addSplitViewItem(timelinesItem)
        splitViewController.addSplitViewItem(postsItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FastSM"
        window.contentViewController = splitViewController
        // Never let the window (and therefore a pane) collapse to near-zero — a
        // zero-height posts pane is invisible to VoiceOver's VO-key navigation.
        window.contentMinSize = NSSize(width: 680, height: 440)
        // New autosave name: discards any earlier corrupt/tiny saved frame.
        window.setFrameAutosaveName("FastSMMainWindow")
        if window.frame.height < 440 || window.frame.width < 680 {
            window.setContentSize(NSSize(width: 920, height: 720))
        }
        super.init(window: window)

        // Tab cycles focus between the two panes.
        timelinesViewController.onMoveToPosts = { [weak self] in self?.postsViewController.focusTable() }
        postsViewController.onMoveToTimelines = { [weak self] in self?.timelinesViewController.focusTable() }

        services.onTimelinesChanged = { [weak self] in self?.timelinesViewController.reload() }
        services.onSelectedTimelineChanged = { [weak self] in
            self?.timelinesViewController.updateSelectionHighlight()
            self?.updateSubtitle()
        }

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reloadTimeline() {
        timelinesViewController.reload()
        postsViewController.reload()
        updateSubtitle()
        if !hasFocusedInitially, !services.timelineRefs.isEmpty {
            hasFocusedInitially = true
            postsViewController.focusTable()
        }
    }

    private func updateSubtitle() {
        // Show the current account + selected timeline, since the list is per-account.
        let parts = [services.currentAccountHandle, services.selectedRef.map(services.displayTitle(for:))]
        window?.subtitle = parts.compactMap { $0 }.joined(separator: " — ")
    }

    // MARK: Action forwarders (work regardless of focused pane)

    @objc func composePost(_ sender: Any?) { postsViewController.composePost(sender) }
    @objc func refreshTimeline(_ sender: Any?) { postsViewController.refreshTimeline(sender) }
    @objc func replyToSelection(_ sender: Any?) { postsViewController.replyToSelection(sender) }
    @objc func boostSelection(_ sender: Any?) { postsViewController.boostSelection(sender) }
    @objc func favoriteSelection(_ sender: Any?) { postsViewController.favoriteSelection(sender) }
    @objc func openSelectionInBrowser(_ sender: Any?) { postsViewController.openSelectionInBrowser(sender) }
    @objc func quoteSelection(_ sender: Any?) { postsViewController.quoteSelection(sender) }
    @objc func showPostInfo(_ sender: Any?) { postsViewController.showPostInfo(sender) }
    @objc func viewThread(_ sender: Any?) { postsViewController.viewThread(sender) }
    @objc func clearTimeline(_ sender: Any?) { postsViewController.clearTimeline(sender) }

    @objc func selectTimelineNumber(_ sender: NSMenuItem) {
        services.selectTimeline(number: sender.tag)
        postsViewController.focusTable()
    }
    @objc func previousAccount(_ sender: Any?) {
        services.switchAccount(offset: -1)
        postsViewController.focusTable()
    }
    @objc func nextAccount(_ sender: Any?) {
        services.switchAccount(offset: 1)
        postsViewController.focusTable()
    }

    private var newTimelineController: NewTimelineWindowController?

    @objc func newTimeline(_ sender: Any?) {
        guard let window else { return }
        let controller = NewTimelineWindowController(services: services)
        newTimelineController = controller
        controller.beginSheet(for: window) { [weak self] in
            self?.newTimelineController = nil
            self?.postsViewController.focusTable()
        }
    }

    // MARK: Toolbar

    private enum ItemID {
        static let refresh = NSToolbarItem.Identifier("refresh")
        static let compose = NSToolbarItem.Identifier("compose")
        static let account = NSToolbarItem.Identifier("account")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.compose, ItemID.refresh, .flexibleSpace, ItemID.account]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.compose, ItemID.refresh, ItemID.account, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case ItemID.refresh:
            item.label = "Refresh"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.target = self
            item.action = #selector(refreshTimeline(_:))
        case ItemID.compose:
            item.label = "New Post"
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Post")
            item.target = self
            item.action = #selector(composePost(_:))
        case ItemID.account:
            item.label = "Add Account"
            item.image = NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: "Add Account")
            item.target = NSApp.delegate
            item.action = #selector(AppDelegate.showAddAccount(_:))
        default:
            return nil
        }
        item.isBordered = true
        return item
    }
}
