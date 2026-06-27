//
//  BlueskyMappingTests.swift
//  FastSMCoreTests
//
//  Decodes representative app.bsky feed JSON and verifies mapping, including the
//  repost-reason boost wrapper.
//

import XCTest
@testable import FastSMCore

final class BlueskyMappingTests: XCTestCase {
    private func decodeFeed(_ json: String) throws -> [Status] {
        let dto = try BlueskyJSON.decoder.decode(BskyTimelineDTO.self, from: Data(json.utf8))
        return dto.feed.map(BlueskyMapper.feedEntry)
    }

    func testPlainPostMapping() throws {
        let json = """
        {
          "feed": [
            {
              "post": {
                "uri": "at://did:plc:abc/app.bsky.feed.post/xyz",
                "cid": "bafy123",
                "author": { "did": "did:plc:abc", "handle": "alice.bsky.social", "displayName": "Alice" },
                "record": { "text": "Hello Bluesky", "createdAt": "2024-01-15T10:30:00.000Z" },
                "replyCount": 1, "repostCount": 2, "likeCount": 3,
                "viewer": { "like": "at://did:plc:me/app.bsky.feed.like/rk1" }
              }
            }
          ]
        }
        """
        let statuses = try decodeFeed(json)
        XCTAssertEqual(statuses.count, 1)
        let status = statuses[0]
        XCTAssertEqual(status.id, "at://did:plc:abc/app.bsky.feed.post/xyz")
        XCTAssertEqual(status.text, "Hello Bluesky")
        XCTAssertEqual(status.favouritesCount, 3)
        XCTAssertEqual(status.boostsCount, 2)
        XCTAssertEqual(status.repliesCount, 1)
        XCTAssertTrue(status.favourited)
        XCTAssertFalse(status.boosted)
        XCTAssertEqual(status.account.username, "alice")
        XCTAssertEqual(status.visibility, .public)
        XCTAssertEqual(status.platform, .bluesky)
    }

    func testRepostWrapping() throws {
        let json = """
        {
          "feed": [
            {
              "post": {
                "uri": "at://did:plc:author/app.bsky.feed.post/orig",
                "cid": "bafy999",
                "author": { "did": "did:plc:author", "handle": "author.bsky.social", "displayName": "Author" },
                "record": { "text": "Original content", "createdAt": "2024-01-15T09:00:00.000Z" },
                "replyCount": 0, "repostCount": 1, "likeCount": 0
              },
              "reason": {
                "by": { "did": "did:plc:repo", "handle": "reposter.bsky.social", "displayName": "Reposter" },
                "indexedAt": "2024-01-15T10:00:00.000Z"
              }
            }
          ]
        }
        """
        let statuses = try decodeFeed(json)
        let status = statuses[0]
        XCTAssertTrue(status.isBoost)
        XCTAssertEqual(status.account.displayName, "Reposter")
        XCTAssertEqual(status.displayStatus.text, "Original content")
        XCTAssertEqual(status.displayStatus.account.displayName, "Author")
        XCTAssertTrue(status.id.hasSuffix(":repost"))
    }
}
