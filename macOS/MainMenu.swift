//
//  MainMenu.swift
//  FastSM (macOS)
//
//  Builds the application main menu in code. Status actions target the first
//  responder (the TimelineViewController) so their key equivalents work whenever
//  the timeline has focus.
//

import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About FastSM", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FastSM", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FastSM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Post", action: #selector(TimelineViewController.composePost(_:)), keyEquivalent: "n")
        fileMenu.addItem(.separator())
        let refresh = fileMenu.addItem(withTitle: "Refresh Timeline", action: #selector(TimelineViewController.refreshTimeline(_:)), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        // Close the key window (main window, Settings, or a sheet). Routed to the
        // first responder so it always targets the frontmost window.
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu (standard editing for text fields / compose)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Status menu
        let statusItem = NSMenuItem()
        mainMenu.addItem(statusItem)
        let statusMenu = NSMenu(title: "Status")
        statusItem.submenu = statusMenu
        statusMenu.addItem(withTitle: "Reply", action: #selector(TimelineViewController.replyToSelection(_:)), keyEquivalent: "")
        let boost = statusMenu.addItem(withTitle: "Boost", action: #selector(TimelineViewController.boostSelection(_:)), keyEquivalent: "b")
        boost.keyEquivalentModifierMask = [.command, .shift]
        let favorite = statusMenu.addItem(withTitle: "Favorite", action: #selector(TimelineViewController.favoriteSelection(_:)), keyEquivalent: "d")
        favorite.keyEquivalentModifierMask = [.command, .shift]
        let quote = statusMenu.addItem(withTitle: "Quote", action: #selector(TimelineViewController.quoteSelection(_:)), keyEquivalent: "q")
        quote.keyEquivalentModifierMask = [.command, .shift]
        statusMenu.addItem(withTitle: "Post Info…", action: #selector(TimelineViewController.showPostInfo(_:)), keyEquivalent: "i")
        statusMenu.addItem(withTitle: "View Thread", action: #selector(TimelineViewController.viewThread(_:)), keyEquivalent: "")
        statusMenu.addItem(.separator())
        // Open User Timeline is also the plain `u` single-key shortcut; the menu
        // item is for discoverability and exposes no command-key equivalent.
        statusMenu.addItem(withTitle: "Open User Timeline", action: #selector(TimelineViewController.openUserTimelineForSelection(_:)), keyEquivalent: "")
        let profile = statusMenu.addItem(withTitle: "Open User Profile", action: #selector(TimelineViewController.openUserProfileForSelection(_:)), keyEquivalent: "u")
        profile.keyEquivalentModifierMask = [.command]
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Open in Browser", action: #selector(TimelineViewController.openSelectionInBrowser(_:)), keyEquivalent: "")

        // Timeline menu
        let timelineItem = NSMenuItem()
        mainMenu.addItem(timelineItem)
        let timelineMenu = NSMenu(title: "Timeline")
        timelineItem.submenu = timelineMenu
        let newTimeline = timelineMenu.addItem(withTitle: "New Timeline…", action: #selector(MainWindowController.newTimeline(_:)), keyEquivalent: "t")
        newTimeline.keyEquivalentModifierMask = [.command]
        timelineMenu.addItem(.separator())
        let clear = timelineMenu.addItem(withTitle: "Clear Timeline", action: #selector(TimelineViewController.clearTimeline(_:)), keyEquivalent: "\u{8}")
        clear.keyEquivalentModifierMask = [.command]
        let clearAll = timelineMenu.addItem(withTitle: "Clear All Timelines", action: #selector(TimelineViewController.clearAllTimelines(_:)), keyEquivalent: "\u{8}")
        clearAll.keyEquivalentModifierMask = [.control, .command, .shift]
        let undoNav = timelineMenu.addItem(withTitle: "Go Back", action: #selector(TimelineViewController.undoTimelineNavigation(_:)), keyEquivalent: "z")
        undoNav.keyEquivalentModifierMask = [.command]
        timelineMenu.addItem(.separator())
        for number in 1...9 {
            let item = timelineMenu.addItem(withTitle: "Go to Timeline \(number)", action: #selector(MainWindowController.selectTimelineNumber(_:)), keyEquivalent: "\(number)")
            item.keyEquivalentModifierMask = [.command]
            item.tag = number
        }

        // Account menu
        let accountItem = NSMenuItem()
        mainMenu.addItem(accountItem)
        let accountMenu = NSMenu(title: "Account")
        accountItem.submenu = accountMenu
        let add = accountMenu.addItem(withTitle: "Add Account…", action: #selector(AppDelegate.showAddAccount(_:)), keyEquivalent: "a")
        add.keyEquivalentModifierMask = [.command, .shift]
        accountMenu.addItem(.separator())
        let prevAccount = accountMenu.addItem(withTitle: "Previous Account", action: #selector(MainWindowController.previousAccount(_:)), keyEquivalent: "[")
        prevAccount.keyEquivalentModifierMask = [.command]
        let nextAccount = accountMenu.addItem(withTitle: "Next Account", action: #selector(MainWindowController.nextAccount(_:)), keyEquivalent: "]")
        nextAccount.keyEquivalentModifierMask = [.command]

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}
