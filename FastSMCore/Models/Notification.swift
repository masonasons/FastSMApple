//
//  Notification.swift
//  FastSMCore
//
//  Port of FastSM's `UniversalNotification` (models/notification.py).
//

import Foundation

/// A platform-agnostic notification.
public struct Notification: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case follow
        case followRequest = "follow_request"
        case favourite
        case reblog
        case mention
        case poll
        case status
        case update
        case unknown
    }

    public let id: String
    public var type: Kind
    /// Who triggered the notification.
    public var account: User
    public var createdAt: Date
    /// The related status, if any.
    public var status: Status?
    public var platform: Platform

    public init(
        id: String,
        type: Kind,
        account: User,
        createdAt: Date,
        status: Status? = nil,
        platform: Platform
    ) {
        self.id = id
        self.type = type
        self.account = account
        self.createdAt = createdAt
        self.status = status
        self.platform = platform
    }
}
