//
//  AccountStore.swift
//  FastSMCore
//
//  The roster of logged-in accounts. Persists everything — including sign-in
//  secrets — to the config file (AppConfigStore), by request. (FastSM keeps
//  credentials in plain JSON too; the Keychain is intentionally not used here.)
//

import Foundation

@MainActor
public final class AccountStore {
    public private(set) var accounts: [any SocialAccount] = []
    public private(set) var selectedAccountKey: String?

    private let configStore: AppConfigStore

    /// Called whenever the roster or selection changes, so non-observing UIs
    /// (AppKit) can refresh.
    public var onChange: (() -> Void)?

    public init(configStore: AppConfigStore = AppConfigStore()) {
        self.configStore = configStore
    }

    public var selectedAccount: (any SocialAccount)? {
        guard let key = selectedAccountKey else { return accounts.first }
        return accounts.first { $0.accountKey == key } ?? accounts.first
    }

    public var isEmpty: Bool { accounts.isEmpty }

    /// Reconstruct accounts from persisted records. Bluesky requires a network
    /// round-trip to create a session.
    public func load() async {
        let config = configStore.load()
        var restored: [any SocialAccount] = []
        for record in config.accounts {
            switch record.credential {
            case .mastodon(let credentials):
                restored.append(MastodonAccount(credentials: credentials, me: record.me))
            case .bluesky(let credentials):
                if let account = try? await BlueskyAccount.restore(credentials: credentials) {
                    restored.append(account)
                }
            }
        }
        accounts = restored
        selectedAccountKey = config.selectedAccountKey ?? restored.first?.accountKey
        onChange?()
    }

    public func add(_ account: any SocialAccount) {
        accounts.removeAll { $0.accountKey == account.accountKey }
        accounts.append(account)
        selectedAccountKey = account.accountKey
        persistConfig()
        onChange?()
    }

    public func remove(accountKey: String) {
        accounts.removeAll { $0.accountKey == accountKey }
        if selectedAccountKey == accountKey {
            selectedAccountKey = accounts.first?.accountKey
        }
        persistConfig()
        onChange?()
    }

    public func select(accountKey: String) {
        guard accounts.contains(where: { $0.accountKey == accountKey }) else { return }
        selectedAccountKey = accountKey
        persistConfig()
        onChange?()
    }

    // MARK: Persistence

    private func storedCredential(for account: any SocialAccount) -> StoredCredential? {
        if let mastodon = account as? MastodonAccount {
            return .mastodon(mastodon.credentials)
        } else if let bluesky = account as? BlueskyAccount {
            return .bluesky(bluesky.credentials)
        }
        return nil
    }

    private func persistConfig() {
        let records = accounts.compactMap { account -> AccountRecord? in
            guard let credential = storedCredential(for: account) else { return nil }
            return AccountRecord(
                accountKey: account.accountKey,
                platform: account.platform,
                me: account.me,
                credential: credential
            )
        }
        configStore.save(AppConfig(accounts: records, selectedAccountKey: selectedAccountKey))
    }
}
