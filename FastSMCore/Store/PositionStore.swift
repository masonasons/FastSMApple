//
//  PositionStore.swift
//  FastSMCore
//
//  Remembers, per timeline, which item was selected — by item ID, not index, so
//  it restores to the right post even if new items arrived (FastSM-style
//  position restore). Persisted to Application Support/FastSM/positions.json.
//

import Foundation

/// A user-opened timeline to restore on launch (beyond the default feeds).
public struct PersistedTimeline: Codable, Sendable, Equatable {
    public var accountKey: String
    public var source: TimelineSource
    public init(accountKey: String, source: TimelineSource) {
        self.accountKey = accountKey
        self.source = source
    }
}

private struct StoredPositions: Codable {
    var positions: [String: String] = [:]   // timeline key -> selected item id
    var selectedTimelineKey: String?
    var openTimelines: [PersistedTimeline] = []
}

@MainActor
public final class PositionStore {
    private var data: StoredPositions
    private let url: URL
    private var saveTask: Task<Void, Never>?

    public init(appName: String = "FastSM", fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("positions.json")

        if let loaded = try? JSONDecoder().decode(StoredPositions.self, from: Data(contentsOf: self.url)) {
            self.data = loaded
        } else {
            self.data = StoredPositions()
        }
    }

    public func position(forKey key: String) -> String? { data.positions[key] }

    public func setPosition(_ id: String?, forKey key: String) {
        if data.positions[key] == id { return }
        data.positions[key] = id
        scheduleSave()
    }

    public var selectedTimelineKey: String? {
        get { data.selectedTimelineKey }
        set {
            guard data.selectedTimelineKey != newValue else { return }
            data.selectedTimelineKey = newValue
            scheduleSave()
        }
    }

    /// Timelines the user opened (beyond defaults), restored on launch.
    public var openTimelines: [PersistedTimeline] {
        get { data.openTimelines }
        set {
            guard data.openTimelines != newValue else { return }
            data.openTimelines = newValue
            scheduleSave()
        }
    }

    /// Drop positions for timelines that no longer exist.
    public func prune(keeping keys: Set<String>) {
        let filtered = data.positions.filter { keys.contains($0.key) }
        guard filtered.count != data.positions.count else { return }
        data.positions = filtered
        scheduleSave()
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.save()
            self?.saveTask = nil
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }
}
