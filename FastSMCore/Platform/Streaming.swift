//
//  Streaming.swift
//  FastSMCore
//
//  Real-time timeline updates. A platform opens a stream and delivers events;
//  the app routes them into the matching timelines (which chime their sound).
//

import Foundation

/// A real-time event from a platform stream.
public enum StreamEvent: Sendable {
    case update(Status)            // new post for the home timeline
    case notification(Notification) // a new notification (mention, follow, …)
    case delete(String)            // a status id that was deleted
}

/// A live stream connection that can be stopped.
public protocol StreamConnection: AnyObject, Sendable {
    func stop()
}
