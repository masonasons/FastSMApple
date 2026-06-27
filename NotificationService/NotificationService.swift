//
//  NotificationService.swift
//  FastSMNotificationService
//
//  The relay can only forward Mastodon's end-to-end-encrypted Web Push body; it
//  delivers a placeholder APNs alert with the ciphertext in `fastsm_payload`.
//  This extension decrypts that with the subscription's private key and swaps in
//  the real title/body. Anything goes wrong -> the placeholder is delivered.
//

import UserNotifications
import FastSMCore

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttempt = content
        guard let content else { contentHandler(request.content); return }

        let info = request.content.userInfo
        guard let payloadB64 = info["fastsm_payload"] as? String,
              let body = Data(base64Encoded: payloadB64) else {
            contentHandler(content); return
        }
        let encoding = (info["fastsm_encoding"] as? String) ?? "aes128gcm"
        // Legacy aesgcm carries salt + server key in headers the relay forwards.
        let salt = headerValue("salt", info["fastsm_encryption"] as? String).flatMap(WebPush.base64urlDecode)
        let serverKey = headerValue("dh", info["fastsm_cryptokey"] as? String).flatMap(WebPush.base64urlDecode)

        // We don't know which account a push is for (accounts share one device
        // token), so try each stored subscription keypair until one decrypts.
        let keypairs = PushKeyStore.allKeypairs()
        for keys in keypairs {
            let plaintext: Data?
            switch encoding {
            case "aesgcm":
                guard let salt, let serverKey else { plaintext = nil; break }
                plaintext = try? WebPush.decryptAESGCM(body, salt: salt, serverPublicKey: serverKey,
                    privateKeyBase64url: keys.privateKey, authBase64url: keys.auth)
            default:
                plaintext = try? WebPush.decrypt(body,
                    privateKeyBase64url: keys.privateKey, authBase64url: keys.auth)
            }
            guard let plaintext,
                  let push = try? JSONDecoder().decode(MastodonPush.self, from: plaintext)
            else { continue }
            if let title = push.title { content.title = title }
            if let pushBody = push.body { content.body = pushBody }
            break
        }
        // Nothing decrypted -> deliver the placeholder content unchanged.
        contentHandler(content)
    }

    /// Pulls `name=<value>` out of a `;`-separated Web Push header field.
    private func headerValue(_ name: String, _ header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces)
            if kv.hasPrefix("\(name)=") { return String(kv.dropFirst(name.count + 1)) }
        }
        return nil
    }

    override func serviceExtensionTimeWillExpire() {
        // Out of time: deliver whatever we have rather than nothing.
        if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }
    }
}

/// The fields we use from Mastodon's decrypted push JSON.
private struct MastodonPush: Decodable {
    let title: String?
    let body: String?
}
