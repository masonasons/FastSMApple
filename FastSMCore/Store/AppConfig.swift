//
//  AppConfig.swift
//  FastSMCore
//
//  JSON-backed app configuration stored in Application Support. Port of the
//  persistence semantics in config.py (portable mode dropped — N/A on sandboxed
//  Apple apps). Holds the non-secret account roster and selection; secrets live
//  in the Keychain.
//

import Foundation

/// Stored sign-in credentials for an account. NOTE: this includes secrets
/// (Mastodon access token, Bluesky app password) and is written to the plain
/// config file by request, rather than the Keychain.
public enum StoredCredential: Codable, Sendable, Equatable {
    case mastodon(MastodonCredentials)
    case bluesky(BlueskyCredentials)

    public var platform: Platform {
        switch self {
        case .mastodon: return .mastodon
        case .bluesky: return .bluesky
        }
    }
}

/// A record of a logged-in account, persisted in the config file.
public struct AccountRecord: Codable, Sendable, Equatable {
    public let accountKey: String
    public let platform: Platform
    /// Cached profile so accounts can be shown without an immediate network call.
    public var me: User
    /// Sign-in credentials (secrets included) stored in the config file.
    public var credential: StoredCredential

    public init(accountKey: String, platform: Platform, me: User, credential: StoredCredential) {
        self.accountKey = accountKey
        self.platform = platform
        self.me = me
        self.credential = credential
    }
}

/// The persisted application configuration.
public struct AppConfig: Codable, Sendable, Equatable {
    public var accounts: [AccountRecord]
    public var selectedAccountKey: String?

    public init(accounts: [AccountRecord] = [], selectedAccountKey: String? = nil) {
        self.accounts = accounts
        self.selectedAccountKey = selectedAccountKey
    }
}

/// Loads and saves `AppConfig` to `Application Support/FastSM/config.json`.
public struct AppConfigStore {
    private let url: URL

    public init(appName: String = "FastSM", fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("config.json")
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    public func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
