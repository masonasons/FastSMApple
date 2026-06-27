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

        guard let content,
              let payloadB64 = request.content.userInfo["fastsm_payload"] as? String,
              let encrypted = Data(base64Encoded: payloadB64) else {
            contentHandler(request.content); return
        }

        // The relay forwards only modern aes128gcm bodies. We don't know which
        // account a push is for (all accounts share one device token), so try
        // each stored subscription keypair until one decrypts.
        for keys in PushKeyStore.allKeypairs() {
            guard let plaintext = try? WebPush.decrypt(encrypted,
                      privateKeyBase64url: keys.privateKey, authBase64url: keys.auth),
                  let push = try? JSONDecoder().decode(MastodonPush.self, from: plaintext)
            else { continue }
            if let title = push.title { content.title = title }
            if let body = push.body { content.body = body }
            break
        }
        contentHandler(content)
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
