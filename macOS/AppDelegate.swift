//
//  AppDelegate.swift
//  FastSM (macOS)
//
//  Boots the services, builds the main menu programmatically, shows the main
//  window, and presents the Add Account flow. Also serves as the OAuth
//  presentation anchor.
//

import AppKit
import AuthenticationServices
import FastSMCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()
    private var mainWindowController: MainWindowController?
    private var addAccountController: AddAccountWindowController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        NSApp.mainMenu = MainMenu.build()

        let controller = MainWindowController(services: services)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindowController = controller

        Task { await bootstrap() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Foundation.Notification) {
        services.positions.flush()   // persist the latest position before quitting
    }

    private func bootstrap() async {
        await services.accountStore.load()
        if services.accountStore.isEmpty {
            presentAddAccount()
        } else {
            await services.rebuildTimelines()
            mainWindowController?.reloadTimeline()
        }
    }

    // MARK: Menu actions (routed from MainMenu via first responder)

    @objc func showAddAccount(_ sender: Any?) {
        presentAddAccount()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: services.settings)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func presentAddAccount() {
        guard let window = mainWindowController?.window else { return }
        let addController = AddAccountWindowController(services: services, anchorProvider: self)
        addController.onComplete = { [weak self] in
            guard let self else { return }
            Task {
                await self.services.rebuildTimelines()
                self.mainWindowController?.reloadTimeline()
            }
        }
        addAccountController = addController // retain for the sheet's lifetime
        addController.beginSheet(for: window) { [weak self] in
            self?.addAccountController = nil
        }
    }
}

extension AppDelegate: PresentationAnchorProviding {
    func presentationAnchor() -> ASPresentationAnchor {
        mainWindowController?.window ?? ASPresentationAnchor()
    }
}
