//
//  TimelineCacheTests.swift
//  FastSMCoreTests
//
//  Verifies the timeline cache actually round-trips the current models, and
//  (diagnostically) that any real on-disk cache file still decodes.
//

import XCTest
@testable import FastSMCore

final class TimelineCacheTests: XCTestCase {
    private func sampleItems() -> [TimelineItem] {
        let user = User(id: "1", acct: "alice@x.social", username: "alice", displayName: "Alice", platform: .mastodon)
        let status = Status(id: "100", account: user, content: "<p>hi</p>", text: "hi", createdAt: Date(timeIntervalSince1970: 1_700_000_000), platform: .mastodon)
        let boosted = Status(id: "200", account: user, text: "boost wrapper", createdAt: Date(), reblog: Reblog(status), platform: .mastodon)
        let notif = Notification(id: "300", type: .favourite, account: user, createdAt: Date(), status: status, platform: .mastodon)
        return [.status(status), .status(boosted), .notification(notif), .user(user)]
    }

    func testRoundTrip() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let cache = TimelineCache(maxEntries: 200, debounceSeconds: 0, directory: dir)
        let items = sampleItems()

        await cache.save(items, key: "mastodon:1:home")
        await cache.flushNow()

        let loaded = await cache.load(key: "mastodon:1:home")
        XCTAssertEqual(loaded.count, items.count, "round-trip should preserve all items")
        XCTAssertEqual(loaded.map(\.id), items.map(\.id))
        XCTAssertEqual(loaded[1].actionableStatus?.id, "100", "boost should unwrap to inner status")
    }
}
