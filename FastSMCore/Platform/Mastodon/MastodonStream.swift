//
//  MastodonStream.swift
//  FastSMCore
//
//  Mastodon streaming over a WebSocket (`stream=user`): delivers home `update`
//  and `notification` events in real time, with automatic reconnect.
//

import Foundation

public final class MastodonStream: NSObject, StreamConnection, @unchecked Sendable {
    private let url: URL
    private let onEvent: @Sendable (StreamEvent) -> Void
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var stopped = false

    init?(credentials: MastodonCredentials, onEvent: @escaping @Sendable (StreamEvent) -> Void) {
        // https → wss for the streaming endpoint.
        guard var comps = URLComponents(url: credentials.instanceURL.appendingPathComponent("api/v1/streaming"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = (comps.scheme == "http") ? "ws" : "wss"
        comps.queryItems = [
            URLQueryItem(name: "stream", value: "user"),
            URLQueryItem(name: "access_token", value: credentials.accessToken),
        ]
        guard let url = comps.url else { return nil }
        self.url = url
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        connect()
    }

    public func stop() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() {
        guard !stopped else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNext()
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self, !self.stopped else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveNext()
            case .failure:
                self.reconnectAfterDelay()
            }
        }
    }

    private func reconnectAfterDelay() {
        guard !stopped else { return }
        task = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.connect()
        }
    }

    private struct Envelope: Decodable {
        let event: String
        let payload: String?
    }

    private func handle(_ text: String) {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else { return }
        switch env.event {
        case "update":
            guard let payload = env.payload,
                  let dto = try? MastodonJSON.decoder.decode(MastodonStatusDTO.self, from: Data(payload.utf8)),
                  let status = MastodonMapper.status(dto) else { return }
            onEvent(.update(status))
        case "notification":
            guard let payload = env.payload,
                  let dto = try? MastodonJSON.decoder.decode(MastodonNotificationDTO.self, from: Data(payload.utf8)),
                  let notification = MastodonMapper.notification(dto) else { return }
            onEvent(.notification(notification))
        case "delete":
            if let payload = env.payload { onEvent(.delete(payload)) }
        default:
            break
        }
    }
}
