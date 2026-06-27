//
//  TimelineMergeTests.swift
//  FastSMCoreTests
//
//  Regression: refreshing a chronological feed must keep it newest-first so the
//  cache cap drops the OLDEST, not the newest. The bug was that a deeper refetch
//  prepended older posts ahead of cached newer ones.
//

import XCTest
@testable import FastSMCore

/// Serves a fixed newest-first list of statuses, paginated by max_id.
private final class MockAccount: SocialAccount, @unchecked Sendable {
    let platform: Platform = .mastodon
    let me: User
    let maxChars = 500
    let features = PlatformFeatures()
    var defaultTimelines: [TimelineSource] { [.home] }
    var supportedTimelines: [TimelineSource] { [.home] }

    var all: [Status]   // newest-first
    var callCount = 0

    init(all: [Status]) {
        self.all = all
        me = User(id: "me", acct: "me", username: "me", displayName: "me", platform: .mastodon)
    }

    func items(for source: TimelineSource, limit: Int, cursor: PageCursor) async throws -> TimelinePage {
        callCount += 1
        let start: Int
        if let maxID = cursor.maxID, let idx = all.firstIndex(where: { $0.id == maxID }) {
            start = idx + 1
        } else {
            start = 0
        }
        guard start < all.count else { return TimelinePage(statuses: [], nextCursor: nil) }
        let slice = Array(all[start..<min(start + limit, all.count)])
        return TimelinePage(statuses: slice, nextCursor: slice.last.map { .maxID($0.id) })
    }

    func post(_ draft: PostDraft) async throws -> Status? { all.first }
    func editPost(_ id: String, draft: PostDraft) async throws -> Status? { all.first }
    func postSource(_ id: String) async throws -> PostSource? { nil }
    func resolveUser(handle: String) async throws -> User { me }
    func lists() async throws -> [TimelineList] { [] }
    func savedFeeds() async throws -> [TimelineList] { [] }
    func homeMarker() async throws -> String? { nil }
    func setHomeMarker(_ statusID: String) async throws {}
    func openStream(onEvent: @escaping @Sendable (StreamEvent) -> Void) -> StreamConnection? { nil }
    func resolve(_ status: Status) async throws -> Status { status }
    func boost(_ id: String) async throws {}
    func unboost(_ id: String) async throws {}
    func favorite(_ id: String) async throws {}
    func unfavorite(_ id: String) async throws {}
}

@MainActor
final class TimelineMergeTests: XCTestCase {
    func testNewPostsPrependNewestFirst() async {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        // s9 (newest) … s0 (oldest).
        let statuses: [Status] = (0..<10).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let account = MockAccount(all: statuses)
        let controller = TimelineController(pageSize: 4)
        controller.setTimeline(account: account, source: .home)

        controller.pageCountProvider = { 1 }
        await controller.refresh()
        XCTAssertEqual(controller.items.map { $0.actionableStatus?.id }, ["s9", "s8", "s7", "s6"])

        // A newer post arrives; refresh must place it on top (newest-first).
        let newest = Status(id: "s10", account: user, text: "10",
                            createdAt: Date(timeIntervalSince1970: 1000), platform: .mastodon)
        account.all.insert(newest, at: 0)
        await controller.refresh()
        XCTAssertEqual(controller.items.first?.actionableStatus?.id, "s10", "newest must be first")
        XCTAssertEqual(controller.items.map { $0.actionableStatus?.id },
                       ["s10", "s9", "s8", "s7", "s6"])
    }

    func testTimelineSourceCodableRoundTrip() throws {
        let sources: [TimelineSource] = [
            .home, .local, .federated,
            .thread(statusID: "abc", title: "Thread: Alice"),
            .userPosts(userID: "42", title: "@alice"),
        ]
        for source in sources {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(TimelineSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
        // And the persisted wrapper used to restore opened timelines.
        let persisted = PersistedTimeline(accountKey: "acct", source: .userPosts(userID: "1", title: "@bob"))
        let round = try JSONDecoder().decode(PersistedTimeline.self, from: JSONEncoder().encode(persisted))
        XCTAssertEqual(round, persisted)
    }

    func testRefreshStopsWhenCaughtUp() async {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        let statuses: [Status] = (0..<10).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let account = MockAccount(all: statuses)
        let controller = TimelineController(pageSize: 4)
        controller.setTimeline(account: account, source: .home)
        controller.pageCountProvider = { 5 }

        await controller.refresh()   // populate

        // A second refresh should stop after the first page (it overlaps what we
        // already have), not burn all 5 allowed pages.
        account.callCount = 0
        await controller.refresh()
        XCTAssertEqual(account.callCount, 1, "should stop once caught up to known posts")
    }
}
