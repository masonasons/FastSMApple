//
//  WebPush.swift
//  FastSMCore
//
//  Web Push (RFC 8291) subscription keys. Mastodon encrypts each notification to
//  the subscription's public key; the app keeps the private key to decrypt in its
//  Notification Service Extension. The relay just forwards the ciphertext.
//

import Foundation
import CryptoKit

/// Which notification types Mastodon should push for an account.
public struct PushAlerts: Codable, Sendable, Equatable {
    public var mention: Bool
    public var reblog: Bool
    public var favourite: Bool
    public var follow: Bool
    public var poll: Bool
    public var status: Bool

    public init(mention: Bool = true, reblog: Bool = true, favourite: Bool = true,
                follow: Bool = true, poll: Bool = true, status: Bool = false) {
        self.mention = mention
        self.reblog = reblog
        self.favourite = favourite
        self.follow = follow
        self.poll = poll
        self.status = status
    }

    public static let `default` = PushAlerts()
}

/// A subscription keypair: the public bits sent to Mastodon, plus the private key
/// kept on-device for decryption.
public struct WebPushKeys: Codable, Sendable, Equatable {
    /// Base64url (unpadded) of the uncompressed P-256 public key (65 bytes).
    public let p256dh: String
    /// Base64url (unpadded) of the 16-byte auth secret.
    public let auth: String
    /// Base64url (unpadded) of the raw P-256 private key, for the extension.
    public let privateKey: String

    public init(p256dh: String, auth: String, privateKey: String) {
        self.p256dh = p256dh
        self.auth = auth
        self.privateKey = privateKey
    }
}

public enum WebPush {
    public static func generateKeys() -> WebPushKeys {
        let priv = P256.KeyAgreement.PrivateKey()
        let pub = priv.publicKey.x963Representation               // 65-byte uncompressed point
        var authBytes = [UInt8](repeating: 0, count: 16)
        for i in authBytes.indices { authBytes[i] = UInt8.random(in: 0...255) }
        return WebPushKeys(
            p256dh: base64url(pub),
            auth: base64url(Data(authBytes)),
            privateKey: base64url(priv.rawRepresentation)
        )
    }

    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
