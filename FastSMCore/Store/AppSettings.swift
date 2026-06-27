//
//  AppSettings.swift
//  FastSMCore
//
//  User preferences, persisted to `Application Support/FastSM/settings.json` —
//  kept separate from the account config so the two never clobber each other.
//

import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    /// When true, plain Return sends a post and ⌘Return inserts a newline.
    /// When false (default), ⌘Return sends and Return inserts a newline.
    public var enterToSend: Bool

    /// How many pages to fetch when loading/refreshing a timeline (each page is
    /// ~40 posts). Higher = more history on launch, more network on refresh.
    public var fetchPages: Int

    /// Maximum number of items kept in each timeline's on-disk cache.
    public var cacheLimit: Int

    // Confirmations (OG FastSM "Confirmation" group).
    public var confirmBoost: Bool
    public var confirmFavorite: Bool
    public var confirmClearTimeline: Bool

    /// Play earcons for navigation/actions.
    public var soundsEnabled: Bool
    /// Selected soundpack name. "Default" = the built-in pack.
    public var soundpack: String
    /// Strip emoji from displayed post text.
    public var demojify: Bool

    /// What VoiceOver reads for posts and users (order + on/off).
    public var speech: SpeechSettings

    /// Seconds between automatic timeline refreshes (0 = off).
    public var autoRefreshSeconds: Int

    /// Sync the home timeline read position with the server (Mastodon markers).
    public var syncHomePosition: Bool

    /// Stream timelines in real time (Mastodon).
    public var streamingEnabled: Bool

    /// Selectable auto-refresh intervals (seconds); 0 = off.
    public static let autoRefreshOptions = [0, 30, 60, 120, 300]

    public static let defaultSoundpackName = "Default"

    public static let fetchPagesRange = 1...10
    public static let cacheLimitRange = 100...20000

    public init(
        enterToSend: Bool = false,
        fetchPages: Int = 3,
        cacheLimit: Int = 200,
        confirmBoost: Bool = false,
        confirmFavorite: Bool = false,
        confirmClearTimeline: Bool = true,
        soundsEnabled: Bool = true,
        soundpack: String = AppSettings.defaultSoundpackName,
        demojify: Bool = false,
        speech: SpeechSettings = .default,
        autoRefreshSeconds: Int = 0,
        syncHomePosition: Bool = false,
        streamingEnabled: Bool = false
    ) {
        self.enterToSend = enterToSend
        self.fetchPages = fetchPages
        self.cacheLimit = cacheLimit
        self.confirmBoost = confirmBoost
        self.confirmFavorite = confirmFavorite
        self.confirmClearTimeline = confirmClearTimeline
        self.soundsEnabled = soundsEnabled
        self.soundpack = soundpack
        self.demojify = demojify
        self.speech = speech
        self.autoRefreshSeconds = autoRefreshSeconds
        self.syncHomePosition = syncHomePosition
        self.streamingEnabled = streamingEnabled
    }

    // Tolerant decoding so older/newer settings files (missing keys) still load
    // with sensible defaults instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enterToSend = try container.decodeIfPresent(Bool.self, forKey: .enterToSend) ?? false
        let pages = try container.decodeIfPresent(Int.self, forKey: .fetchPages) ?? 3
        fetchPages = pages.clamped(to: AppSettings.fetchPagesRange)
        let limit = try container.decodeIfPresent(Int.self, forKey: .cacheLimit) ?? 200
        cacheLimit = limit.clamped(to: AppSettings.cacheLimitRange)
        confirmBoost = try container.decodeIfPresent(Bool.self, forKey: .confirmBoost) ?? false
        confirmFavorite = try container.decodeIfPresent(Bool.self, forKey: .confirmFavorite) ?? false
        confirmClearTimeline = try container.decodeIfPresent(Bool.self, forKey: .confirmClearTimeline) ?? true
        soundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        soundpack = try container.decodeIfPresent(String.self, forKey: .soundpack) ?? AppSettings.defaultSoundpackName
        demojify = try container.decodeIfPresent(Bool.self, forKey: .demojify) ?? false
        speech = (try container.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? .default).normalized()
        autoRefreshSeconds = try container.decodeIfPresent(Int.self, forKey: .autoRefreshSeconds) ?? 0
        syncHomePosition = try container.decodeIfPresent(Bool.self, forKey: .syncHomePosition) ?? false
        streamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? false
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

@MainActor
public final class SettingsStore {
    public private(set) var settings: AppSettings

    /// Fired after settings change so observers can react.
    public var onChange: (() -> Void)?

    private let url: URL

    public init(appName: String = "FastSM", fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = AppSettings()
        }
        SpeechConfig.current = settings.speech
    }

    /// Mutate, persist, and notify in one call.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        SpeechConfig.current = settings.speech
        save()
        onChange?()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
