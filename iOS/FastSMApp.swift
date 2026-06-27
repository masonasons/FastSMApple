//
//  FastSMApp.swift
//  FastSM (iOS)
//
//  SwiftUI entry point. Shows the timeline once at least one account exists,
//  otherwise the add-account screen.
//

import SwiftUI
import FastSMCore

@main
struct FastSMApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
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
