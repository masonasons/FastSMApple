//
//  TimelineView.swift
//  FastSM (iOS)
//
//  The paged timeline UI: a swipeable page per timeline (works for touch and
//  VoiceOver page-swipes) plus a custom bottom tab bar. Each timeline tab has
//  VoiceOver actions (mute/unmute, remove); each post has a context menu and
//  matching VoiceOver actions.
//

import SwiftUI
import AVKit
import FastSMCore

struct TimelinePagerView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false
    @State private var showingAddAccount = false
    @State private var activePrompt: PromptKind?
    @State private var promptText = ""

    /// A text-entry prompt for opening a parameterized timeline.
    private enum PromptKind: String, Identifiable {
        case user, hashtag, searchPosts, searchPeople, remoteInstance, remoteUser
        var id: String { rawValue }
        var title: String {
            switch self {
            case .user: return "User Timeline"
            case .hashtag: return "Hashtag"
            case .searchPosts: return "Search Posts"
            case .searchPeople: return "Search People"
            case .remoteInstance: return "Remote Instance Timeline"
            case .remoteUser: return "Remote User Timeline"
            }
        }
        var placeholder: String {
            switch self {
            case .user, .remoteUser: return "user@instance.tld"
            case .hashtag: return "swift"
            case .searchPosts: return "search terms"
            case .searchPeople: return "name or handle"
            case .remoteInstance: return "mastodon.social"
            }
        }
        var message: String {
            switch self {
            case .user: return "Open a user's timeline."
            case .hashtag: return "Enter a hashtag (without the #)."
            case .searchPosts: return "Search posts."
            case .searchPeople: return "Find people."
            case .remoteInstance: return "Open another instance's local timeline."
            case .remoteUser: return "A user's timeline fetched from their instance."
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: Binding(
                    get: { model.selectedKey ?? model.visibleRefs.first?.key ?? "" },
                    set: { model.selectedKey = $0 }
                )) {
                    ForEach(model.visibleRefs) { ref in
                        TimelinePageView(ref: ref).tag(ref.key)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                TimelineTabBar()
            }
            .background { globalShortcuts }
            // VoiceOver magic tap (two-finger double-tap) opens compose.
            .accessibilityAction(.magicTap) { model.composeRequest = ComposeRequest() }
            .navigationTitle(model.selectedRef?.shortTitle ?? "FastSM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { moreMenu } label: { Label("More", systemImage: "ellipsis.circle") }
                        .accessibilityActions { accountSwitchActions }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.composeRequest = ComposeRequest() } label: { Label("New Post", systemImage: "square.and.pencil") }
                }
            }
            .sheet(item: $model.composeRequest) { request in
                ComposeView(replyTo: request.replyTo, quoting: request.quoting, editing: request.editing)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingAddAccount) { AddAccountView() }
            .alert(activePrompt?.title ?? "", isPresented: promptPresented) {
                TextField(activePrompt?.placeholder ?? "", text: $promptText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Open") {
                    if let prompt = activePrompt { runPrompt(prompt, promptText) }
                    promptText = ""; activePrompt = nil
                }
                Button("Cancel", role: .cancel) { promptText = ""; activePrompt = nil }
            } message: {
                Text(activePrompt?.message ?? "")
            }
            .sheet(item: $model.mediaToPlay) { media in
                MediaPlayerSheet(url: media.url)
            }
            .confirmationDialog("Open Link", isPresented: linksPresented, titleVisibility: .visible) {
                ForEach(model.linkChoices ?? []) { link in
                    Button(link.title) { openURL(link.url); model.linkChoices = nil }
                }
                Button("Cancel", role: .cancel) { model.linkChoices = nil }
            }
            .confirmationDialog("Play Media", isPresented: mediaPresented, titleVisibility: .visible) {
                ForEach(model.mediaChoices ?? []) { item in
                    Button(item.title) { model.mediaToPlay = PlayableMedia(url: item.url); model.mediaChoices = nil }
                }
                Button("Cancel", role: .cancel) { model.mediaChoices = nil }
            }
            .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    /// VoiceOver actions on the More button to jump between accounts.
    @ViewBuilder private var accountSwitchActions: some View {
        let accounts = model.accountStore.accounts
        if accounts.count > 1 {
            ForEach(accounts, id: \.accountKey) { account in
                Button("Switch to @\(account.me.acct)") { model.switchAccount(to: account.accountKey) }
            }
        }
    }

    @ViewBuilder private var moreMenu: some View {
        Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        Button { showingAddAccount = true } label: { Label("Accounts", systemImage: "person.crop.circle") }
        let accounts = model.accountStore.accounts
        if accounts.count > 1 {
            Menu {
                ForEach(accounts, id: \.accountKey) { account in
                    Button("@\(account.me.acct)") { model.switchAccount(to: account.accountKey) }
                }
            } label: {
                Label("Switch Account", systemImage: "person.2")
            }
        }
        Divider()
        Menu { newTimelineMenu } label: { Label("New Timeline", systemImage: "rectangle.stack.badge.plus") }
        if let key = model.selectedKey {
            Divider()
            Button { Task { await model.refresh(key: key) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button { model.toggleMute(key: key) } label: {
                Label(model.isMuted(key) ? "Unmute" : "Mute", systemImage: model.isMuted(key) ? "speaker.wave.2" : "speaker.slash")
            }
            Button { model.clearTimeline(key: key) } label: { Label("Clear Items", systemImage: "trash") }
            if model.selectedRef?.source.isDismissable == true {
                Button(role: .destructive) { model.closeTimeline(key: key) } label: { Label("Close Tab", systemImage: "xmark.circle") }
            }
        }
    }

    @ViewBuilder private var newTimelineMenu: some View {
        if let account = model.selectedAccount {
            if account.platform == .mastodon {
                Button("Local Timeline") { model.spawn(.local, for: account) }
                Button("Federated Timeline") { model.spawn(.federated, for: account) }
            }
            Button("User Timeline…") { activePrompt = .user }
            Button("Hashtag…") { activePrompt = .hashtag }
            Button("Search Posts…") { activePrompt = .searchPosts }
            Button("Search People…") { activePrompt = .searchPeople }
            Button("Favorites") { model.spawn(.favorites, for: account) }
            if account.platform == .mastodon {
                Button("Bookmarks") { model.spawn(.bookmarks, for: account) }
                Button("Trending") { model.spawn(.trending, for: account) }
                if !model.availableLists.isEmpty {
                    Menu("Lists") {
                        ForEach(model.availableLists) { list in
                            Button(list.title) { model.spawn(.list(id: list.id, title: list.title), for: account) }
                        }
                    }
                }
                Button("Remote Instance…") { activePrompt = .remoteInstance }
                Button("Remote User…") { activePrompt = .remoteUser }
            }
            if !model.availableFeeds.isEmpty {
                Menu("Feeds") {
                    ForEach(model.availableFeeds) { feed in
                        Button(feed.title) { model.spawn(.feed(uri: feed.id, title: feed.title), for: account) }
                    }
                }
            }
        }
    }

    @Environment(\.openURL) private var openURL

    private var promptPresented: Binding<Bool> {
        Binding(get: { activePrompt != nil }, set: { if !$0 { activePrompt = nil } })
    }

    private func runPrompt(_ kind: PromptKind, _ text: String) {
        guard let account = model.selectedAccount else { return }
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        switch kind {
        case .user: model.openUserTimeline(handle: value)
        case .hashtag:
            let tag = value.hasPrefix("#") ? String(value.dropFirst()) : value
            model.spawn(.hashtag(tag: tag), for: account)
        case .searchPosts: model.spawn(.search(query: value, kind: .posts), for: account)
        case .searchPeople: model.spawn(.search(query: value, kind: .users), for: account)
        case .remoteInstance: model.spawn(.remoteLocal(instance: value), for: account)
        case .remoteUser: model.openRemoteUserTimeline(handle: value)
        }
    }

    private var linksPresented: Binding<Bool> {
        Binding(get: { model.linkChoices != nil }, set: { if !$0 { model.linkChoices = nil } })
    }
    private var mediaPresented: Binding<Bool> {
        Binding(get: { model.mediaChoices != nil }, set: { if !$0 { model.mediaChoices = nil } })
    }

    // Hardware-keyboard shortcuts: ⌘1…⌘9 jump to a timeline, ⌘[ / ⌘] switch account.
    private var globalShortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("") { model.selectTimeline(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("") { model.switchAccount(offset: -1) }.keyboardShortcut("[", modifiers: .command)
            Button("") { model.switchAccount(offset: 1) }.keyboardShortcut("]", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct TimelinePageView: View {
    @Environment(AppModel.self) private var model
    let ref: TimelineRef

    /// Restore the saved position only once per appearance — otherwise every
    /// background refresh / marker sync would yank the reader back, since
    /// VoiceOver swiping doesn't update the list's selection.
    @State private var hasRestoredScroll = false

    /// The row VoiceOver is currently reading. SwiftUI's list `selection` only
    /// changes on tap, so this is how we learn the reader has moved (and update
    /// the saved/synced position to match).
    @AccessibilityFocusState private var focusedID: String?

    private var items: [TimelineItem] { model.items(forKey: ref.key) }

    // Backed by the model so the position persists across page revisits/restarts.
    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedItemID(forKey: ref.key) },
            set: { model.setSelectedItemID($0, forKey: ref.key) }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TimelineItemRow(item: item, demojify: model.settingsDemojify)
                        .tag(item.id)
                        .accessibilityFocused($focusedID, equals: item.id)
                        .contextMenu { PostActions(item: item, ref: ref, index: index) }
                        .accessibilityActions { PostActions(item: item, ref: ref, index: index, reversed: true) }
                        .task { await model.loadOlderIfNeeded(key: ref.key, index: index) }
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh(key: ref.key) }
            .overlay { if items.isEmpty { ContentUnavailableView("No Posts", systemImage: "tray") } }
            .background { postShortcuts }
            // Restore the saved/synced position ONCE, when items first load —
            // never on later refreshes, so it doesn't fight the reader.
            .onChange(of: items.count) { _, _ in restoreScrollOnce(proxy) }
            .onAppear { restoreScrollOnce(proxy) }
            .onDisappear { hasRestoredScroll = false }
            // Track the row VoiceOver is reading as the saved/synced position.
            .onChange(of: focusedID) { _, id in
                if let id { model.setSelectedItemID(id, forKey: ref.key) }
            }
        }
    }

    private func restoreScrollOnce(_ proxy: ScrollViewProxy) {
        guard !hasRestoredScroll,
              let id = model.selectedItemID(forKey: ref.key),
              items.contains(where: { $0.id == id }) else { return }
        hasRestoredScroll = true
        proxy.scrollTo(id, anchor: .center)
    }

    // Hardware-keyboard post shortcuts matching the Mac app, acting on the
    // selected row: R reply, B boost, Q quote, F favorite.
    private var postShortcuts: some View {
        ZStack {
            Button("") { performShortcut("r") }.keyboardShortcut("r", modifiers: [])
            Button("") { performShortcut("b") }.keyboardShortcut("b", modifiers: [])
            Button("") { performShortcut("q") }.keyboardShortcut("q", modifiers: [])
            Button("") { performShortcut("f") }.keyboardShortcut("f", modifiers: [])
            Button("") { performShortcut("e") }.keyboardShortcut("e", modifiers: [])
            Button("") { withSelectedStatus { model.openLinks(for: $0) } }.keyboardShortcut(.return, modifiers: .command)
            Button("") { withSelectedStatus { model.playMedia(for: $0) } }.keyboardShortcut(.return, modifiers: .shift)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func withSelectedStatus(_ action: (Status) -> Void) {
        guard let id = model.selectedItemID(forKey: ref.key),
              let status = items.first(where: { $0.id == id })?.actionableStatus else { return }
        action(status)
    }

    private func performShortcut(_ key: Character) {
        guard let selectedID = model.selectedItemID(forKey: ref.key),
              let index = items.firstIndex(where: { $0.id == selectedID }),
              let status = items[index].actionableStatus else { return }
        switch key {
        case "r": model.compose(replyTo: status)
        case "q": model.compose(quoting: status)
        case "b": Task { await model.toggleBoost(key: ref.key, index: index) }
        case "f": Task { await model.toggleFavorite(key: ref.key, index: index) }
        case "e": if model.canEdit(status, in: ref) { model.composeRequest = ComposeRequest(editing: status) }
        default: break
        }
    }
}

/// A simple full-screen-ish player for a post's video/audio.
struct MediaPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Media")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .onAppear {
                    let avPlayer = AVPlayer(url: url)
                    player = avPlayer
                    avPlayer.play()
                }
                .onDisappear { player?.pause() }
        }
    }
}

struct TimelineTabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.visibleRefs) { ref in
                    let selected = model.selectedKey == ref.key
                    Button {
                        model.selectedKey = ref.key
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: ref.symbol)
                            Text(ref.shortTitle).font(.caption2)
                        }
                        .frame(minWidth: 64)
                        .padding(.vertical, 6)
                    }
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityLabel((model.hasMultipleAccounts ? ref.fullTitle : ref.shortTitle) + (model.isMuted(ref.key) ? ", muted" : ""))
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    .contextMenu { tabActions(ref) }
                    .accessibilityActions { tabActions(ref) }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 54)
        .background(.bar)
    }

    @ViewBuilder
    private func tabActions(_ ref: TimelineRef) -> some View {
        Button(model.isMuted(ref.key) ? "Unmute" : "Mute") { model.toggleMute(key: ref.key) }
        Button("Clear Items") { model.clearTimeline(key: ref.key) }
        if ref.source.isDismissable {
            Button("Remove", role: .destructive) { model.closeTimeline(key: ref.key) }
        }
    }
}

/// The actions available on a post (or user) — used for both the long-press
/// context menu and VoiceOver custom actions. VoiceOver lists custom actions in
/// reverse declaration order, so pass `reversed: true` for the accessibility
/// variant to keep the spoken order matching the menu.
struct PostActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let item: TimelineItem
    let ref: TimelineRef
    let index: Int
    var reversed: Bool = false

    private struct Action: Identifiable {
        let id = UUID()
        let title: String
        let perform: () -> Void
    }

    private var actions: [Action] {
        var list: [Action] = []
        switch item {
        case .user(let user):
            list.append(Action(title: "View Posts") { model.spawn(.userPosts(userID: user.id, title: "@\(user.acct)"), for: ref.account) })
            list.append(Action(title: "Followers") { model.spawn(.followers(userID: user.id, title: "Followers: @\(user.acct)"), for: ref.account) })
            list.append(Action(title: "Following") { model.spawn(.following(userID: user.id, title: "Following: @\(user.acct)"), for: ref.account) })
            if let url = user.url { list.append(Action(title: "Open in Browser") { openURL(url) }) }
        default:
            if let status = item.actionableStatus {
                list.append(Action(title: "Reply") { model.compose(replyTo: status) })
                list.append(Action(title: status.boosted ? "Unboost" : "Boost") { Task { await model.toggleBoost(key: ref.key, index: index) } })
                list.append(Action(title: status.favourited ? "Unfavorite" : "Favorite") { Task { await model.toggleFavorite(key: ref.key, index: index) } })
                list.append(Action(title: "Quote") { model.compose(quoting: status) })
                if model.canEdit(status, in: ref) {
                    list.append(Action(title: "Edit") { model.composeRequest = ComposeRequest(editing: status) })
                }
                if model.canOpenLinks(status) {
                    list.append(Action(title: "Open Link") { model.openLinks(for: status) })
                }
                if model.canPlayMedia(status) {
                    list.append(Action(title: "Play Media") { model.playMedia(for: status) })
                }
                list.append(Action(title: "View Thread") { model.spawn(.thread(statusID: status.id, title: "Thread: \(status.account.bestName)"), for: ref.account) })
                list.append(Action(title: "View Author") { model.spawn(.userPosts(userID: status.account.id, title: "@\(status.account.acct)"), for: ref.account) })
                if let url = status.url { list.append(Action(title: "Open in Browser") { openURL(url) }) }
            }
        }
        return reversed ? list.reversed() : list
    }

    var body: some View {
        ForEach(actions) { action in
            Button(action.title, action: action.perform)
        }
    }
}
