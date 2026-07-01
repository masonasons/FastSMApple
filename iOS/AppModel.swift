//
//  AppModel.swift
//  FastSM (iOS)
//
//  Observable app state. Manages all timelines (one TimelineController each,
//  loaded in parallel) for the paged UI, plus accounts, settings, sound, and
//  the OAuth anchor.
//

import Foundation
import Observation
import AuthenticationServices
import UIKit
import FastSMCore

/// One timeline page: a source for an account, plus its controller.
struct TimelineRef: Identifiable, Equatable {
    let account: any SocialAccount
    let source: TimelineSource
    /// The timeline (key) this one was spawned from, for return-on-close.
    var originKey: String?

    var key: String { "\(account.accountKey):\(source.cacheKey)" }
    var id: String { key }
    var shortTitle: String { source.title }
    var fullTitle: String { "\(source.title) · @\(account.me.acct)" }

    var symbol: String {
        switch source {
        case .home: return "house"
        case .notifications: return "bell"
        case .mentions: return "at"
        case .conversations: return "bubble.left.and.bubble.right"
        case .local: return "person.2"
        case .federated: return "globe"
        case .thread: return "text.bubble"
        case .userPosts: return "person.crop.square"
        case .followers, .following: return "person.2.fill"
        case .hashtag: return "number"
        case .favorites: return "star"
        case .bookmarks: return "bookmark"
        case .list: return "list.bullet.rectangle"
        case .trending: return "chart.line.uptrend.xyaxis"
        case .search: return "magnifyingglass"
        case .feed: return "antenna.radiowaves.left.and.right"
        case .remoteLocal: return "globe.badge.chevron.backward"
        case .remoteUser: return "person.crop.circle.badge.questionmark"
        }
    }

    static func == (lhs: TimelineRef, rhs: TimelineRef) -> Bool { lhs.key == rhs.key }
}

@MainActor
@Observable
final class AppModel {
    let accountStore = AccountStore()
    let settings = SettingsStore()
    let cache = TimelineCache()
    let positions = PositionStore()
    let sound = SoundManager()
    @ObservationIgnored lazy var anchor = AnchorProvider()

    // One controller per timeline, parallel arrays with `refs`.
    private(set) var refs: [TimelineRef] = []
    @ObservationIgnored private var controllers: [String: TimelineController] = [:]

    // Mirrored, observable per-timeline state.
    var itemsByKey: [String: [TimelineItem]] = [:]
    var mutedKeys: Set<String> = []
    var selectedKey: String? {
        didSet {
            positions.selectedTimelineKey = selectedKey
            // Remember the order timelines were viewed so closing one returns to
            // the timeline you were on before it, not the next one in the list.
            if let old = oldValue, old != selectedKey {
                selectionHistory.removeAll { $0 == old }
                selectionHistory.append(old)
                if selectionHistory.count > 20 { selectionHistory.removeFirst() }
            }
        }
    }
    /// Keys of previously-selected timelines, oldest first (most recent last).
    private var selectionHistory: [String] = []
    var presentedError: PresentedError?
    var accountsVersion = 0
    /// Set to present the compose sheet (new post, reply, or quote).
    var composeRequest: ComposeRequest?

    var hasAccounts: Bool { !accountStore.isEmpty }
    var hasMultipleAccounts: Bool { accountStore.accounts.count > 1 }

    var selectedRef: TimelineRef? {
        guard let key = selectedKey else { return refs.first }
        return refs.first { $0.key == key } ?? refs.first
    }
    var selectedAccount: (any SocialAccount)? { selectedRef?.account }

    /// Only the current account's timelines are shown at once.
    var visibleRefs: [TimelineRef] {
        guard let key = selectedRef?.account.accountKey else { return refs }
        return refs.filter { $0.account.accountKey == key }
    }

    init() {
        _ = AppModel.soundpacksDirectory()   // create the Files-visible folder up front
        applyCacheLimit()
        applySounds()
        accountStore.onChange = { [weak self] in self?.accountsVersion += 1 }
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.applyCacheLimit()
            self.applySounds()
            self.accountsVersion += 1
            // Force timeline rows to re-render so speech/template changes apply live.
            self.itemsByKey = self.itemsByKey
            self.restartAutoRefresh()
            self.restartStreaming()
        }
        restartAutoRefresh()
    }

    // MARK: Bootstrap & timelines

    func bootstrap() async {
        await accountStore.load()
        rebuildTimelines()
        await loadLists()
        enablePush()
    }

    // MARK: Push notifications

    /// Human-readable push status, shown in Settings for debugging.
    var pushStatus = "Not started"

    /// Ask for notification permission and register for APNs. When the token
    /// arrives, PushManager calls back into `syncPush`.
    func enablePush() {
        PushManager.shared.onTokenChanged = { [weak self] in self?.syncPush() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                if let error { self?.pushStatus = "Permission error: \(error.localizedDescription)"; return }
                guard granted else { self?.pushStatus = "Notifications not allowed"; return }
                self?.pushStatus = "Permission granted; registering with APNs…"
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        syncPush()   // in case the token is already known from a previous launch
    }

    /// Register a push subscription for every push-capable account.
    func syncPush() {
        guard let endpoint = PushManager.shared.endpoint() else {
            pushStatus = "Waiting for device token from APNs…"
            return
        }
        let pushAccounts = accountStore.accounts.filter { $0.supportsPush }
        guard !pushAccounts.isEmpty else { pushStatus = "No push-capable accounts"; return }
        pushStatus = "Got token; subscribing \(pushAccounts.count) account(s)…"
        for account in pushAccounts {
            let keys = PushManager.shared.keys(for: account.accountKey)
            Task {
                do {
                    try await account.registerPushSubscription(endpoint: endpoint, keys: keys, alerts: .default)
                    pushStatus = "Subscribed @\(account.me.acct)"
                } catch {
                    pushStatus = "Subscribe failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
    }

    func rebuildTimelines() {
        for account in accountStore.accounts {
            Task { await account.loadConfiguration() }
        }
        var newRefs = accountStore.accounts.flatMap { account in
            account.defaultTimelines.map { TimelineRef(account: account, source: $0) }
        }
        // Restore timelines opened last session (threads, user/local/federated).
        for persisted in positions.openTimelines {
            guard let account = accountStore.accounts.first(where: { $0.accountKey == persisted.accountKey }) else { continue }
            let ref = TimelineRef(account: account, source: persisted.source)
            if !newRefs.contains(ref) { newRefs.append(ref) }
        }
        refs = newRefs
        // Drop controllers/items for timelines that no longer exist.
        let keys = Set(newRefs.map(\.key))
        controllers = controllers.filter { keys.contains($0.key) }
        itemsByKey = itemsByKey.filter { keys.contains($0.key) }
        for ref in newRefs where controllers[ref.key] == nil {
            controllers[ref.key] = makeController(for: ref)
        }
        if selectedKey == nil || !keys.contains(selectedKey!) {
            if let saved = positions.selectedTimelineKey, keys.contains(saved) {
                selectedKey = saved
            } else {
                selectedKey = newRefs.first?.key
            }
        }
        Task { await cache.removeAll(except: keys) }
        positions.prune(keeping: keys)
        for ref in newRefs { startLoading(ref.key) }
        restartStreaming()
    }

    /// The remembered selected item for a timeline (position memory).
    func selectedItemID(forKey key: String) -> String? { controllers[key]?.selectedID }

    func setSelectedItemID(_ id: String?, forKey key: String) {
        controllers[key]?.noteUserSelection(id)
        positions.setPosition(id, forKey: key)
    }

    // MARK: Navigation history (undo)

    /// Pop the previous position in a timeline's navigation history.
    func undoNavigation(forKey key: String) -> String? { controllers[key]?.undoNavigation() }

    /// Set the remembered position WITHOUT recording navigation history — used
    /// when restoring focus during an undo, so it doesn't re-enter the history.
    func restoreSelectedItemID(_ id: String?, forKey key: String) {
        controllers[key]?.selectedID = id
        positions.setPosition(id, forKey: key)
    }

    /// Bumped to ask the visible timeline to step back through its navigation
    /// history (from the More menu; the VoiceOver escape gesture acts directly).
    private(set) var navBackTick = 0
    func requestNavBack() { navBackTick += 1 }

    /// Bumped to ask the visible timeline to jump to the top — fired when you tap
    /// the tab you're already on.
    private(set) var scrollTopTick = 0
    func requestScrollToTop() { scrollTopTick += 1 }

    /// Boundary feedback when there's nothing left to go back to.
    func playNavBoundary(forKey key: String) { playEarcon(.boundary, timeline: key) }

    /// Persist any pending position changes right away (e.g. on backgrounding),
    /// so a quick close doesn't lose your spot.
    func flush() { positions.flush() }

    /// Call when the app returns to the foreground. iOS suspends the streaming
    /// WebSocket in the background and it often doesn't recover on its own — which
    /// leaves the timeline frozen (old posts stay, nothing new arrives) until the
    /// app is relaunched. Reconnect the stream and refresh so we catch up, which
    /// is the useful half of a cold launch without needing one.
    func enterForeground() {
        restartStreaming()
        Task { for controller in controllers.values { await controller.refresh() } }
    }

    private func makeController(for ref: TimelineRef) -> TimelineController {
        let controller = TimelineController(cache: cache)
        controller.pageCountProvider = { [weak self] in self?.settings.settings.fetchPages ?? 1 }
        controller.setTimeline(account: ref.account, source: ref.source)
        controller.selectedID = positions.position(forKey: ref.key)
        controller.onChange = { [weak self] in self?.itemsByKey[ref.key] = controller.items }
        controller.onError = { [weak self] error in self?.report(error) }
        controller.onReceivedNewItems = { [weak self] _ in
            guard let self, !self.isMuted(ref.key), let name = ref.source.newItemsSoundName else { return }
            self.sound.play(named: name)
        }
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

    private var hasPlayedReady = false

    private func startLoading(_ key: String) {
        guard let controller = controllers[key] else { return }
        Task {
            await controller.loadCached()
            await controller.refresh()   // refresh applies the home marker at its end
            if !hasPlayedReady {
                hasPlayedReady = true
                sound.play(named: "ready")
            }
        }
    }

    func items(forKey key: String) -> [TimelineItem] { itemsByKey[key] ?? [] }

    /// Jump to the Nth timeline in the current account (1-based).
    func selectTimeline(number: Int) {
        let index = number - 1
        let visible = visibleRefs
        if visible.indices.contains(index) { selectedKey = visible[index].key }
    }

    /// Switch to a specific account and select its first timeline.
    func switchAccount(to accountKey: String) {
        if let ref = refs.first(where: { $0.account.accountKey == accountKey }) {
            selectedKey = ref.key
        }
        Task { await loadLists() }
    }

    /// Switch to the previous/next account and select its first timeline.
    func switchAccount(offset: Int) {
        let accounts = accountStore.accounts
        guard !accounts.isEmpty else { return }
        let currentKey = selectedRef?.account.accountKey
        let currentIndex = accounts.firstIndex { $0.accountKey == currentKey } ?? 0
        let target = accounts[(currentIndex + offset + accounts.count) % accounts.count]
        switchAccount(to: target.accountKey)
    }

    // MARK: Spawning / closing / mute

    func spawn(_ source: TimelineSource, for account: any SocialAccount) {
        var ref = TimelineRef(account: account, source: source)
        ref.originKey = selectedKey   // remember where we came from
        if !refs.contains(ref) {
            refs.append(ref)
            controllers[ref.key] = makeController(for: ref)
            startLoading(ref.key)
            persistOpenTimelines()
        }
        selectedKey = ref.key
    }

    /// Save the user-opened (non-default) timelines so they persist until closed.
    private func persistOpenTimelines() {
        positions.openTimelines = refs
            .filter { $0.source.isDismissable }
            .map { PersistedTimeline(accountKey: $0.account.accountKey, source: $0.source) }
    }

    func closeTimeline(key: String) {
        guard let ref = refs.first(where: { $0.key == key }), ref.source.isDismissable else {
            sound.play(.error)
            return
        }
        let wasSelected = selectedKey == key
        let origin = ref.originKey
        refs.removeAll { $0.key == key }
        controllers[key] = nil
        itemsByKey[key] = nil
        mutedKeys.remove(key)
        selectionHistory.removeAll { $0 == key }
        Task { await cache.remove(key: key) }
        positions.setPosition(nil, forKey: key)
        persistOpenTimelines()
        sound.play(.close)
        if wasSelected {
            // Return to the timeline you were on before this one (same account),
            // falling back to where it was opened from, then the account's first.
            let account = ref.account.accountKey
            let sameAccount = refs.filter { $0.account.accountKey == account }.map(\.key)
            if let previous = selectionHistory.last(where: { sameAccount.contains($0) }) {
                selectedKey = previous
            } else if let origin, sameAccount.contains(origin) {
                selectedKey = origin
            } else {
                selectedKey = sameAccount.first ?? refs.first?.key
            }
        }
    }

    func clearTimeline(key: String) {
        guard let controller = controllers[key] else { return }
        if !isMuted(key) { sound.play(.delete) }
        Task { await controller.clear() }
    }

    func isMuted(_ key: String) -> Bool { mutedKeys.contains(key) }

    func toggleMute(key: String) {
        if mutedKeys.contains(key) { mutedKeys.remove(key) } else { mutedKeys.insert(key) }
    }

    private func playEarcon(_ earcon: Earcon, timeline key: String) {
        guard !isMuted(key) else { return }
        sound.play(earcon)
    }

    // MARK: Actions (per timeline)

    func refresh(key: String) async {
        guard let controller = controllers[key] else { return }
        // Run the refresh in an independent task so a cancelled pull-to-refresh
        // gesture (SwiftUI tears down the .refreshable task when the paged TabView
        // re-renders or a stream update lands) doesn't abort the network load and
        // leave it looking like pull-to-refresh does nothing.
        await Task { await controller.refresh() }.value
    }

    func loadOlderIfNeeded(key: String, index: Int) async {
        let count = items(forKey: key).count
        if index >= count - 5 { await controllers[key]?.loadOlder() }
    }

    func loadOlder(key: String) async { await controllers[key]?.loadOlder() }
    func isLoading(key: String) -> Bool { controllers[key]?.isLoading ?? false }
    func hasMore(key: String) -> Bool { controllers[key]?.hasMore ?? false }

    func toggleFavorite(key: String, index: Int) async {
        let current = items(forKey: key)[safe: index]?.actionableStatus?.favourited ?? false
        // Play the earcon only once the action has actually gone through.
        if await controllers[key]?.toggleFavorite(at: index) == true {
            playEarcon(current ? .unfavorite : .favorite, timeline: key)
        }
    }

    func toggleBoost(key: String, index: Int) async {
        let current = items(forKey: key)[safe: index]?.actionableStatus?.boosted ?? false
        if await controllers[key]?.toggleBoost(at: index) == true, !current {
            playEarcon(.boost, timeline: key)
        }
    }

    func toggleBookmark(key: String, index: Int) async {
        let current = items(forKey: key)[safe: index]?.actionableStatus?.bookmarked ?? false
        if await controllers[key]?.toggleBookmark(at: index) == true {
            playEarcon(current ? .unbookmark : .bookmark, timeline: key)
        }
    }

    // MARK: User actions

    /// The user rows in a timeline (followers/following lists, people search).
    func users(forKey key: String) -> [User] {
        items(forKey: key).compactMap { if case .user(let u) = $0 { return u } else { return nil } }
    }

    /// Apply a follow/mute/block action to one or many users on a timeline's account.
    func performUserAction(_ action: UserAction, userIDs: [String], in ref: TimelineRef) async {
        guard !userIDs.isEmpty else { return }
        var failures = 0
        var lastError: Error?
        for id in userIDs {
            do { try await ref.account.perform(action, on: id) } catch { failures += 1; lastError = error }
        }
        if failures > 0 {
            let n = userIDs.count
            let summary = "\(action.title) failed for \(failures) of \(n) user\(n == 1 ? "" : "s")."
            sound.play(.error)
            if let lastError {
                let underlying = ErrorPresenter.present(lastError, context: action.title)
                presentedError = PresentedError(summary: summary, detail: summary + "\n\n" + underlying.detail)
            } else {
                presentedError = PresentedError(summary: summary, detail: summary)
            }
        }
    }

    @discardableResult
    func post(_ draft: PostDraft) async throws -> Status? {
        guard let key = selectedKey, let controller = controllers[key] else { return nil }
        let status = try await controller.post(draft)
        playEarcon(.postSent, timeline: key)
        return status
    }

    /// Whether the given post can be edited (own post on a platform that supports it).
    func canEdit(_ status: Status, in ref: TimelineRef) -> Bool {
        ref.account.features.editing && status.account.id == ref.account.me.id
    }

    @discardableResult
    func editPost(_ id: String, draft: PostDraft) async throws -> Status? {
        if let key = selectedKey, let controller = controllers[key] {
            let status = try await controller.editPost(id, draft: draft)
            playEarcon(.postSent, timeline: key)
            return status
        }
        return try await selectedAccount?.editPost(id, draft: draft)
    }

    // MARK: Sign-in

    func addMastodon(instance: String) async throws {
        let (credentials, me) = try await MastodonAuth.signIn(instance: instance, anchorProvider: anchor, clientName: "FastSM for iOS")
        accountStore.add(MastodonAccount(credentials: credentials, me: me))
        rebuildTimelines()
    }

    func addBluesky(handle: String, appPassword: String) async throws {
        let account = try await BlueskyAccount.signIn(identifier: handle, appPassword: appPassword)
        accountStore.add(account)
        rebuildTimelines()
    }

    // MARK: Settings passthrough

    private var streams: [StreamConnection] = []

    private func restartStreaming() {
        streams.forEach { $0.stop() }
        streams.removeAll()
        guard settings.settings.streamingEnabled else { return }
        for account in accountStore.accounts {
            let accountKey = account.accountKey
            let stream = account.openStream { [weak self] event in
                Task { @MainActor in self?.handleStream(event, accountKey: accountKey) }
            }
            if let stream { streams.append(stream) }
        }
    }

    private func handleStream(_ event: StreamEvent, accountKey: String) {
        func controller(_ source: TimelineSource) -> TimelineController? {
            controllers["\(accountKey):\(source.cacheKey)"]
        }
        switch event {
        case .update(let status):
            controller(.home)?.streamIn([.status(status)])
        case .notification(let notification):
            if notification.type == .mention, let status = notification.status {
                controller(.mentions)?.streamIn([.status(status)])
            } else {
                controller(.notifications)?.streamIn([.notification(notification)])
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
                for controller in self.controllers.values { await controller.refresh() }
            }
        }
    }

    private func applyCacheLimit() {
        let limit = settings.settings.cacheLimit
        Task { await cache.setMaxEntries(limit) }
    }
    private func applySounds() {
        sound.enabled = settings.settings.soundsEnabled
        sound.setSoundpack(directory: AppModel.soundpackDirectory(named: settings.settings.soundpack))
    }
    private func report(_ error: Error, context: String? = nil) {
        guard !error.isCancellation else { return }
        sound.play(.error)
        presentedError = ErrorPresenter.present(error, context: context)
    }

    var settingsFetchPages: Int { settings.settings.fetchPages }
    var settingsCacheLimit: Int { settings.settings.cacheLimit }
    var settingsSoundsEnabled: Bool { settings.settings.soundsEnabled }
    var settingsEmojiPrefs: EmojiPrefs { settings.settings.emojiPrefs }
    var settingsPostEmojiRemoval: EmojiRemoval { settings.settings.postEmojiRemoval }
    var settingsNameEmojiRemoval: EmojiRemoval { settings.settings.nameEmojiRemoval }
    var settingsEnterToSend: Bool { settings.settings.enterToSend }
    func updateEnterToSend(_ value: Bool) { settings.update { $0.enterToSend = value } }
    var settingsSoundpack: String { settings.settings.soundpack }
    func updateFetchPages(_ value: Int) { settings.update { $0.fetchPages = value } }
    func updateCacheLimit(_ value: Int) { settings.update { $0.cacheLimit = value } }
    func updateSounds(_ value: Bool) { settings.update { $0.soundsEnabled = value } }
    func updatePostEmojiRemoval(_ value: EmojiRemoval) { settings.update { $0.postEmojiRemoval = value } }
    func updateNameEmojiRemoval(_ value: EmojiRemoval) { settings.update { $0.nameEmojiRemoval = value } }
    var settingsMaxUsernamesInPost: Int { settings.settings.maxUsernamesInPost }
    func updateMaxUsernamesInPost(_ value: Int) { settings.update { $0.maxUsernamesInPost = value } }
    func updateSoundpack(_ value: String) { settings.update { $0.soundpack = value } }
    var speechSettings: SpeechSettings { settings.settings.speech }
    func updateSpeech(_ value: SpeechSettings) { settings.update { $0.speech = value } }
    var movementSettings: MovementSettings { settings.settings.movement }
    func updateMovement(_ value: MovementSettings) { settings.update { $0.movement = value } }
    var settingsAutoRefresh: Int { settings.settings.autoRefreshSeconds }
    func updateAutoRefresh(_ value: Int) { settings.update { $0.autoRefreshSeconds = value } }
    var settingsSyncHomePosition: Bool { settings.settings.syncHomePosition }
    func updateSyncHomePosition(_ value: Bool) { settings.update { $0.syncHomePosition = value } }
    var settingsStreaming: Bool { settings.settings.streamingEnabled }
    func updateStreaming(_ value: Bool) { settings.update { $0.streamingEnabled = value } }
    var settingsRecordEveryNavStep: Bool { settings.settings.recordEveryNavStep }
    func updateRecordEveryNavStep(_ value: Bool) { settings.update { $0.recordEveryNavStep = value } }

    // MARK: Links & media

    var linkChoices: [PostLink]?
    var mediaChoices: [MediaAttachment]?
    var mediaToPlay: PlayableMedia?
    var mediaToView: MediaGallery?

    var availableLists: [TimelineList] = []
    var availableFeeds: [TimelineList] = []

    func loadLists() async {
        guard let account = selectedAccount else { availableLists = []; availableFeeds = []; return }
        availableLists = (try? await account.lists()) ?? []
        availableFeeds = (try? await account.savedFeeds()) ?? []
    }

    /// Reply to / quote a post, resolving remote-instance posts to the local copy.
    func compose(replyTo: Status? = nil, quoting: Status? = nil) {
        let target = replyTo ?? quoting
        guard let account = selectedAccount, let target, target.instanceURL != nil else {
            composeRequest = ComposeRequest(replyTo: replyTo, quoting: quoting)
            return
        }
        Task {
            let resolved = (try? await account.resolve(target)) ?? target
            composeRequest = ComposeRequest(replyTo: replyTo != nil ? resolved : nil,
                                            quoting: quoting != nil ? resolved : nil)
        }
    }

    func openRemoteUserTimeline(handle rawHandle: String) {
        guard let account = selectedAccount else { return }
        var handle = rawHandle.trimmingCharacters(in: .whitespaces)
        if handle.hasPrefix("@") { handle.removeFirst() }
        guard let at = handle.lastIndex(of: "@") else { return }
        let username = String(handle[handle.startIndex..<at])
        let instance = String(handle[handle.index(after: at)...])
        guard !username.isEmpty, !instance.isEmpty else { return }
        spawn(.remoteUser(instance: instance, username: username, title: "@\(handle)"), for: account)
    }

    func openUserTimeline(handle: String) {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let account = selectedAccount else { return }
        Task {
            do {
                let user = try await account.resolveUser(handle: trimmed)
                spawn(.userPosts(userID: user.id, title: "@\(user.acct)"), for: account)
            } catch {
                report(error)
            }
        }
    }

    // Whether a post has openable links / viewable media. Memoized by post id:
    // PostLinks.links runs an HTML regex, and these are queried while building each
    // row's context menu AND its VoiceOver actions — so without caching the parse
    // re-runs for every row on every VoiceOver scroll, which lags badly.
    @ObservationIgnored private var linkMediaFlags: [String: (links: Bool, media: Bool)] = [:]

    private func linkMedia(_ status: Status) -> (links: Bool, media: Bool) {
        let key = status.displayStatus.id
        if let hit = linkMediaFlags[key] { return hit }
        let flags = (links: !PostLinks.links(for: status).isEmpty,
                     media: !PostLinks.viewableMedia(for: status).isEmpty)
        if linkMediaFlags.count > 2000 { linkMediaFlags.removeAll() }   // simple bound
        linkMediaFlags[key] = flags
        return flags
    }

    func canOpenLinks(_ status: Status) -> Bool { linkMedia(status).links }
    func canViewMedia(_ status: Status) -> Bool { linkMedia(status).media }

    func openLinks(for status: Status) {
        let links = PostLinks.links(for: status)
        if links.isEmpty { sound.play(.error); return }
        linkChoices = links
    }

    func playMedia(for status: Status) {
        let media = PostLinks.viewableMedia(for: status)
        guard !media.isEmpty else { sound.play(.error); return }
        if media.count == 1 { presentMedia(media[0], among: media); return }
        mediaChoices = media
    }

    /// Route a chosen attachment: images open the image viewer (paging all the
    /// post's images), video/audio open the player.
    func presentMedia(_ item: MediaAttachment, among media: [MediaAttachment]) {
        if item.type == .image {
            let images = media.filter { $0.type == .image }
            let start = images.firstIndex(where: { $0.id == item.id }) ?? 0
            mediaToView = MediaGallery(images: images, startIndex: start)
        } else if let url = item.url {
            mediaToPlay = PlayableMedia(url: url)
        }
    }

    static func soundpacksDirectory() -> URL? {
        let fm = FileManager.default
        // Documents so it shows up in Files (the "FastSM" folder under On My
        // iPhone) — UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace make
        // it user-accessible to drop soundpack folders into.
        guard let base = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let dir = base.appendingPathComponent("Soundpacks", isDirectory: true)
        let isNew = !fm.fileExists(atPath: dir.path)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if isNew {
            let readme = dir.appendingPathComponent("Read Me.txt")
            let text = "Put soundpack folders here.\n\nEach soundpack is a folder of sound files (e.g. home.ogg, mention.ogg, like.ogg). After adding one, pick it in FastSM → Settings → Audio → Soundpack.\n"
            try? text.data(using: .utf8)?.write(to: readme)
        }
        return dir
    }

    static func soundpackDirectory(named name: String) -> URL? {
        guard name != AppSettings.defaultSoundpackName, let base = soundpacksDirectory() else { return nil }
        return base.appendingPathComponent(name, isDirectory: true)
    }

    static func availableSoundpacks() -> [String] {
        var names = [AppSettings.defaultSoundpackName]
        if let base = soundpacksDirectory(),
           let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
            names.append(contentsOf: entries
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { $0.lastPathComponent }
                .sorted())
        }
        return names
    }
}

/// A request to open the compose sheet.
struct ComposeRequest: Identifiable {
    let id = UUID()
    var replyTo: Status?
    var quoting: Status?
    var editing: Status?
}

struct PlayableMedia: Identifiable {
    let id = UUID()
    let url: URL
}

/// A set of images to show in the image viewer, starting at a given one.
struct MediaGallery: Identifiable {
    let id = UUID()
    let images: [MediaAttachment]
    let startIndex: Int
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Supplies the key window as the OAuth presentation anchor on iOS.
@MainActor
final class AnchorProvider: NSObject, PresentationAnchorProviding {
    func presentationAnchor() -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
