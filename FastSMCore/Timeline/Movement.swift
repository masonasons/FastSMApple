//
//  Movement.swift
//  FastSMCore
//
//  "Movement units" let the reader jump through a timeline by a chosen
//  granularity — a time gap (1 hour, 2 hours, …, 1 day), the same author, or
//  the same conversation. On macOS, Option+Left/Right picks the unit and
//  Option+Up/Down jumps by it; on iOS each enabled unit is a VoiceOver rotor.
//  Which units appear, and in what order, is configured in Settings → Movement.
//

import Foundation

/// One navigation granularity. Time units carry a gap in seconds.
public struct MovementUnit: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable { case time, sameUser, thread }
    public let kind: Kind
    public let seconds: Int

    public init(kind: Kind, seconds: Int = 0) {
        self.kind = kind
        self.seconds = seconds
    }

    public static func time(_ seconds: Int) -> MovementUnit { .init(kind: .time, seconds: seconds) }
    public static let sameUser = MovementUnit(kind: .sameUser)
    public static let thread = MovementUnit(kind: .thread)

    public var id: String { kind == .time ? "time:\(seconds)" : kind.rawValue }

    public var title: String {
        switch kind {
        case .sameUser: return "Same User"
        case .thread: return "Thread"
        case .time:
            if seconds % 86_400 == 0 {
                let d = seconds / 86_400
                return "\(d) day\(d == 1 ? "" : "s")"
            }
            let h = seconds / 3_600
            return "\(h) hour\(h == 1 ? "" : "s")"
        }
    }

    /// Every unit the UI knows about, in default order.
    public static let catalog: [MovementUnit] = [
        time(3_600), time(7_200), time(14_400), time(21_600), time(43_200), time(86_400),
        sameUser, thread,
    ]
}

/// An orderable, toggleable movement unit (Settings → Movement).
public struct MovementItem: Codable, Sendable, Hashable, Identifiable {
    public var unit: MovementUnit
    public var enabled: Bool
    public var id: String { unit.id }
    public init(_ unit: MovementUnit, _ enabled: Bool = true) {
        self.unit = unit
        self.enabled = enabled
    }
}

public struct MovementSettings: Codable, Sendable, Equatable {
    public var items: [MovementItem]
    public init(items: [MovementItem]) { self.items = items }

    public static let `default` = MovementSettings(items: MovementUnit.catalog.map { MovementItem($0) })

    /// Enabled units, in user order — what the navigation actually offers.
    public var enabledUnits: [MovementUnit] { items.filter(\.enabled).map(\.unit) }

    /// Keep saved order, drop unknown/dupes, append any newly-added catalog units.
    public func normalized() -> MovementSettings {
        var result: [MovementItem] = []
        var seen = Set<String>()
        for item in items where MovementUnit.catalog.contains(where: { $0.id == item.id }) && !seen.contains(item.id) {
            result.append(item); seen.insert(item.id)
        }
        for unit in MovementUnit.catalog where !seen.contains(unit.id) {
            result.append(MovementItem(unit)); seen.insert(unit.id)
        }
        return MovementSettings(items: result)
    }
}

/// The current movement configuration, set by SettingsStore on load/change.
public enum MovementConfig {
    public static var current: MovementSettings = .default
}

/// Direction of travel. `.down` heads toward higher indices (older posts in a
/// newest-first feed); `.up` toward lower indices (newer).
public enum MoveDirection: Sendable { case down, up }

public enum Movement {
    /// The index to jump to from `index` by one `unit` step in `direction`, or
    /// nil if there's nowhere to go.
    public static func destination(in items: [TimelineItem], from index: Int,
                                   unit: MovementUnit, direction: MoveDirection) -> Int? {
        guard items.indices.contains(index) else { return nil }
        let step = direction == .down ? 1 : -1

        switch unit.kind {
        case .time:
            guard let base = items[index].actionableStatus?.createdAt else { return nil }
            let threshold = TimeInterval(unit.seconds)
            var i = index + step
            while items.indices.contains(i) {
                if let t = items[i].actionableStatus?.createdAt {
                    let diff = direction == .down ? base.timeIntervalSince(t) : t.timeIntervalSince(base)
                    if diff >= threshold { return i }
                }
                i += step
            }
            return nil

        case .sameUser:
            guard let uid = items[index].actionableStatus?.account.id else { return nil }
            var i = index + step
            while items.indices.contains(i) {
                if items[i].actionableStatus?.account.id == uid { return i }
                i += step
            }
            return nil

        case .thread:
            let keys = threadKeys(items)
            guard let key = keys[index] else { return nil }
            var i = index + step
            while items.indices.contains(i) {
                if keys[i] == key { return i }
                i += step
            }
            return nil
        }
    }

    /// Representative stop indices for a unit, top-to-bottom — used to populate a
    /// VoiceOver rotor on iOS.
    public static func rotorStops(in items: [TimelineItem], unit: MovementUnit) -> [Int] {
        switch unit.kind {
        case .time:
            let threshold = TimeInterval(unit.seconds)
            var stops: [Int] = []
            var lastTime: Date?
            for (i, item) in items.enumerated() {
                guard let t = item.actionableStatus?.createdAt else { continue }
                if let last = lastTime {
                    if last.timeIntervalSince(t) >= threshold { stops.append(i); lastTime = t }
                } else {
                    stops.append(i); lastTime = t
                }
            }
            return stops

        case .sameUser:
            // The first post of each consecutive same-author run.
            var stops: [Int] = []
            var lastAuthor: String?
            for (i, item) in items.enumerated() {
                guard let a = item.actionableStatus?.account.id else { continue }
                if a != lastAuthor { stops.append(i); lastAuthor = a }
            }
            return stops

        case .thread:
            let keys = threadKeys(items)
            var stops: [Int] = []
            var seen = Set<String>()
            for (i, key) in keys.enumerated() {
                if let key, !seen.contains(key) { stops.append(i); seen.insert(key) }
            }
            return stops
        }
    }

    /// Root-ancestor id per index (nil for non-status rows). Follows inReplyToID
    /// among the loaded items so posts of one conversation share a key.
    static func threadKeys(_ items: [TimelineItem]) -> [String?] {
        var parent: [String: String?] = [:]
        for item in items {
            if let s = item.actionableStatus { parent[s.id] = s.inReplyToID }
        }
        func root(_ id: String) -> String {
            var current = id
            var hops = 0
            while hops < 1_000 {
                guard let p = parent[current], let up = p, parent[up] != nil else { break }
                current = up; hops += 1
            }
            return current
        }
        return items.map { $0.actionableStatus.map { root($0.id) } }
    }
}
