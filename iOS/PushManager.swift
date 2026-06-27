//
//  PushManager.swift
//  FastSM (iOS)
//
//  Holds the APNs device token and per-account Web Push keypairs, and builds the
//  relay endpoint URL that Mastodon pushes to. Registration with each account is
//  driven by AppModel.
//

import Foundation
import FastSMCore

@MainActor
final class PushManager {
    static let shared = PushManager()

    /// The relay base; the device token + environment are appended.
    static let relayBase = "https://masonasons.me/relay/push"

    private(set) var deviceToken: String?
    /// Called when the device token arrives so AppModel can (re)subscribe.
    var onTokenChanged: (() -> Void)?

    private var keysByAccount: [String: WebPushKeys] = [:]
    private let url: URL

    private init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("FastSM", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("pushkeys.json")
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String: WebPushKeys].self, from: data) {
            keysByAccount = loaded
        }
    }

    func setDeviceToken(_ token: String) {
        guard token != deviceToken else { return }
        deviceToken = token
        onTokenChanged?()
    }

    /// Stable keypair for an account, generated and persisted on first use.
    func keys(for accountKey: String) -> WebPushKeys {
        if let existing = keysByAccount[accountKey] { return existing }
        let made = WebPush.generateKeys()
        keysByAccount[accountKey] = made
        save()
        return made
    }

    /// APNs environment must match the build: dev installs use sandbox.
    private var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func endpoint() -> URL? {
        guard let token = deviceToken else { return nil }
        return URL(string: "\(Self.relayBase)/\(environment)/\(token)")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(keysByAccount) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
