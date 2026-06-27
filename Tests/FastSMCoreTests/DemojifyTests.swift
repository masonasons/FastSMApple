//
//  DemojifyTests.swift
//  FastSMCoreTests
//
//  Verifies the granular emoji removal: unicode emoji, Mastodon custom
//  :shortcode: emoji, or both.
//

import XCTest
@testable import FastSMCore

final class DemojifyTests: XCTestCase {
    func testStrippingModes() {
        let s = "Hello 😀 :blobcat: world"
        XCTAssertEqual(s.strippingEmoji(.none), s)
        XCTAssertEqual(s.strippingEmoji(.unicode), "Hello :blobcat: world")
        XCTAssertEqual(s.strippingEmoji(.mastodon), "Hello 😀 world")
        XCTAssertEqual(s.strippingEmoji(.both), "Hello world")
    }

    func testCustomEmojiOnlyTouchesShortcodes() {
        // A bare colon or a time shouldn't be removed; only :word: shortcodes.
        XCTAssertEqual("ends at 9:30 sharp".strippingEmoji(.mastodon), "ends at 9:30 sharp")
        XCTAssertEqual("a :wave: b :tada:".strippingEmoji(.mastodon), "a b")
    }

    func testNoEmojiIsUnchanged() {
        XCTAssertEqual("plain text".strippingEmoji(.both), "plain text")
    }
}
