//
//  BlueskyAuth.swift
//  FastSMCore
//
//  AT Protocol session handling. Bluesky uses an app-password login
//  (com.atproto.server.createSession) rather than OAuth. We persist the app
//  password (a long-lived, user-revocable credential) and create a fresh
//  session on launch; within a session we refresh the access JWT on 401.
//

import Foundation

/// Persisted Bluesky credentials. `appPassword` is the secret → Keychain.
public struct BlueskyCredentials: Codable, Sendable, Equatable {
    public var serviceURL: URL
    public var identifier: String
    public var appPassword: String
    public var did: String
    public var handle: String

    public init(serviceURL: URL, identifier: String, appPassword: String, did: String, handle: String) {
        self.serviceURL = serviceURL
        self.identifier = identifier
        self.appPassword = appPassword
        self.did = did
        self.handle = handle
    }
}

/// An active, in-memory AT Proto session.
struct BlueskySession: Sendable {
    var accessJwt: String
    var refreshJwt: String
    var did: String
    var handle: String
    /// The user's PDS endpoint (from the DID document), used for all calls.
    var pdsURL: URL
}

public enum BlueskyAuth {
    public static let defaultService = URL(string: "https://bsky.social")!

    private struct CreateSessionResponse: Decodable {
        let accessJwt: String
        let refreshJwt: String
        let did: String
        let handle: String
        let didDoc: DIDDocument?
    }

    private struct RefreshSessionResponse: Decodable {
        let accessJwt: String
        let refreshJwt: String
        let did: String
        let handle: String
    }

    private struct DIDDocument: Decodable {
        struct Service: Decodable {
            let id: String
            let type: String
            let serviceEndpoint: String
        }
        let service: [Service]?

        var pdsEndpoint: URL? {
            guard let service else { return nil }
            let pds = service.first { $0.id.hasSuffix("atproto_pds") || $0.type == "AtprotoPersonalDataServer" }
            return pds.flatMap { URL(string: $0.serviceEndpoint) }
        }
    }

    /// Normalize a handle: strip a leading "@" and whitespace.
    public static func normalizeIdentifier(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        return text
    }

    static func createSession(
        identifier: String,
        appPassword: String,
        serviceURL: URL,
        http: HTTP
    ) async throws -> BlueskySession {
        var request = URLRequest(url: serviceURL.appendingPathComponent("xrpc/com.atproto.server.createSession"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "identifier": identifier,
            "password": appPassword,
        ])
        let response = try await http.decode(CreateSessionResponse.self, from: request, decoder: BlueskyJSON.decoder)
        return BlueskySession(
            accessJwt: response.accessJwt,
            refreshJwt: response.refreshJwt,
            did: response.did,
            handle: response.handle,
            pdsURL: response.didDoc?.pdsEndpoint ?? serviceURL
        )
    }

    static func refreshSession(_ session: BlueskySession, http: HTTP) async throws -> BlueskySession {
        var request = URLRequest(url: session.pdsURL.appendingPathComponent("xrpc/com.atproto.server.refreshSession"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("Bearer \(session.refreshJwt)", forHTTPHeaderField: "Authorization")
        let response = try await http.decode(RefreshSessionResponse.self, from: request, decoder: BlueskyJSON.decoder)
        var updated = session
        updated.accessJwt = response.accessJwt
        updated.refreshJwt = response.refreshJwt
        return updated
    }
}
