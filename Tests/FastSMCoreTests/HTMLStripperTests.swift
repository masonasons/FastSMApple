//
//  HTMLStripperTests.swift
//  FastSMCoreTests
//
//  Verifies HTMLStripper matches FastSM's strip_html behavior.
//

import XCTest
@testable import FastSMCore

final class HTMLStripperTests: XCTestCase {
    func testBlockElementsBecomeSpaces() {
        XCTAssertEqual(HTMLStripper.strip("<p>Hello</p><p>World</p>"), "Hello World")
        XCTAssertEqual(HTMLStripper.strip("Line one<br>Line two"), "Line one Line two")
        XCTAssertEqual(HTMLStripper.strip("<div>A</div><div>B</div>"), "A B")
    }

    func testURLSpansArePreservedWithoutSpaces() {
        // Mastodon wraps URL fragments in spans; stripping must not insert spaces.
        let html = #"<span class="invisible">https://</span><span class="ellipsis">example.com</span>"#
        XCTAssertEqual(HTMLStripper.strip(html), "https://example.com")
    }

    func testNamedEntitiesDecode() {
        XCTAssertEqual(HTMLStripper.strip("Tom &amp; Jerry"), "Tom & Jerry")
        XCTAssertEqual(HTMLStripper.strip("a &lt; b &gt; c"), "a < b > c")
        XCTAssertEqual(HTMLStripper.strip("she said &quot;hi&quot;"), "she said \"hi\"")
    }

    func testNumericEntitiesDecode() {
        XCTAssertEqual(HTMLStripper.strip("it&#39;s"), "it's")
        XCTAssertEqual(HTMLStripper.strip("dash&#x2014;dash"), "dash—dash")
    }

    func testWhitespaceCollapsedAndTrimmed() {
        XCTAssertEqual(HTMLStripper.strip("  <p>  spaced   out  </p>  "), "spaced out")
    }

    func testEmptyAndPlain() {
        XCTAssertEqual(HTMLStripper.strip(""), "")
        XCTAssertEqual(HTMLStripper.strip("just text"), "just text")
    }
}
