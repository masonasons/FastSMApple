//
//  WebPushTests.swift
//  FastSMCoreTests
//
//  Verifies the Web Push decryption against the canonical RFC 8291 Appendix A
//  worked example, so we know the aes128gcm/HKDF/ECDH wiring matches the spec
//  rather than merely being self-consistent.
//

import XCTest
import CryptoKit
@testable import FastSMCore

final class WebPushTests: XCTestCase {
    func testRFC8291AppendixADecryption() throws {
        // The complete aes128gcm message (header + ciphertext) from RFC 8291 A.
        let message = WebPush.base64urlDecode(
            "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN")!
        let plaintext = try WebPush.decrypt(
            message,
            privateKeyBase64url: "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94",
            authBase64url: "BTBZMqHH6r4Tts7J_aSIgg")
        XCTAssertEqual(String(data: plaintext, encoding: .utf8),
                       "When I grow up, I want to be a watermelon")
    }

    func testLegacyAESGCMDecryption() throws {
        // Self-verified vector generated with http_ece (the reference impl),
        // matching what Mastodon servers using the legacy `aesgcm` encoding send.
        let ciphertext = WebPush.base64urlDecode(
            "0BEzCq1CEBKGcJ3G-g5mDqOtqdARrGo87tisNF7vB-6EfbBVXXdqyaphQEFKGDXoA59fdpRVXI966WDuwNFCcv12fvc3XthMKueBEcawZA2oszgBlhUk")!
        let salt = WebPush.base64urlDecode("7Fxw2x6UKvRCQu08CQw6ZQ")!
        let dh = WebPush.base64urlDecode(
            "BF7hluxn-_jzv36vO3uj_a3PMKY7aszIRBYxIzMiJMDUhp-VbSdV_3YfobewEI15BrBuq_F9xkgRf4DRfTvm7xk")!
        let plaintext = try WebPush.decryptAESGCM(
            ciphertext, salt: salt, serverPublicKey: dh,
            privateKeyBase64url: "97O2KtYHYxiTbu2HuIIIRPZ7hvwA6AUejV_31V7AZks",
            authBase64url: "TAa0royO3hSRBE96b_xVIw")
        XCTAssertEqual(String(data: plaintext, encoding: .utf8),
                       #"{"title":"Alice mentioned you","body":"hey @you legacy aesgcm works"}"#)
    }

    func testWrongKeyThrows() throws {
        let message = WebPush.base64urlDecode(
            "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN")!
        // A different (valid) keypair must fail to decrypt — this is what lets a
        // multi-account device try each subscription's key until one works.
        let other = WebPush.generateKeys()
        XCTAssertThrowsError(try WebPush.decrypt(
            message, privateKeyBase64url: other.privateKey, authBase64url: other.auth))
    }
}
