//
//  Keychain.swift
//  FastSMCore
//
//  Minimal Keychain wrapper for storing per-account credential blobs (access
//  tokens, app passwords). FastSM keeps these in plain JSON config (config.py);
//  on Apple platforms we keep secrets out of the config file.
//

import Foundation
import Security

public struct Keychain {
    private let service: String

    public init(service: String = "com.fastsm.credentials") {
        self.service = service
    }

    public func set(_ data: Data, for account: String) throws {
        // Remove any existing item first so we can add cleanly.
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PlatformError.message("Keychain save failed (\(status)).")
        }
    }

    public func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // Convenience for Codable credential blobs.

    public func setCodable<T: Encodable>(_ value: T, for account: String) throws {
        try set(try JSONEncoder().encode(value), for: account)
    }

    public func codable<T: Decodable>(_ type: T.Type, for account: String) -> T? {
        guard let data = data(for: account) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
