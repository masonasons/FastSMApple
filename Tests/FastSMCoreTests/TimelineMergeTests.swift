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
    var supportsIDPagination: Bool { true }
    var defaultTimelines: [TimelineSource] { [.home] }
    var supportedTimelines: [TimelineSource] { [.home] }

    var all: [Status]   // newest-first
    var callCount = 0
    var lastMaxID: String?
    /// If set, return at most this many items per page regardless of `limit`.
    var serverPageSize: Int?

    init(all: [Status]) {
        self.all = all
        me = User(id: "me", acct: "me", username: "me", displayName: "me", platform: .mastodon)
    }

    /// Fires inside a fetch, to simulate something (e.g. streaming) mutating the
    /// timeline while a refresh awaits the network.
    var onFetch: (() -> Void)?

    func items(for source: TimelineSource, limit: Int, cursor: PageCursor) async throws -> TimelinePage {
        callCount += 1
        lastMaxID = cursor.maxID
        onFetch?()
        let start: Int
        if let maxID = cursor.maxID, let idx = all.firstIndex(where: { $0.id == maxID }) {
            start = idx + 1
        } else {
            start = 0
        }
        guard start < all.count else { return TimelinePage(statuses: [], nextCursor: nil) }
        // Mastodon often returns fewer than `limit` items mid-timeline; mimic that.
        let perPage = min(limit, serverPageSize ?? limit)
        let slice = Array(all[start..<min(start + perPage, all.count)])
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

    private func shortPageController() -> (TimelineController, MockAccount) {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        let statuses = (0..<20).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let account = MockAccount(all: statuses)
        account.serverPageSize = 3   // server returns 3/page even though limit is 40
        let controller = TimelineController(pageSize: 40)
        controller.setTimeline(account: account, source: .home)
        return (controller, account)
    }

    func testRefreshLoadsAllPagesDespiteShortPages() async {
        let (controller, _) = shortPageController()
        controller.pageCountProvider = { 3 }
        await controller.refresh()
        XCTAssertEqual(controller.items.count, 9, "3 pages × 3 items; a short page must not stop the loop")
    }

    func testScrollbackLoadsAllPagesDespiteShortPages() async {
        let (controller, _) = shortPageController()
        controller.pageCountProvider = { 1 }
        await controller.refresh()
        XCTAssertEqual(controller.items.count, 3)
        controller.pageCountProvider = { 3 }
        await controller.loadOlder()
        XCTAssertEqual(controller.items.count, 12, "scrollback must load all 3 pages despite short pages")
    }

    func testConcurrentLoadOlderTriggersLoadOneRound() async {
        let (controller, _) = shortPageController()
        controller.pageCountProvider = { 1 }
        await controller.refresh()
        let afterRefresh = controller.items.count
        controller.pageCountProvider = { 3 }
        // The bottom rows fire loadOlder near-simultaneously; only ONE round of
        // fetchPages pages must run, not a coalesced second round (the 800-not-400 bug).
        async let a: Void = controller.loadOlder()
        async let b: Void = controller.loadOlder()
        _ = await (a, b)
        XCTAssertEqual(controller.items.count, afterRefresh + 9,
                       "concurrent triggers must not double-load")
    }

    func testRefreshDoesNotDuplicateItemStreamedDuringFetch() async {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        let statuses = (0..<5).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let account = MockAccount(all: statuses)
        let controller = TimelineController(pageSize: 10)
        controller.setTimeline(account: account, source: .mentions)
        controller.pageCountProvider = { 1 }
        await controller.refresh()

        // A new post arrives; streaming inserts it WHILE the next refresh awaits
        // the network, and the fetch also returns it.
        let incoming = Status(id: "s5", account: user, text: "5",
                              createdAt: Date(timeIntervalSince1970: 500), platform: .mastodon)
        account.all.insert(incoming, at: 0)
        account.onFetch = { controller.streamIn([.status(incoming)]) }
        await controller.refresh()
        account.onFetch = nil

        let incomingID = TimelineItem.status(incoming).id
        XCTAssertEqual(controller.items.filter { $0.id == incomingID }.count, 1,
                       "a post streamed in mid-refresh must not be duplicated")
    }

    func testCacheSeededScrollbackUsesRawID() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let cache = TimelineCache(maxEntries: 200, debounceSeconds: 0, directory: dir)
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        let statuses = (0..<6).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let account = MockAccount(all: statuses)
        let items = statuses.map { TimelineItem.status($0) }   // s5 (newest) … s0 (oldest)
        await cache.save(items, key: "\(account.accountKey):\(TimelineSource.home.cacheKey)")

        let controller = TimelineController(pageSize: 10, cache: cache)
        controller.setTimeline(account: account, source: .home)
        await controller.loadCached()
        XCTAssertFalse(controller.items.isEmpty, "cache should have loaded")

        await controller.loadOlder()
        // The cursor must be the RAW status id ("s0"), not the prefixed
        // TimelineItem id ("s:s0") that broke scrollback from cache.
        XCTAssertEqual(account.lastMaxID, "s0")
        XCTAssertFalse(account.lastMaxID?.contains(":") ?? false,
                       "max_id must not be a prefixed TimelineItem id")
    }

    private func loadedController() async -> TimelineController {
        let user = User(id: "u", acct: "u", username: "u", displayName: "u", platform: .mastodon)
        let statuses: [Status] = (0..<10).reversed().map { i in
            Status(id: "s\(i)", account: user, text: "\(i)",
                   createdAt: Date(timeIntervalSince1970: Double(i) * 100), platform: .mastodon)
        }
        let controller = TimelineController(pageSize: 10)
        controller.setTimeline(account: MockAccount(all: statuses), source: .home)
        controller.pageCountProvider = { 1 }
        await controller.refresh()
        return controller
    }

    func testNavigationHistoryRecordsJumpsOnly() async {
        let controller = await loadedController()
        let ids = controller.items.map(\.id)
        XCTAssertEqual(ids.count, 10)

        controller.noteUserSelection(ids[0])
        controller.noteUserSelection(ids[5])  // jump (5 rows) -> records ids[0]
        controller.noteUserSelection(ids[6])  // single step -> not recorded
        controller.noteUserSelection(ids[2])  // jump (4 rows) -> records ids[6]

        XCTAssertEqual(controller.undoNavigation(), ids[6])
        XCTAssertEqual(controller.undoNavigation(), ids[0])
        XCTAssertNil(controller.undoNavigation(), "history exhausted")
    }

    func testNavigationHistoryEveryStepWhenEnabled() async {
        TimelineController.recordsEveryNavStep = true
        defer { TimelineController.recordsEveryNavStep = false }
        let controller = await loadedController()
        let ids = controller.items.map(\.id)

        controller.noteUserSelection(ids[0])
        controller.noteUserSelection(ids[1])  // single step -> recorded because flag is on
        controller.noteUserSelection(ids[2])

        XCTAssertEqual(controller.undoNavigation(), ids[1])
        XCTAssertEqual(controller.undoNavigation(), ids[0])
    }

    func testGoBackNavigateGoBackAgain() async {
        let controller = await loadedController()
        let ids = controller.items.map(\.id)

        controller.noteUserSelection(ids[0])
        controller.noteUserSelection(ids[4])           // jump -> records ids[0]

        // Go back: pop ids[0]; UI restores selectedID WITHOUT recording.
        XCTAssertEqual(controller.undoNavigation(), ids[0])
        controller.selectedID = ids[0]                 // mimics recordSelection(fromUser:false)

        controller.noteUserSelection(ids[7])           // a NEW jump must be recorded
        XCTAssertEqual(controller.undoNavigation(), ids[0],
                       "navigation after a go-back must refill the history")
    }

    func testNavigationHistorySkipsVanishedAndCapsAtTen() async {
        let controller = await loadedController()
        let ids = controller.items.map(\.id)
        // 12 jumps alternating across the list; only the last 10 are retained.
        var prev = ids[0]
        controller.noteUserSelection(prev)
        for i in 1...12 {
            let next = ids[(i * 3) % 10]
            controller.noteUserSelection(next)
            prev = next
        }
        var popped = 0
        while controller.undoNavigation() != nil { popped += 1 }
        XCTAssertLessThanOrEqual(popped, 10, "history is capped at 10")
    }
}
