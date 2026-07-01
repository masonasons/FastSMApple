//
//  StatusStatsSpeechTests.swift
//  FastSMCoreTests
//
//  The reply/boost/favorite speech summary should omit any count that's zero —
//  "0 boosts" is just noise for a screen-reader user.
//

import XCTest
@testable import FastSMCore

final class StatusStatsSpeechTests: XCTestCase {
    private func status(replies: Int, boosts: Int, favorites: Int) -> Status {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        return Status(id: "s", account: user, text: "hi",
                      createdAt: Date(timeIntervalSince1970: 0),
                      favouritesCount: favorites, boostsCount: boosts, repliesCount: replies,
                      platform: .mastodon)
    }

    /// Just the stats field, so we're asserting on its phrasing alone.
    private func statsLabel(_ s: Status) -> String {
        StatusPresenter.accessibilityLabel(for: s, speech: [SpeechItem(.stats)])
    }

    func testOmitsZeroCounts() {
        XCTAssertEqual(statsLabel(status(replies: 0, boosts: 0, favorites: 5)), "5 favorites")
        XCTAssertEqual(statsLabel(status(replies: 2, boosts: 0, favorites: 0)), "2 replies")
        XCTAssertEqual(statsLabel(status(replies: 0, boosts: 1, favorites: 0)), "1 boost")
    }

    func testAllZeroSaysNothing() {
        XCTAssertEqual(statsLabel(status(replies: 0, boosts: 0, favorites: 0)), "")
    }

    func testNonZeroCountsJoinInOrder() {
        XCTAssertEqual(statsLabel(status(replies: 3, boosts: 2, favorites: 1)),
                       "3 replies, 2 boosts, 1 favorite")
        // Singular vs plural still correct.
        XCTAssertEqual(statsLabel(status(replies: 1, boosts: 0, favorites: 2)),
                       "1 reply, 2 favorites")
    }
}
