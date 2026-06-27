//
//  PostLinks.swift
//  FastSMCore
//
//  Collects the openable links and playable media in a post — used by the
//  "Open Link" (⌘Return) and "Play Media" (Shift+Return) actions.
//

import Foundation

public struct PostLink: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let title: String
    public let url: URL
    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public enum PostLinks {
    /// Every link worth offering: links in the text, the link-preview card (with
    /// its title), media attachments, and the post's own URL — de-duplicated.
    public static func links(for status: Status) -> [PostLink] {
        let display = status.displayStatus
        var result: [PostLink] = []
        var seen = Set<URL>()

        func add(_ title: String, _ url: URL?) {
            guard let url, !seen.contains(url) else { return }
            seen.insert(url)
            result.append(PostLink(title: title, url: url))
        }

        // The link-preview card, if any — its title decorates the matching text
        // link rather than appearing as a separate entry.
        let card = display.card.flatMap { c in c.url.map { (url: $0, title: c.title) } }

        // Links embedded in the post text.
        for (text, url) in anchors(in: display.content) {
            if let card, card.url == url, !card.title.isEmpty {
                add(card.title, url)
            } else {
                add(text.isEmpty ? url.absoluteString : text, url)
            }
        }

        // If the card's link wasn't already in the text, add it on its own.
        if let card, !seen.contains(card.url) {
            add(card.title.isEmpty ? card.url.absoluteString : card.title, card.url)
        }

        // Media attachments.
        for media in display.mediaAttachments {
            let noun = media.type.rawValue.capitalized
            let label = (media.description?.isEmpty == false) ? media.description! : noun
            add("\(label) (\(media.type.rawValue))", media.url)
        }

        // The post itself.
        add("Open this post in browser", display.url)

        return result
    }

    /// Attachments that can be played (video / animated GIF / audio).
    public static func playableMedia(for status: Status) -> [MediaAttachment] {
        status.displayStatus.mediaAttachments.filter {
            ($0.type == .video || $0.type == .gifv || $0.type == .audio) && $0.url != nil
        }
    }

    /// Extract `(visible text, href)` pairs from HTML, skipping mention/hashtag
    /// anchors (those aren't "links" a user wants to open externally).
    private static func anchors(in html: String) -> [(String, URL)] {
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\s+[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var out: [(String, URL)] = []
        for match in regex.matches(in: html, range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }
            let href = String(html[hrefRange])
            let fullTag = (Range(match.range, in: html)).map { String(html[$0]) } ?? ""
            if fullTag.contains("mention") || fullTag.contains("hashtag") { continue }
            let text = HTMLStripper.strip(String(html[textRange]))
            if let url = URL(string: href), url.scheme?.hasPrefix("http") == true {
                out.append((text, url))
            }
        }
        return out
    }
}
