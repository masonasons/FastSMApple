//
//  FastSMApp.swift
//  FastSM (iOS)
//
//  SwiftUI entry point. Shows the timeline once at least one account exists,
//  otherwise the add-account screen.
//

import SwiftUI
import UIKit
import FastSMCore

/// Receives the APNs device token and hands it to PushManager.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushManager.shared.setDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Push registration failed: \(error.localizedDescription)")
    }
}

@main
struct FastSMApp: App {
    @State private var model = AppModel()
    @State private var wasBackgrounded = false
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Returning from the background: the streaming socket was likely
                // suspended, so reconnect and refresh to catch up.
                if wasBackgrounded {
                    wasBackgrounded = false
                    model.enterForeground()
                }
            case .background:
                wasBackgrounded = true
                model.flush()   // save position when leaving the foreground
            default:
                model.flush()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddAccount = false

    var body: some View {
        Group {
            if model.hasAccounts {
                TimelinePagerView()
            } else {
                EmptyAccountsView(showingAddAccount: $showingAddAccount)
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
        }
        .onChange(of: model.accountsVersion) { _, _ in
            if model.hasAccounts { showingAddAccount = false }
        }
    }
}

struct EmptyAccountsView: View {
    @Binding var showingAddAccount: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Welcome to FastSM", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Add a Mastodon or Bluesky account to get started.")
        } actions: {
            Button("Add Account") { showingAddAccount = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
