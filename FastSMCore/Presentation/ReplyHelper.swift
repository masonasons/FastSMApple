//
//  ReplyHelper.swift
//  FastSMCore
//
//  Builds the leading @-mention text for a reply, including everyone in the
//  conversation (the author plus everyone they mentioned), minus yourself —
//  matching the Mastodon convention. Shared by both apps.
//

import Foundation

public enum ReplyHelper {
    /// Ordered, de-duplicated "@a @b " prefix for replying to `status` as `me`.
    /// Returns "" when there's no one to mention. (Mastodon-style; Bluesky uses
    /// structural replies, so callers there typically skip this.)
    public static func mentionPrefix(replyingTo status: Status, me: User) -> String {
        var handles: [String] = [status.account.acct]
        handles.append(contentsOf: status.mentions.map(\.acct))

        let mine = me.acct.lowercased()
        var seen = Set<String>()
        var ordered: [String] = []
        for handle in handles {
            let key = handle.lowercased()
            guard !handle.isEmpty, key != mine, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(handle)
        }

        guard !ordered.isEmpty else { return "" }
        return ordered.map { "@\($0)" }.joined(separator: " ") + " "
    }
}
