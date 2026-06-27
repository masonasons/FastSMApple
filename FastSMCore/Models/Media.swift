//
//  Media.swift
//  FastSMCore
//
//  Ports of FastSM's `UniversalMedia` and `UniversalMention` (models/status.py).
//

import Foundation

/// A media attachment on a status.
public struct MediaAttachment: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case image, video, audio, gifv, unknown
    }

    public let id: String
    public var type: Kind
    public var url: URL?
    public var previewURL: URL?
    /// Alt text / description, used heavily for accessibility.
    public var description: String?

    public init(
        id: String,
        type: Kind,
        url: URL?,
        previewURL: URL? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.previewURL = previewURL
        self.description = description
    }
}

/// A mention inside a status.
public struct Mention: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var acct: String
    public var username: String
    public var url: URL?

    public init(id: String, acct: String, username: String, url: URL? = nil) {
        self.id = id
        self.acct = acct
        self.username = username
        self.url = url
    }
}
