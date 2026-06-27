//
//  UserPresenter.swift
//  FastSMCore
//
//  Display + VoiceOver strings for user rows (followers/following lists, search
//  results, etc.).
//

import Foundation

public enum UserPresenter {
    public static func compactLine(for user: User) -> String {
        "\(user.bestName) (@\(user.acct))"
    }

    public static func accessibilityLabel(
        for user: User, speech: [SpeechItem<UserSpeechField>] = SpeechConfig.current.user
    ) -> String {
        var parts: [String] = []
        for item in speech where item.enabled {
            if let part = string(for: item.field, user: user), !part.isEmpty {
                parts.append(part)
            }
        }
        return parts.joined(separator: ", ")
    }

    private static func string(for field: UserSpeechField, user: User) -> String? {
        switch field {
        case .author: return user.bestName
        case .handle: return "@\(user.acct)"
        case .bot: return user.bot ? "bot" : nil
        case .locked: return user.locked ? "locked account" : nil
        case .bio:
            let bio = HTMLStripper.strip(user.note)
            return bio.isEmpty ? nil : bio
        case .followers: return "\(user.followersCount) followers"
        case .following: return "\(user.followingCount) following"
        case .posts: return "\(user.statusesCount) posts"
        }
    }
}
