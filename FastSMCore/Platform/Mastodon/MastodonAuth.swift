//
//  MastodonAuth.swift
//  FastSMCore
//
//  Mastodon OAuth. Ports the create_app → authorize → token-exchange flow from
//  mastodon_api.py:150-205, but uses a custom redirect scheme (fastsm://oauth)
//  with ASWebAuthenticationSession instead of out-of-band code pasting.
//

import Foundation

/// Persisted Mastodon credentials. The access token is the secret; store it in
/// the Keychain, not in plain config.
public struct MastodonCredentials: Codable, Sendable, Equatable {
    public var instanceURL: URL
    public var clientID: String
    public var clientSecret: String
    public var accessToken: String

    public init(instanceURL: URL, clientID: String, clientSecret: String, accessToken: String) {
        self.instanceURL = instanceURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accessToken = accessToken
    }
}

public enum MastodonAuth {
    static let scopes = "read write follow push"
    static let redirectURI = "fastsm://oauth"
    static let callbackScheme = "fastsm"
    static let clientName = "FastSM"
    static let website = "https://github.com/masonasons/FastSM"

    /// Normalize user-typed instance text into an https base URL.
    public static func normalizeInstance(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        // Strip any trailing path/slash; we only want scheme + host.
        guard let comps = URLComponents(string: text), let host = comps.host else { return nil }
        var base = URLComponents()
        base.scheme = comps.scheme == "http" ? "http" : "https"
        base.host = host
        if let port = comps.port { base.port = port }
        return base.url
    }

    private struct AppRegistrationDTO: Decodable {
        let clientId: String
        let clientSecret: String
    }

    private struct TokenDTO: Decodable {
        let accessToken: String
    }

    /// Full interactive sign-in. Must run on the main actor because it presents
    /// a web auth sheet.
    @MainActor
    public static func signIn(
        instance rawInstance: String,
        anchorProvider: PresentationAnchorProviding,
        clientName: String = "FastSM",
        http: HTTP = HTTP()
    ) async throws -> (MastodonCredentials, User) {
        guard let instanceURL = normalizeInstance(rawInstance) else {
            throw PlatformError.invalidInstance
        }

        // 1. Register the app (POST /api/v1/apps). client_name becomes the post
        // "source" shown on Mastodon.
        let registration = try await registerApp(instanceURL: instanceURL, clientName: clientName, http: http)

        // 2. Authorize in the browser and capture the code.
        let authorizeURL = buildAuthorizeURL(instanceURL: instanceURL, clientID: registration.clientId)
        let session = OAuthSession(anchorProvider: anchorProvider)
        let callback = try await session.authenticate(url: authorizeURL, callbackScheme: callbackScheme)
        guard let code = authorizationCode(from: callback) else {
            throw PlatformError.message("Sign-in didn't return an authorization code.")
        }

        // 3. Exchange the code for an access token.
        let token = try await exchangeToken(
            instanceURL: instanceURL,
            clientID: registration.clientId,
            clientSecret: registration.clientSecret,
            code: code,
            http: http
        )

        let credentials = MastodonCredentials(
            instanceURL: instanceURL,
            clientID: registration.clientId,
            clientSecret: registration.clientSecret,
            accessToken: token
        )

        // 4. Fetch the authenticated user.
        let client = MastodonClient(credentials: credentials, http: http)
        let me = try await client.verifyCredentials()
        return (credentials, me)
    }

    private static func registerApp(instanceURL: URL, clientName: String, http: HTTP) async throws -> AppRegistrationDTO {
        var request = URLRequest(url: instanceURL.appendingPathComponent("api/v1/apps"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody([
            "client_name": clientName,
            "redirect_uris": redirectURI,
            "scopes": scopes,
            "website": website,
        ])
        return try await http.decode(AppRegistrationDTO.self, from: request, decoder: MastodonJSON.decoder)
    }

    private static func buildAuthorizeURL(instanceURL: URL, clientID: String) -> URL {
        var comps = URLComponents(url: instanceURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
        ]
        return comps.url!
    }

    private static func exchangeToken(
        instanceURL: URL,
        clientID: String,
        clientSecret: String,
        code: String,
        http: HTTP
    ) async throws -> String {
        var request = URLRequest(url: instanceURL.appendingPathComponent("oauth/token"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "code": code,
            "scope": scopes,
        ])
        let token = try await http.decode(TokenDTO.self, from: request, decoder: MastodonJSON.decoder)
        return token.accessToken
    }

    private static func authorizationCode(from callback: URL) -> String? {
        URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }
}
