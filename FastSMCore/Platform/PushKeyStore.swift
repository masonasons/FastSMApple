//
//  PushKeyStore.swift
//  FastSMCore
//
//  Shared on-disk store for Web Push subscription keypairs. Lives in the app
//  group container so the Notification Service Extension can read the private
//  keys it needs to decrypt incoming pushes, while the app writes them.
//

import Foundation

public enum PushKeyStore {
    /// Must match the `com.apple.security.application-groups` entitlement on both
    /// the app and the extension.
    public static let appGroupID = "group.me.masonasons.fastsm"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("pushkeys.json")
    }

    public static func load() -> [String: WebPushKeys] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode([String: WebPushKeys].self, from: data)
        else { return [:] }
        return keys
    }

    public static func save(_ keys: [String: WebPushKeys]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(keys) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Every stored keypair, for a receiver to try in turn when it can't tell
    /// up front which subscription a push belongs to.
    public static func allKeypairs() -> [WebPushKeys] { Array(load().values) }
}
