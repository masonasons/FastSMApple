//
//  Platform.swift
//  FastSMCore
//
//  Identifies which social network a model came from. Mirrors the
//  `_platform` string used throughout FastSM's universal models.
//

import Foundation

/// The social networks FastSM speaks to.
public enum Platform: String, Codable, Sendable, CaseIterable {
    case mastodon
    case bluesky

    /// Human-facing name for menus and labels.
    public var displayName: String {
        switch self {
        case .mastodon: return "Mastodon"
        case .bluesky: return "Bluesky"
        }
    }
}
