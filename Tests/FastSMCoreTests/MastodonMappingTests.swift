//
//  MastodonMappingTests.swift
//  FastSMCoreTests
//
//  Decodes representative Mastodon JSON and verifies the mapping to universal
//  models, including reblog unwrapping and HTML stripping.
//

import XCTest
@testable import FastSMCore

final class MastodonMappingTests: XCTestCase {
    private func decodeStatus(_ json: String) throws -> Status {
        let dto = try MastodonJSON.decoder.decode(MastodonStatusDTO.self, from: Data(json.utf8))
        let status = MastodonMapper.status(dto)
        return try XCTUnwrap(status)
    }

    func testBasicStatusMapping() throws {
        let json = """
        {
          "id": "111",
          "created_at": "2024-01-15T10:30:00.000Z",
          "content": "<p>Hello &amp; welcome!</p>",
          "favourites_count": 5,
          "reblogs_count": 2,
          "replies_count": 1,
          "visibility": "public",
          "favourited": true,
          "reblogged": false,
          "account": {
            "id": "42",
            "acct": "alice@example.social",
            "username": "alice",
            "display_name": "Alice"
          }
        }
        """
        let status = try decodeStatus(json)
        XCTAssertEqual(status.id, "111")
        XCTAssertEqual(status.text, "Hello & welcome!")
        XCTAssertEqual(status.favouritesCount, 5)
        XCTAssertEqual(status.boostsCount, 2)
        XCTAssertEqual(status.repliesCount, 1)
        XCTAssertEqual(status.visibility, .public)
        XCTAssertTrue(status.favourited)
        XCTAssertFalse(status.boosted)
        XCTAssertEqual(status.account.displayName, "Alice")
        XCTAssertEqual(status.account.acct, "alice@example.social")
        XCTAssertEqual(status.platform, .mastodon)
        XCTAssertFalse(status.isBoost)
    }

    func testApplicationSourceMapping() throws {
        let json = """
        {
          "id": "300",
          "created_at": "2024-01-15T10:30:00.000Z",
          "content": "<p>hi</p>",
          "application": { "name": "FastSM for Mac", "website": "https://example.com" },
          "account": { "id": "1", "acct": "me", "username": "me", "display_name": "Me" }
        }
        """
        let status = try decodeStatus(json)
        XCTAssertEqual(status.applicationName, "FastSM for Mac")

        let speech = SpeechSettings.default.status.map {
            SpeechItem($0.field, $0.field == .source || $0.field == .text)
        }
        let label = StatusPresenter.accessibilityLabel(for: status, speech: speech)
        XCTAssertTrue(label.contains("via FastSM for Mac"), "got: \(label)")
    }

    func testReblogUnwrapping() throws {
        let json = """
        {
          "id": "200",
          "created_at": "2024-01-15T12:00:00.000Z",
          "content": "",
          "account": { "id": "1", "acct": "booster", "username": "booster", "display_name": "Booster" },
          "reblog": {
            "id": "199",
            "created_at": "2024-01-15T11:00:00.000Z",
            "content": "<p>Original post</p>",
            "account": { "id": "2", "acct": "author", "username": "author", "display_name": "Author" }
          }
        }
        """
        let status = try decodeStatus(json)
        XCTAssertTrue(status.isBoost)
        XCTAssertEqual(status.account.displayName, "Booster")
        XCTAssertEqual(status.displayStatus.id, "199")
        XCTAssertEqual(status.displayStatus.text, "Original post")
        XCTAssertEqual(status.displayStatus.account.displayName, "Author")
    }

    func testDisplayNameFallsBackToAcct() throws {
        let json = """
        {
          "id": "5", "created_at": "2024-01-15T10:30:00Z", "content": "hi",
          "account": { "id": "9", "acct": "bob@host", "username": "bob", "display_name": "" }
        }
        """
        let status = try decodeStatus(json)
        XCTAssertEqual(status.account.displayName, "bob@host")
        XCTAssertEqual(status.account.bestName, "bob@host")
    }

    func testQuoteURLStrippedFromText() {
        let url = URL(string: "https://mastodon.social/@alice/123")
        XCTAssertEqual(
            QuoteText.stripped("Great point https://mastodon.social/@alice/123", quotedURL: url),
            "Great point")
        XCTAssertEqual(
            QuoteText.stripped("RE: https://example.com/x my thoughts", quotedURL: nil),
            "my thoughts")
        // Trailing bare status URL even without a known quoted URL.
        XCTAssertEqual(
            QuoteText.stripped("nice https://example.com/@bob/999", quotedURL: nil),
            "nice")
        // No quote URL present: text untouched.
        XCTAssertEqual(
            QuoteText.stripped("just a normal post", quotedURL: nil),
            "just a normal post")
    }
}
