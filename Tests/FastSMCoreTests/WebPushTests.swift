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
