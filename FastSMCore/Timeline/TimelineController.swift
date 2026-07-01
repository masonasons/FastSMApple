//
//  TimelineController.swift
//  FastSMCore
//
//  Loads and paginates the selected timeline for an account and applies
//  optimistic boost/favorite toggles. Content is a list of `TimelineItem`, so
//  the same pipeline serves status timelines (home/local/federated/mentions/
//  conversations) and the notifications timeline. UI-framework agnostic: AppKit
//  observes via `onChange`; SwiftUI wraps it in an @Observable model.
//

import Foundation

@MainActor
public final class TimelineController {
    public private(set) var items: [TimelineItem] = []
    public private(set) var isLoading = false
    /// The id of the item the user last had selected in this timeline (for
    /// position memory / restore). UI-owned; the controller just holds it.
    public var selectedID: String?

    // MARK: Navigation history (undo)

    /// Recent prior positions in this timeline, oldest first, for undo-navigation.
    private var navHistory: [String] = []
    private let maxNavHistory = 10
    /// When true, every selection move is recorded; otherwise only "jumps" (moves
    /// of more than one row). App-wide preference, set from settings.
    public static var recordsEveryNavStep = false

    /// Fired after `items`/`isLoading` change so non-observing UIs refresh.
    public var onChange: (() -> Void)?
    /// Fired when a load or action fails, with a user-presentable error.
    public var onError: ((Error) -> Void)?
    /// Home-position sync (Mastodon markers): the app wires these for the home
    /// timeline when the setting is on. nil = no sync.
    public var fetchHomeMarker: (() async -> String?)?
    public var saveHomeMarker: ((String) async -> Void)?
    private var userMovedPosition = false
    private var lastSyncedMarker: String?
    private var markerSaveTask: Task<Void, Never>?

    /// The status id of the currently-selected row (for marker sync).
    private var selectedStatusID: String? {
        items.first(where: { $0.id == selectedID })?.actionableStatus?.id
    }

    /// Record a user-initiated selection and (if syncing) push the marker.
    public func noteUserSelection(_ id: String?) {
        recordNavigation(leaving: selectedID, arrivingAt: id)
        selectedID = id
        userMovedPosition = true
        guard saveHomeMarker != nil, let statusID = selectedStatusID, statusID != lastSyncedMarker else { return }
        lastSyncedMarker = statusID
        markerSaveTask?.cancel()
        markerSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.saveHomeMarker?(statusID)
        }
    }

    /// Push the position being left onto the history stack. A "jump" (selection
    /// moving more than one row, or to/from an item not in the list) is always
    /// recorded; single-row steps only when `recordsEveryNavStep` is on.
    private func recordNavigation(leaving oldID: String?, arrivingAt newID: String?) {
        guard let oldID, oldID != newID else { return }
        let oldIndex = items.firstIndex { $0.id == oldID }
        let newIndex = newID.flatMap { id in items.firstIndex { $0.id == id } }
        let isJump: Bool
        if let oldIndex, let newIndex { isJump = abs(oldIndex - newIndex) > 1 } else { isJump = true }
        guard isJump || Self.recordsEveryNavStep else { return }
        guard navHistory.last != oldID else { return }
        navHistory.append(oldID)
        if navHistory.count > maxNavHistory { navHistory.removeFirst() }
    }

    /// Pop the most recent prior position that still exists in the timeline, for
    /// undo-navigation. Returns the id the UI should move selection to (via a
    /// programmatic, non-recording restore), or nil if there's nothing to undo.
    public func undoNavigation() -> String? {
        while let target = navHistory.popLast() {
            if items.contains(where: { $0.id == target }) { return target }
        }
        return nil
    }

    /// On first load, move to the server-synced position if available.
    /// Move to the server-synced position, unless the user has moved the position
    /// themselves this session. Runs after every refresh (like the Windows app).
    public func applyHomeMarkerIfNeeded() async {
        guard let fetchHomeMarker, !userMovedPosition else { return }
        guard let markerID = await fetchHomeMarker(),
              let item = items.first(where: { $0.actionableStatus?.id == markerID }) else { return }
        lastSyncedMarker = markerID
        if selectedID != item.id {
            selectedID = item.id
            onChange?()
        }
    }

    /// Fired (with the count) when a refresh merges new posts into an already-
    /// populated timeline — used to chime the timeline's "new posts" sound. Not
    /// fired on the initial/cold load.
    public var onReceivedNewItems: ((Int) -> Void)?

    private var account: (any SocialAccount)?
    private var source: TimelineSource = .home
    private var nextCursor: PageCursor?
    /// Whether there's a known next page to load (drives the UI's load-more footer).
    public var hasMore: Bool { nextCursor != nil }
    private let pageSize: Int
    private let cache: TimelineCache?

    /// Number of pages to fetch per refresh. Supplied by the app from settings.
    public var pageCountProvider: () -> Int = { 1 }

    public init(pageSize: Int = 40, cache: TimelineCache? = nil) {
        self.pageSize = pageSize
        self.cache = cache
    }

    public var account_: (any SocialAccount)? { account }

    /// Cache key namespaced per account *and* source. Every timeline is cached;
    /// closed (dismissed) timelines have their cache removed by the caller.
    private var cacheKey: String? {
        guard let account else { return nil }
        return "\(account.accountKey):\(source.cacheKey)"
    }

    /// Point the controller at an account + source and clear content.
    public func setTimeline(account: (any SocialAccount)?, source: TimelineSource) {
        self.account = account
        self.source = source
        items = []
        nextCursor = nil
        onChange?()
    }

    /// Convenience for callers that only use the home timeline (e.g. iOS).
    public func setAccount(_ account: (any SocialAccount)?) {
        setTimeline(account: account, source: .home)
    }

    /// Empty the current timeline's items and delete its cache. The account and
    /// source are kept, so a refresh reloads it.
    public func clear() async {
        items = []
        nextCursor = nil
        onChange?()
        if let cache, let cacheKey {
            await cache.remove(key: cacheKey)
        }
    }

    /// Show cached items immediately (instant startup) before the network load.
    public func loadCached() async {
        guard let cache, let cacheKey, items.isEmpty else { return }
        let cached = await cache.load(key: cacheKey)
        guard !cached.isEmpty, items.isEmpty else { return }
        items = cached
        // Seed the cursor BELOW the cached backlog so scrollback fetches older
        // posts, not the pages we already have. (Mastodon paginates by raw id;
        // Bluesky's opaque cursor can't be reconstructed from items, so it falls
        // back to refresh-driven seeding.)
        if account?.supportsIDPagination == true, source.paginatesByItemID,
           let oldest = cached.last, let rawID = paginationID(of: oldest) {
            nextCursor = .maxID(rawID)
        }
        onChange?()
    }

    /// The RAW api id to paginate before, for cache-seeding the scrollback cursor.
    /// `TimelineItem.id` is prefixed ("s:"/"n:"), so it can't be used directly.
    /// Mentions display statuses but paginate by NOTIFICATION id, which a cached
    /// status doesn't carry — so they return nil and let refresh seed the cursor.
    private func paginationID(of item: TimelineItem) -> String? {
        switch source {
        case .notifications:
            if case .notification(let notification) = item { return notification.id }
            return nil
        case .mentions:
            return nil
        default:
            if case .status(let status) = item { return status.id }
            return nil
        }
    }

    /// Keep chronological feeds strictly newest-first so the cache cap drops the
    /// oldest, not the newest. Threads / user lists keep their natural order.
    private func normalizeOrder() {
        guard source.isTimeOrdered else { return }
        items.sort { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
    }

    private func persistToCache() {
        guard let cache, let cacheKey else { return }
        let snapshot = items
        Task { await cache.save(snapshot, key: cacheKey) }
    }

    /// Fetch the newest page and merge it into the existing backlog: brand-new
    /// posts are prepended on top, and the cached history below is preserved
    /// (rather than collapsing the timeline back to a single page on every
    /// launch/refresh).
    public func refresh() async {
        guard let account else { return }
        setLoading(true)
        defer { setLoading(false) }
        do {
            // Fetch up to N pages from the top, following the cursor — but stop
            // early once we reach posts we already have (caught up, no gap) or the
            // server returns a short page (end of timeline). This avoids wasting
            // API calls when there's little new to fetch.
            let existingIDs = Set(items.map(\.id))
            let pageCount = max(1, pageCountProvider())
            var fetched: [TimelineItem] = []
            var seen = Set<String>()
            var cursor: PageCursor = .start
            var bottomCursor: PageCursor?
            for _ in 0..<pageCount {
                let page = try await account.items(for: source, limit: pageSize, cursor: cursor)
                for item in page.items where !seen.contains(item.id) {
                    seen.insert(item.id)
                    fetched.append(item)
                }
                bottomCursor = page.nextCursor
                if !existingIDs.isEmpty, page.items.contains(where: { existingIDs.contains($0.id) }) { break }
                // Stop at the real end only — an empty page or no next cursor.
                // Mastodon often returns fewer than `limit` items mid-timeline, so
                // a short (non-empty) page must NOT be treated as the end.
                if page.items.isEmpty { break }
                guard let next = page.nextCursor else { break }
                cursor = next
            }

            var newItemCount = 0
            if items.isEmpty {
                items = fetched
                nextCursor = bottomCursor
            } else {
                // Update posts we already have with the freshly fetched copy, so
                // re-fetched data (counts, source app, fav/boost state) replaces
                // stale cached versions instead of being discarded.
                let fetchedByID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                items = items.map { fetchedByID[$0.id] ?? $0 }
                // De-dupe against the CURRENT items, not the pre-await snapshot:
                // streaming may have inserted an item while we awaited the network,
                // and prepending it again here would duplicate it.
                let currentIDs = Set(items.map(\.id))
                let fresh = fetched.filter { !currentIDs.contains($0.id) }
                newItemCount = fresh.count
                items = fresh + items
                // Keep paginating older from the bottom of the backlog. If we
                // launched from cache with no cursor yet, seed one (loadOlder
                // de-dupes, so any re-fetched overlap is harmless).
                if nextCursor == nil { nextCursor = bottomCursor }
            }
            normalizeOrder()
            onChange?()
            persistToCache()
            if newItemCount > 0 { onReceivedNewItems?(newItemCount) }
            await applyHomeMarkerIfNeeded()
        } catch {
            // A cancelled refresh (superseded by a newer one, or interrupted by a
            // live stream update re-rendering the view) is not a failure.
            if error.isCancellation { return }
            onError?(error)
        }
    }

    /// Append older posts. Fetches up to `fetchPages` pages per scrollback so the
    /// page-count setting applies to loading history, not just refresh.
    public func loadOlder() async {
        // Ignore the redundant triggers the bottom rows fire near-simultaneously:
        // one round already loads `fetchPages` pages, and the freshly-appended
        // rows are off-screen so they don't re-trigger until the user scrolls —
        // so coalescing an extra round here just double-loads (e.g. 800 not 400).
        guard account != nil, nextCursor != nil, !isLoading else { return }
        setLoading(true)
        await fetchOlderPage()
        setLoading(false)
    }

    private func fetchOlderPage() async {
        guard let account, var cursor = nextCursor else { return }
        do {
            let pageCount = max(1, pageCountProvider())
            var existingIDs = Set(items.map(\.id))
            var bottomCursor: PageCursor? = cursor
            for _ in 0..<pageCount {
                let page = try await account.items(for: source, limit: pageSize, cursor: cursor)
                let fresh = page.items.filter { !existingIDs.contains($0.id) }
                fresh.forEach { existingIDs.insert($0.id) }
                items.append(contentsOf: fresh)
                bottomCursor = page.nextCursor
                // Stop at the real end only. A short (non-empty) page is normal
                // for Mastodon mid-timeline; an empty page or missing cursor is
                // the actual end.
                if page.items.isEmpty { bottomCursor = nil; break }
                guard let next = page.nextCursor else { break }
                cursor = next
            }
            nextCursor = bottomCursor
            normalizeOrder()
            onChange?()
            persistToCache()
        } catch {
            if error.isCancellation { return }
            onError?(error)
        }
    }

    // MARK: Actions

    /// Returns true if the favorite/unfavorite actually went through.
    @discardableResult
    public func toggleFavorite(at index: Int) async -> Bool {
        await toggle(
            at: index,
            current: { $0.actionableStatus?.favourited ?? false },
            optimistic: { $0.setFavourited($1) },
            perform: { account, id, value in
                if value { try await account.favorite(id) } else { try await account.unfavorite(id) }
            }
        )
    }

    /// Returns true if the boost/unboost actually went through.
    @discardableResult
    public func toggleBoost(at index: Int) async -> Bool {
        await toggle(
            at: index,
            current: { $0.actionableStatus?.boosted ?? false },
            optimistic: { $0.setBoosted($1) },
            perform: { account, id, value in
                if value { try await account.boost(id) } else { try await account.unboost(id) }
            }
        )
    }

    /// Returns true if the bookmark/unbookmark actually went through.
    @discardableResult
    public func toggleBookmark(at index: Int) async -> Bool {
        await toggle(
            at: index,
            current: { $0.actionableStatus?.bookmarked ?? false },
            optimistic: { $0.setBookmarked($1) },
            perform: { account, id, value in
                if value { try await account.bookmark(id) } else { try await account.unbookmark(id) }
            }
        )
    }

    @discardableResult
    public func post(_ draft: PostDraft) async throws -> Status? {
        guard let account else { throw PlatformError.notAuthenticated }
        let status = try await account.post(draft)
        // Surface our own new top-level post immediately on status timelines.
        // (Scheduled posts return nil — nothing to insert yet.)
        if let status, draft.replyToID == nil, !source.isNotificationTimeline {
            items.insert(.status(status), at: 0)
            onChange?()
        }
        return status
    }

    /// Insert items pushed in real time by a stream: prepend new ones, keep order,
    /// persist, and chime the timeline's sound.
    public func streamIn(_ newItems: [TimelineItem]) {
        let existing = Set(items.map(\.id))
        let fresh = newItems.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        items = fresh + items
        normalizeOrder()
        onChange?()
        persistToCache()
        onReceivedNewItems?(fresh.count)
    }

    /// The actionable status at `index`, resolved to the local copy if it came
    /// from a remote instance (so it can be replied to / quoted).
    public func resolvedStatus(at index: Int) async -> Status? {
        guard let account, items.indices.contains(index),
              let status = items[index].actionableStatus else { return nil }
        return (try? await account.resolve(status)) ?? status
    }

    @discardableResult
    public func editPost(_ id: String, draft: PostDraft) async throws -> Status? {
        guard let account else { throw PlatformError.notAuthenticated }
        let updated = try await account.editPost(id, draft: draft)
        // Replace the edited post in place wherever it appears.
        if let updated, let index = items.firstIndex(where: { $0.actionableStatus?.id == id }) {
            items[index] = .status(updated)
            onChange?()
            persistToCache()
        }
        return updated
    }

    // MARK: Internals

    /// Returns whether the remote action succeeded, so callers can defer success
    /// feedback (earcons) until it's actually gone through.
    @discardableResult
    private func toggle(
        at index: Int,
        current: (TimelineItem) -> Bool,
        optimistic: (inout TimelineItem, Bool) -> Void,
        perform: (any SocialAccount, String, Bool) async throws -> Void
    ) async -> Bool {
        guard let account, items.indices.contains(index),
              let actionable = items[index].actionableStatus else { return false }
        let newValue = !current(items[index])

        optimistic(&items[index], newValue)
        onChange?()

        do {
            // Remote-instance posts need resolving to a local id first.
            let targetID = (try await account.resolve(actionable)).id
            try await perform(account, targetID, newValue)
            return true
        } catch {
            if items.indices.contains(index) {
                optimistic(&items[index], !newValue)
                onChange?()
            }
            onError?(error)
            return false
        }
    }

    private func setLoading(_ value: Bool) {
        isLoading = value
        onChange?()
    }
}
