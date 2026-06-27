//
//  HTTP.swift
//  FastSMCore
//
//  Minimal URLSession helpers shared by the platform clients. Centralizes
//  status-code checking and JSON decoding so MastodonClient / BlueskyClient stay
//  focused on endpoint shapes.
//

import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public struct HTTP {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Perform a request, validating the HTTP status, and return the body data.
    public func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlatformError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.network("Malformed response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.http(status: http.statusCode, body: body)
        }
        return data
    }

    /// Perform a request and decode the JSON body as `T`.
    public func decode<T: Decodable>(_ type: T.Type, from request: URLRequest, decoder: JSONDecoder) async throws -> T {
        let data = try await data(for: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PlatformError.decoding(String(describing: error))
        }
    }

    /// Build form-urlencoded body data from key/value pairs.
    public static func formBody(_ params: [String: String]) -> Data {
        orderedFormBody(params.map { ($0.key, $0.value) })
    }

    /// Build form-urlencoded body data preserving order and duplicate keys
    /// (needed for repeated fields like `poll[options][]`).
    public static func orderedFormBody(_ params: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
