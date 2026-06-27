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

    public static func base64urlDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    public enum DecryptError: Error { case malformed, badKey }

    /// Decrypt a Mastodon Web Push body (RFC 8291 / RFC 8188 `aes128gcm`) using a
    /// subscription's private key + auth secret. Returns the plaintext push JSON.
    /// Throws (incl. AES-GCM auth failure) when the keys don't match the message —
    /// callers with several subscriptions can try each keypair until one succeeds.
    public static func decrypt(_ message: Data,
                               privateKeyBase64url: String,
                               authBase64url: String) throws -> Data {
        let bytes = [UInt8](message)
        // Header: salt(16) || recordSize(4) || idLen(1) || keyId(idLen) || ciphertext
        guard bytes.count > 21 else { throw DecryptError.malformed }
        let salt = Data(bytes[0..<16])
        let idLen = Int(bytes[20])
        let headerEnd = 21 + idLen
        guard idLen == 65, bytes.count > headerEnd + 16 else { throw DecryptError.malformed }
        let serverPublic = Data(bytes[21..<headerEnd])   // app server's ephemeral P-256 key
        let ciphertext = Data(bytes[headerEnd...])

        guard let privRaw = base64urlDecode(privateKeyBase64url),
              let authSecret = base64urlDecode(authBase64url) else { throw DecryptError.badKey }
        let priv = try P256.KeyAgreement.PrivateKey(rawRepresentation: privRaw)
        let serverKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublic)
        let shared = try priv.sharedSecretFromKeyAgreement(with: serverKey)
        let uaPublic = priv.publicKey.x963Representation

        // RFC 8291 §3.4: IKM = HKDF(salt: auth_secret, ikm: ecdh, info: key_info).
        var keyInfo = Data("WebPush: info".utf8)
        keyInfo.append(0x00)
        keyInfo.append(uaPublic)
        keyInfo.append(serverPublic)
        let ikm = shared.withUnsafeBytes { ecdh in
            HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ecdh),
                                   salt: authSecret, info: keyInfo, outputByteCount: 32)
        }

        // RFC 8188 §2.2: content-encryption key + nonce, both salted by the header salt.
        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt,
            info: Data("Content-Encoding: aes128gcm".utf8) + [0x00], outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt,
            info: Data("Content-Encoding: nonce".utf8) + [0x00], outputByteCount: 12)
            .withUnsafeBytes { Data($0) }

        let sealed = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce),
                                           ciphertext: ciphertext.dropLast(16),
                                           tag: ciphertext.suffix(16))
        var plain = [UInt8](try AES.GCM.open(sealed, using: cek))

        // RFC 8188 §2: strip trailing 0x00 padding and the record delimiter (0x02 last).
        while plain.last == 0x00 { plain.removeLast() }
        guard let delimiter = plain.last, delimiter == 0x01 || delimiter == 0x02 else {
            throw DecryptError.malformed
        }
        plain.removeLast()
        return Data(plain)
    }

    /// Decrypt a legacy `aesgcm` Web Push body (draft-ietf-webpush-encryption-04).
    /// Unlike aes128gcm, the salt and the app server's public key arrive out of
    /// band (HTTP `Encryption`/`Crypto-Key` headers, which the relay forwards),
    /// the KDF mixes both public keys into a context, and padding is a 2-byte
    /// big-endian length prefix.
    public static func decryptAESGCM(_ ciphertext: Data,
                                     salt: Data,
                                     serverPublicKey: Data,
                                     privateKeyBase64url: String,
                                     authBase64url: String) throws -> Data {
        guard ciphertext.count > 16 else { throw DecryptError.malformed }
        guard let privRaw = base64urlDecode(privateKeyBase64url),
              let authSecret = base64urlDecode(authBase64url) else { throw DecryptError.badKey }
        let priv = try P256.KeyAgreement.PrivateKey(rawRepresentation: privRaw)
        let serverKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKey)
        let shared = try priv.sharedSecretFromKeyAgreement(with: serverKey)
        let uaPublic = priv.publicKey.x963Representation

        // Combine the ECDH secret with the auth secret first.
        let prk = shared.withUnsafeBytes { ecdh in
            HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ecdh),
                salt: authSecret,
                info: Data("Content-Encoding: auth".utf8) + [0x00],
                outputByteCount: 32)
        }

        // context = "P-256" 0x00 len(ua) ua len(server) server  (lengths uint16 BE).
        var context = Data("P-256".utf8)
        context.append(0x00)
        context.append(contentsOf: [UInt8(uaPublic.count >> 8), UInt8(uaPublic.count & 0xff)])
        context.append(uaPublic)
        context.append(contentsOf: [UInt8(serverPublicKey.count >> 8), UInt8(serverPublicKey.count & 0xff)])
        context.append(serverPublicKey)

        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: prk, salt: salt,
            info: Data("Content-Encoding: aesgcm".utf8) + [0x00] + context, outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(inputKeyMaterial: prk, salt: salt,
            info: Data("Content-Encoding: nonce".utf8) + [0x00] + context, outputByteCount: 12)
            .withUnsafeBytes { Data($0) }

        let sealed = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce),
                                           ciphertext: ciphertext.dropLast(16),
                                           tag: ciphertext.suffix(16))
        let padded = [UInt8](try AES.GCM.open(sealed, using: cek))

        // Padding: 2-byte big-endian length, then that many leading zero bytes.
        guard padded.count >= 2 else { throw DecryptError.malformed }
        let padLength = Int(padded[0]) << 8 | Int(padded[1])
        guard padded.count >= 2 + padLength else { throw DecryptError.malformed }
        return Data(padded[(2 + padLength)...])
    }
}
