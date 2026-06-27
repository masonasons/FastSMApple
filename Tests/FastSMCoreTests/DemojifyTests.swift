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

    func testLeadingMentionTruncation() {
        let s = "@a @b @c @d @e hello world"
        XCTAssertEqual(s.truncatingLeadingMentions(max: 0), s, "0 = keep all")
        XCTAssertEqual(s.truncatingLeadingMentions(max: 2), "@a @b and 3 others hello world")
        XCTAssertEqual("@a @b hi".truncatingLeadingMentions(max: 2), "@a @b hi", "at/under the cap is unchanged")
        XCTAssertEqual("@a@inst.social @b @c done".truncatingLeadingMentions(max: 1),
                       "@a@inst.social and 2 others done")
        // Mentions later in the text are not a leading run, so untouched.
        XCTAssertEqual("hey @a @b @c".truncatingLeadingMentions(max: 1), "hey @a @b @c")
    }
}
