//
//  Card.swift
//  FastSMCore
//
//  Lightweight link-preview card and poll types. FastSM keeps these as raw
//  platform dicts (UniversalStatus.card / .poll); here we model the fields the
//  UI actually reads.
//

import Foundation

/// A link preview card attached to a status.
public struct Card: Codable, Sendable, Hashable {
    public var url: URL?
    public var title: String
    public var description: String
    public var imageURL: URL?

    public init(url: URL? = nil, title: String = "", description: String = "", imageURL: URL? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.imageURL = imageURL
    }
}

/// A poll attached to a status.
public struct Poll: Identifiable, Codable, Sendable, Hashable {
    public struct Option: Codable, Sendable, Hashable {
        public var title: String
        public var votesCount: Int
        public init(title: String, votesCount: Int = 0) {
            self.title = title
            self.votesCount = votesCount
        }
    }

    public let id: String
    public var expiresAt: Date?
    public var expired: Bool
    public var multiple: Bool
    public var votesCount: Int
    public var voted: Bool
    public var options: [Option]

    public init(
        id: String,
        expiresAt: Date? = nil,
        expired: Bool = false,
        multiple: Bool = false,
        votesCount: Int = 0,
        voted: Bool = false,
        options: [Option] = []
    ) {
        self.id = id
        self.expiresAt = expiresAt
        self.expired = expired
        self.multiple = multiple
        self.votesCount = votesCount
        self.voted = voted
        self.options = options
    }
}
