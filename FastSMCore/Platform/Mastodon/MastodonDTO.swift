//
//  MastodonDTO.swift
//  FastSMCore
//
//  Codable mirrors of the Mastodon REST API JSON, plus mapping into FastSMCore's
//  universal models. Port of platforms/mastodon/models.py. Decoding uses
//  `.convertFromSnakeCase`, so DTO properties are camelCase.
//

import Foundation

/// Shared JSON decoder configured for Mastodon responses.
enum MastodonJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

struct MastodonAccountDTO: Decodable {
    let id: String
    let acct: String?
    let username: String?
    let displayName: String?
    let note: String?
    let avatar: String?
    let header: String?
    let followersCount: Int?
    let followingCount: Int?
    let statusesCount: Int?
    let createdAt: String?
    let url: String?
    let bot: Bool?
    let locked: Bool?
}

struct MastodonMediaDTO: Decodable {
    let id: String
    let type: String?
    let url: String?
    let previewUrl: String?
    let description: String?
}

struct MastodonMentionDTO: Decodable {
    let id: String
    let acct: String?
    let username: String?
    let url: String?
}

struct MastodonPollOptionDTO: Decodable {
    let title: String
    let votesCount: Int?
}

struct MastodonPollDTO: Decodable {
    let id: String
    let expiresAt: String?
    let expired: Bool?
    let multiple: Bool?
    let votesCount: Int?
    let voted: Bool?
    let options: [MastodonPollOptionDTO]?
}

struct MastodonCardDTO: Decodable {
    let url: String?
    let title: String?
    let description: String?
    let image: String?
}

struct MastodonQuoteDTO: Decodable {
    let quotedStatus: MastodonStatusDTO?
}

/// `GET /api/v1/statuses/:id/source` — the editable text + content warning.
struct MastodonStatusSourceDTO: Decodable {
    let text: String
    let spoilerText: String?
}

/// Reference type so a status can recursively contain its reblog/quote.
final class MastodonStatusDTO: Decodable {
    let id: String
    let createdAt: String?
    let content: String?
    let account: MastodonAccountDTO?
    let reblog: MastodonStatusDTO?
    let quote: MastodonQuoteDTO?
    let mediaAttachments: [MastodonMediaDTO]?
    let mentions: [MastodonMentionDTO]?
    let favouritesCount: Int?
    let reblogsCount: Int?
    let repliesCount: Int?
    let inReplyToId: String?
    let inReplyToAccountId: String?
    let url: String?
    let visibility: String?
    let spoilerText: String?
    let card: MastodonCardDTO?
    let poll: MastodonPollDTO?
    let pinned: Bool?
    let favourited: Bool?
    let reblogged: Bool?
    let bookmarked: Bool?
    let application: MastodonApplicationDTO?
    /// Plaintext source, present on deleted statuses for redraft.
    let text: String?
}

struct MastodonApplicationDTO: Decodable {
    let name: String?
}

struct MastodonListDTO: Decodable {
    let id: String
    let title: String
}

struct MastodonRelationshipDTO: Decodable {
    let id: String
    let following: Bool?
    let followedBy: Bool?
    let muting: Bool?
    let blocking: Bool?
    let showingReblogs: Bool?
}

struct MastodonMarkersDTO: Decodable {
    struct Marker: Decodable { let lastReadId: String? }
    let home: Marker?
}

struct MastodonSearchDTO: Decodable {
    let statuses: [MastodonStatusDTO]?
    let accounts: [MastodonAccountDTO]?
}

struct MastodonNotificationDTO: Decodable {
    let id: String
    let type: String?
    let account: MastodonAccountDTO?
    let createdAt: String?
    let status: MastodonStatusDTO?
}

struct MastodonConversationDTO: Decodable {
    let id: String
    let lastStatus: MastodonStatusDTO?
}

struct MastodonContextDTO: Decodable {
    let ancestors: [MastodonStatusDTO]
    let descendants: [MastodonStatusDTO]
}

struct MastodonInstanceDTO: Decodable {
    struct Configuration: Decodable {
        struct Statuses: Decodable {
            let maxCharacters: Int?
        }
        let statuses: Statuses?
    }
    let configuration: Configuration?
}

// MARK: - Mapping to universal models

enum MastodonMapper {
    static func user(_ dto: MastodonAccountDTO?) -> User? {
        guard let dto else { return nil }
        let acct = dto.acct ?? ""
        let displayName = (dto.displayName?.isEmpty == false) ? dto.displayName! : acct
        return User(
            id: dto.id,
            acct: acct,
            username: dto.username ?? "",
            displayName: displayName,
            note: dto.note ?? "",
            avatarURL: dto.avatar.flatMap(URL.init(string:)),
            headerURL: dto.header.flatMap(URL.init(string:)),
            followersCount: dto.followersCount ?? 0,
            followingCount: dto.followingCount ?? 0,
            statusesCount: dto.statusesCount ?? 0,
            createdAt: DateParsing.parse(dto.createdAt),
            url: dto.url.flatMap(URL.init(string:)),
            bot: dto.bot ?? false,
            locked: dto.locked ?? false,
            platform: .mastodon
        )
    }

    static func media(_ dto: MastodonMediaDTO) -> MediaAttachment {
        MediaAttachment(
            id: dto.id,
            type: MediaAttachment.Kind(rawValue: dto.type ?? "unknown") ?? .unknown,
            url: dto.url.flatMap(URL.init(string:)),
            previewURL: dto.previewUrl.flatMap(URL.init(string:)),
            description: dto.description
        )
    }

    static func mention(_ dto: MastodonMentionDTO) -> Mention {
        Mention(
            id: dto.id,
            acct: dto.acct ?? "",
            username: dto.username ?? "",
            url: dto.url.flatMap(URL.init(string:))
        )
    }

    static func poll(_ dto: MastodonPollDTO?) -> Poll? {
        guard let dto else { return nil }
        return Poll(
            id: dto.id,
            expiresAt: DateParsing.parse(dto.expiresAt),
            expired: dto.expired ?? false,
            multiple: dto.multiple ?? false,
            votesCount: dto.votesCount ?? 0,
            voted: dto.voted ?? false,
            options: (dto.options ?? []).map { Poll.Option(title: $0.title, votesCount: $0.votesCount ?? 0) }
        )
    }

    static func card(_ dto: MastodonCardDTO?) -> Card? {
        guard let dto, dto.url != nil || dto.title != nil else { return nil }
        return Card(
            url: dto.url.flatMap(URL.init(string:)),
            title: dto.title ?? "",
            description: dto.description ?? "",
            imageURL: dto.image.flatMap(URL.init(string:))
        )
    }

    /// Choose the best plaintext for display, mirroring the source/text fallbacks
    /// in mastodon_status_to_universal, then HTML-strip the content.
    private static func plaintext(content: String, sourceText: String?) -> String {
        if let sourceText, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceText
        }
        return HTMLStripper.strip(content)
    }

    static func status(_ dto: MastodonStatusDTO?) -> Status? {
        guard let dto else { return nil }
        let account = user(dto.account) ?? User(
            id: "0", acct: "", username: "", displayName: "", platform: .mastodon
        )
        let content = dto.content ?? ""

        var reblog: Reblog?
        if let reblogDTO = dto.reblog, let mapped = status(reblogDTO) {
            reblog = Reblog(mapped)
        }

        var quote: Reblog?
        if let quotedDTO = dto.quote?.quotedStatus, let mapped = status(quotedDTO) {
            quote = Reblog(mapped)
        }

        var displayText = plaintext(content: content, sourceText: dto.text)
        if let quote {
            displayText = QuoteText.stripped(displayText, quotedURL: quote.status.url)
        }

        return Status(
            id: dto.id,
            account: account,
            content: content,
            text: displayText,
            createdAt: DateParsing.parse(dto.createdAt) ?? Date(),
            favouritesCount: dto.favouritesCount ?? 0,
            boostsCount: dto.reblogsCount ?? 0,
            repliesCount: dto.repliesCount ?? 0,
            inReplyToID: dto.inReplyToId,
            inReplyToAccountID: dto.inReplyToAccountId,
            reblog: reblog,
            quote: quote,
            mediaAttachments: (dto.mediaAttachments ?? []).map(media),
            mentions: (dto.mentions ?? []).map(mention),
            url: dto.url.flatMap(URL.init(string:)),
            visibility: dto.visibility.flatMap(Visibility.init(rawValue:)),
            spoilerText: dto.spoilerText,
            card: card(dto.card),
            poll: poll(dto.poll),
            pinned: dto.pinned ?? false,
            favourited: dto.favourited ?? false,
            boosted: dto.reblogged ?? false,
            bookmarked: dto.bookmarked ?? false,
            applicationName: dto.application?.name,
            platform: .mastodon
        )
    }

    static func notification(_ dto: MastodonNotificationDTO) -> Notification? {
        guard let account = user(dto.account) else { return nil }
        return Notification(
            id: dto.id,
            type: Notification.Kind(rawValue: dto.type ?? "unknown") ?? .unknown,
            account: account,
            createdAt: DateParsing.parse(dto.createdAt) ?? Date(),
            status: status(dto.status),
            platform: .mastodon
        )
    }
}
