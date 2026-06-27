//
//  AppServices.swift
//  FastSM (macOS)
//
//  Shared, app-wide service container. Each timeline in the list has its own
//  TimelineController, and they ALL load in parallel on launch (regardless of
//  which is focused), so switching between them is instant and every timeline
//  stays current. The posts pane displays whichever controller is selected.
//

import Foundation
import FastSMCore

/// One entry in the timelines table: a specific source for a specific account.
struct TimelineRef: Equatable {
    let account: any SocialAccount
    let source: TimelineSource
    /// The timeline (cache key) this one was spawned from, for return-on-close.
    var originKey: String?

    var shortTitle: String { source.title }
    var title: String { "\(source.title) — @\(account.me.acct)" }

    static func == (lhs: TimelineRef, rhs: TimelineRef) -> Bool {
        lhs.account.accountKey == rhs.account.accountKey && lhs.source == rhs.source
    }
}

@MainActor
final class AppServices {
    let accountStore = AccountStore()
    let settings = SettingsStore()
    let cache = TimelineCache()
    let positions = PositionStore()
    let sound: SoundManager

    private(set) var timelineRefs: [TimelineRef] = []
    /// One controller per ref, in the same order; all load concurrently.
    private(set) var controllers: [TimelineController] = []
    private(set) var selectedTimelineIndex = 0

    /// The set of timelines changed (added/removed).
    var onTimelinesChanged: (() -> Void)?
    /// The selected timeline changed.
    var onSelectedTimelineChanged: (() -> Void)?
    /// The selected timeline's items/loading changed (drives the posts pane).
    var onSelectedItemsChanged: (() -> Void)?
    /// A load/action error to surface.
    var onError: ((Error) -> Void)?

    init() {
        sound = SoundManager()
        _ = AppServices.soundpacksDirectory()  // ensure it exists to paste packs into
        applyCacheLimit()
        applySounds()
        settings.onChange = { [weak self] in
            self?.applyCacheLimit()
            self?.applySounds()
            // Speech/display prefs changed — rebuild visible row labels.
            self?.onSelectedItemsChanged?()
            self?.restartAutoRefresh()
            self?.restartStreaming()
        }
        restartAutoRefresh()
    }

    private var streams: [StreamConnection] = []

    private func restartStreaming() {
        streams.forEach { $0.stop() }
        streams.removeAll()
        guard settings.settings.streamingEnabled else { return }
        for account in accountStore.accounts {
            let key = account.accountKey
            let stream = account.openStream { [weak self] event in
                Task { @MainActor in self?.handleStream(event, accountKey: key) }
            }
            if let stream { streams.append(stream) }
        }
    }

    private func controller(accountKey: String, source: TimelineSource) -> TimelineController? {
        guard let index = timelineRefs.firstIndex(where: {
            $0.account.accountKey == accountKey && $0.source == source
        }) else { return nil }
        return controllers[index]
    }

    private func handleStream(_ event: StreamEvent, accountKey: String) {
        switch event {
        case .update(let status):
            controller(accountKey: accountKey, source: .home)?.streamIn([.status(status)])
        case .notification(let notification):
            if notification.type == .mention, let status = notification.status {
                controller(accountKey: accountKey, source: .mentions)?.streamIn([.status(status)])
            } else {
                controller(accountKey: accountKey, source: .notifications)?.streamIn([.notification(notification)])
            }
        case .delete:
            break
        }
    }

    private var autoRefreshTask: Task<Void, Never>?

    private func restartAutoRefresh() {
        autoRefreshTask?.cancel()
        let seconds = settings.settings.autoRefreshSeconds
        guard seconds > 0 else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                for controller in self.controllers { await controller.refresh() }
            }
        }
    }

    private func applyCacheLimit() {
        let limit = settings.settings.cacheLimit
        Task { await cache.setMaxEntries(limit) }
    }

    private func applySounds() {
        sound.enabled = settings.settings.soundsEnabled
        sound.setSoundpack(directory: AppServices.soundpackDirectory(named: settings.settings.soundpack))
    }

    /// Folder that holds soundpack subfolders. Paste a soundpack folder here, then
    /// select it in Settings. Lives in the app's Application Support container.
    static func soundpacksDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let dir = base.appendingPathComponent("FastSM/soundpacks", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The folder for a named soundpack, or nil for the built-in Default.
    static func soundpackDirectory(named name: String) -> URL? {
        guard name != AppSettings.defaultSoundpackName, let base = soundpacksDirectory() else { return nil }
        return base.appendingPathComponent(name, isDirectory: true)
    }

    /// Default plus the names of installed soundpack folders.
    static func availableSoundpacks() -> [String] {
        var names = [AppSettings.defaultSoundpackName]
        if let base = soundpacksDirectory(),
           let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
            let folders = entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { $0.lastPathComponent }
                .sorted()
            names.append(contentsOf: folders)
        }
        return names
    }

    var selectedRef: TimelineRef? {
        timelineRefs.indices.contains(selectedTimelineIndex) ? timelineRefs[selectedTimelineIndex] : nil
    }

    var selectedController: TimelineController? {
        controllers.indices.contains(selectedTimelineIndex) ? controllers[selectedTimelineIndex] : nil
    }

    var activeAccount: (any SocialAccount)? {
        selectedRef?.account ?? accountStore.selectedAccount ?? accountStore.accounts.first
    }

    /// Timeline title shown in the list. The list only shows one account at a
    /// time, so the @account suffix is unnecessary.
    func displayTitle(for ref: TimelineRef) -> String { ref.shortTitle }

    /// The handle of the current account (for the window subtitle).
    var currentAccountHandle: String? { selectedRef.map { "@\($0.account.me.acct)" } }

    private func cacheKey(for ref: TimelineRef) -> String {
        "\(ref.account.accountKey):\(ref.source.cacheKey)"
    }

    /// Save the user-opened (non-default) timelines so they persist until closed.
    private func persistOpenTimelines() {
        positions.openTimelines = timelineRefs
            .filter { $0.source.isDismissable }
            .map { PersistedTimeline(accountKey: $0.account.accountKey, source: $0.source) }
    }

    // MARK: Local mute (per timeline)

    private(set) var mutedKeys: Set<String> = []

    func isMuted(at index: Int) -> Bool {
        timelineRefs.indices.contains(index) && mutedKeys.contains(cacheKey(for: timelineRefs[index]))
    }

    func toggleMute(at index: Int) {
        guard timelineRefs.indices.contains(index) else { return }
        let key = cacheKey(for: timelineRefs[index])
        if mutedKeys.contains(key) { mutedKeys.remove(key) } else { mutedKeys.insert(key) }
        onTimelinesChanged?()
    }

    /// Play an earcon unless the selected timeline is muted.
    func playEarcon(_ earcon: Earcon) {
        guard !isMuted(at: selectedTimelineIndex) else { return }
        sound.play(earcon)
    }

    /// Clear a specific timeline's items + cache (right-click → Clear Items).
    func clearTimeline(at index: Int) {
        guard controllers.indices.contains(index) else { return }
        let controller = controllers[index]
        Task { await controller.clear() }
    }

    /// Clear every timeline belonging to the current account (items + cache).
    func clearCurrentAccountTimelines() {
        guard let accountKey = selectedRef?.account.accountKey else { return }
        for index in timelineRefs.indices
        where timelineRefs[index].account.accountKey == accountKey && controllers.indices.contains(index) {
            let controller = controllers[index]
            Task { await controller.clear() }
        }
    }

    private func makeController(for ref: TimelineRef) -> TimelineController {
        let controller = TimelineController(cache: cache)
        controller.pageCountProvider = { [weak self] in self?.settings.settings.fetchPages ?? 1 }
        controller.setTimeline(account: ref.account, source: ref.source)
        controller.selectedID = positions.position(forKey: cacheKey(for: ref))
        controller.onChange = { [weak self] in
            guard let self, self.selectedController === controller else { return }
            self.onSelectedItemsChanged?()
        }
        controller.onError = { [weak self] error in self?.onError?(error) }
        controller.onReceivedNewItems = { [weak self] _ in self?.playNewItems(for: ref) }
        if ref.source == .home, ref.account.platform == .mastodon {
            controller.fetchHomeMarker = { [weak self] in
                guard self?.settings.settings.syncHomePosition == true else { return nil }
                return try? await ref.account.homeMarker()
            }
            controller.saveHomeMarker = { [weak self] id in
                guard self?.settings.settings.syncHomePosition == true else { return }
                try? await ref.account.setHomeMarker(id)
            }
        }
        return controller
    }

    /// Chime a timeline's "new posts" sound when it receives new posts on
    /// refresh (unless that timeline is muted).
    private func playNewItems(for ref: TimelineRef) {
        guard !mutedKeys.contains(cacheKey(for: ref)), let name = ref.source.newItemsSoundName else { return }
        sound.play(named: name)
    }

    /// Record the selected item for the current timeline (position memory).
    /// `fromUser` distinguishes genuine navigation (which syncs the home marker)
    /// from programmatic restores.
    func recordSelection(_ id: String?, fromUser: Bool = true) {
        guard let ref = selectedRef else { return }
        if fromUser {
            selectedController?.noteUserSelection(id)
        } else {
            selectedController?.selectedID = id
        }
        positions.setPosition(id, forKey: cacheKey(for: ref))
    }

    private var hasPlayedReady = false

    private func startLoading(_ controller: TimelineController) {
        Task {
            await controller.loadCached()
            await controller.refresh()   // refresh applies the home marker at its end
            // Chime "ready" once the app has finished its first load.
            if !hasPlayedReady {
                hasPlayedReady = true
                sound.play(named: "ready")
            }
        }
    }

    /// Rebuild the timelines list from the current accounts and load them all.
    func rebuildTimelines() async {
        for account in accountStore.accounts {
            Task { await account.loadConfiguration() }
        }
        timelineRefs = accountStore.accounts.flatMap { account in
            account.defaultTimelines.map { TimelineRef(account: account, source: $0) }
        }
        // Restore timelines the user opened last session (threads, user/local/
        // federated, lists), for accounts that still exist.
        for persisted in positions.openTimelines {
            guard let account = accountStore.accounts.first(where: { $0.accountKey == persisted.accountKey }) else { continue }
            let ref = TimelineRef(account: account, source: persisted.source)
            if !timelineRefs.contains(ref) { timelineRefs.append(ref) }
        }
        controllers = timelineRefs.map(makeController)
        let activeKeys = Set(timelineRefs.map(cacheKey(for:)))
        if let key = positions.selectedTimelineKey, let index = timelineRefs.firstIndex(where: { cacheKey(for: $0) == key }) {
            selectedTimelineIndex = index
        } else {
            selectedTimelineIndex = min(selectedTimelineIndex, max(0, timelineRefs.count - 1))
        }
        Task { await cache.removeAll(except: activeKeys) }
        positions.prune(keeping: activeKeys)

        onTimelinesChanged?()
        onSelectedTimelineChanged?()
        onSelectedItemsChanged?()

        // Load every timeline in parallel, focused or not.
        for controller in controllers { startLoading(controller) }

        restartStreaming()
    }

    func selectTimeline(at index: Int) {
        guard timelineRefs.indices.contains(index) else { return }
        selectedTimelineIndex = index
        positions.selectedTimelineKey = cacheKey(for: timelineRefs[index])
        onSelectedTimelineChanged?()
        onSelectedItemsChanged?()
    }

    /// Only the current account's timelines are shown at once. The current
    /// account is whichever owns the selected timeline.
    var visibleRefs: [TimelineRef] {
        guard let key = selectedRef?.account.accountKey else { return timelineRefs }
        return timelineRefs.filter { $0.account.accountKey == key }
    }

    /// Select a timeline by its row in the visible (current-account) list.
    func selectVisible(at row: Int) {
        guard visibleRefs.indices.contains(row),
              let index = timelineRefs.firstIndex(of: visibleRefs[row]) else { return }
        selectTimeline(at: index)
    }

    func nextTimeline() {
        let visible = visibleRefs
        guard !visible.isEmpty, let ref = selectedRef,
              let current = visible.firstIndex(of: ref) else { return }
        selectVisible(at: (current + 1) % visible.count)
    }

    func previousTimeline() {
        let visible = visibleRefs
        guard !visible.isEmpty, let ref = selectedRef,
              let current = visible.firstIndex(of: ref) else { return }
        selectVisible(at: (current - 1 + visible.count) % visible.count)
    }

    /// Jump to the Nth timeline in the current account (1-based), for ⌘1…⌘9.
    func selectTimeline(number: Int) {
        selectVisible(at: number - 1)
    }

    /// Switch to the previous/next account and select its first timeline.
    func switchAccount(offset: Int) {
        let accounts = accountStore.accounts
        guard !accounts.isEmpty else { return }
        let currentKey = selectedRef?.account.accountKey
        let currentIndex = accounts.firstIndex { $0.accountKey == currentKey } ?? 0
        let target = accounts[(currentIndex + offset + accounts.count) % accounts.count]
        if let index = timelineRefs.firstIndex(where: { $0.account.accountKey == target.accountKey }) {
            selectTimeline(at: index)
            onTimelinesChanged?()   // the visible (current-account) list changed
        }
    }

    /// Spawn (or re-select) a timeline for `source`, load it, and select it.
    func spawnTimeline(_ source: TimelineSource, for account: any SocialAccount) {
        var ref = TimelineRef(account: account, source: source)
        ref.originKey = selectedRef.map(cacheKey(for:))   // remember where we came from
        if let index = timelineRefs.firstIndex(of: ref) {
            selectTimeline(at: index)
            return
        }
        timelineRefs.append(ref)
        let controller = makeController(for: ref)
        controllers.append(controller)
        persistOpenTimelines()
        onTimelinesChanged?()
        selectTimeline(at: timelineRefs.count - 1)
        startLoading(controller)
    }

    /// Show an on-demand standing feed (Local / Federated) for the current account.
    func showTimeline(source: TimelineSource) {
        guard let account = activeAccount else { return }
        guard account.supportedTimelines.contains(source) else {
            sound.play(.error)
            return
        }
        spawnTimeline(source, for: account)
    }

    /// Close a dismissable (spawned) timeline. If it was selected, return to the
    /// timeline it was spawned from (origin), else a neighbor.
    func closeTimeline(at index: Int) {
        guard timelineRefs.indices.contains(index) else { return }
        guard timelineRefs[index].source.isDismissable else {
            sound.play(.error)
            return
        }
        let closed = timelineRefs[index]
        let wasSelected = index == selectedTimelineIndex
        let previouslySelectedKey = selectedRef.map(cacheKey(for:))
        let key = cacheKey(for: closed)

        timelineRefs.remove(at: index)
        controllers.remove(at: index)
        Task { await cache.remove(key: key) }
        positions.setPosition(nil, forKey: key)
        persistOpenTimelines()
        sound.play(.close)

        // Settle the selection to a VALID index BEFORE notifying the UI. The
        // visible timeline list is derived from the selection, so a stale index
        // here makes the table read out of bounds during its next layout.
        if timelineRefs.isEmpty {
            selectedTimelineIndex = 0
        } else if wasSelected {
            if let origin = closed.originKey, let originIndex = timelineRefs.firstIndex(where: { cacheKey(for: $0) == origin }) {
                selectedTimelineIndex = originIndex
            } else {
                selectedTimelineIndex = min(index, timelineRefs.count - 1)
            }
        } else if let key = previouslySelectedKey, let newIndex = timelineRefs.firstIndex(where: { cacheKey(for: $0) == key }) {
            selectedTimelineIndex = newIndex
        } else {
            selectedTimelineIndex = min(selectedTimelineIndex, timelineRefs.count - 1)
        }
        positions.selectedTimelineKey = selectedRef.map(cacheKey(for:))

        onTimelinesChanged?()
        onSelectedTimelineChanged?()
        onSelectedItemsChanged?()
    }

    func closeCurrentTimeline() {
        closeTimeline(at: selectedTimelineIndex)
    }
}
