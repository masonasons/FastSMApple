//
//  ErrorPresentation.swift
//  FastSMCore
//
//  Turns a thrown error into a specific, human-readable summary plus a full,
//  copyable detail block. The apps use this to show "what actually went wrong"
//  (including the server's own message) instead of a generic box, and to offer a
//  "Copy Details" button so a tester can paste the specifics into a bug report.
//

import Foundation

/// A user-facing rendering of an error.
public struct PresentedError: Sendable, Equatable {
    /// One line, as specific as we can make it — used as the alert title/heading.
    public let summary: String
    /// The full, copyable breakdown: summary, then technical details and context.
    public let detail: String

    public init(summary: String, detail: String) {
        self.summary = summary
        self.detail = detail
    }
}

public extension Error {
    /// True when this error just means the work was cancelled — Swift task
    /// cancellation or a cancelled URL request. This is expected control flow
    /// (a superseded refresh, a view that went away, a stream that already
    /// delivered the data) and must never be surfaced as a failure.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

public enum ErrorPresenter {
    /// Build a `PresentedError` from any thrown error.
    /// - Parameters:
    ///   - error: the thrown error.
    ///   - context: what the app was doing (e.g. "Posting a status"), folded into
    ///     the copyable detail so a report says where it happened.
    public static func present(_ error: Error, context: String? = nil) -> PresentedError {
        let (summary, technical) = summarize(error)
        var lines: [String] = [summary, ""]
        if let context, !context.isEmpty { lines.append("While: \(context)") }
        lines.append(contentsOf: technical)
        return PresentedError(summary: summary, detail: lines.joined(separator: "\n"))
    }

    /// A specific one-line summary plus technical detail lines for the given error.
    private static func summarize(_ error: Error) -> (summary: String, technical: [String]) {
        guard let platform = error as? PlatformError else {
            // Anything not from our clients: surface whatever description it carries,
            // and keep the raw value for the copyable detail.
            let described = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (described, ["Kind: \(String(reflecting: type(of: error)))",
                                "Raw: \(String(reflecting: error))"])
        }

        switch platform {
        case .notAuthenticated:
            return ("You're not signed in.", ["Kind: not authenticated"])

        case .invalidInstance:
            return ("That doesn't look like a valid server address.", ["Kind: invalid instance"])

        case .message(let text):
            return (text, ["Kind: message"])

        case .network(let detail):
            let summary = detail.isEmpty ? "Network error." : "Network error: \(detail)"
            return (summary, ["Kind: network", "Detail: \(detail.isEmpty ? "(none)" : detail)"])

        case .decoding(let detail):
            return ("Couldn't read the server's response.",
                    ["Kind: decoding", "Detail: \(detail)"])

        case .http(let status, let body):
            let meaning = httpMeaning(status)
            let server = serverMessage(from: body)
            let summary: String
            if let server, !server.isEmpty {
                summary = "\(server) (HTTP \(status))"
            } else {
                summary = "Server error \(status)\(meaning.isEmpty ? "" : " — \(meaning)")"
            }
            let technical = ["Kind: HTTP",
                             "Status: \(status)\(meaning.isEmpty ? "" : " \(meaning)")",
                             "Body: \(body.isEmpty ? "(empty)" : body)"]
            return (summary, technical)
        }
    }

    /// Pull a human message out of a JSON error body. Mastodon uses `error` /
    /// `error_description` (its `error` is already human, e.g. "Validation failed:
    /// …"); Bluesky uses `message` with a machine `error` code. Prefer the most
    /// human field available.
    static func serverMessage(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in ["error_description", "message"] {
            if let value = obj[key] as? String,
               !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        if let value = obj["error"] as? String,
           !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        return nil
    }

    /// A short phrase for an HTTP status ("Unauthorized", "Not Found", …).
    private static func httpMeaning(_ status: Int) -> String {
        let text = HTTPURLResponse.localizedString(forStatusCode: status)
            .trimmingCharacters(in: .whitespaces)
        return text.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}
