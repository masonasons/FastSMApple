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

    // Persisted in the shared app group container so the Notification Service
    // Extension can read the private keys to decrypt incoming pushes.
    private var keysByAccount: [String: WebPushKeys]

    private init() {
        keysByAccount = PushKeyStore.load()
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
        PushKeyStore.save(keysByAccount)
    }
}
