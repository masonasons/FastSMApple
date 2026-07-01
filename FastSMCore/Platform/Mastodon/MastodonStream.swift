//
//  MastodonStream.swift
//  FastSMCore
//
//  Mastodon streaming over a WebSocket (`stream=user`): delivers home `update`
//  and `notification` events in real time.
//
//  The connection is kept alive and self-heals: a keepalive ping runs on a timer,
//  and a watchdog reconnects if the socket goes quiet (a silently half-dead socket
//  — common after a network blip or an app backgrounding — otherwise never fires a
//  `.failure`, so the stream would freeze until the app relaunched). All mutable
//  state is confined to a serial queue so the receive callback, the keepalive
//  timer, and stop() can't race.
//

import Foundation

public final class MastodonStream: NSObject, StreamConnection, @unchecked Sendable {
    private let url: URL
    private let onEvent: @Sendable (StreamEvent) -> Void
    private let session = URLSession(configuration: .default)

    /// All mutable state below is touched only on this queue.
    private let queue = DispatchQueue(label: "me.masonasons.fastsm.mastodon-stream")
    private var task: URLSessionWebSocketTask?
    private var stopped = false
    private var lastActivity = Date()
    private var keepAlive: DispatchSourceTimer?

    /// Ping this often to keep the connection from going idle; reconnect if we
    /// haven't heard anything (message or pong) for `staleTimeout`.
    private let pingInterval: TimeInterval = 25
    private let staleTimeout: TimeInterval = 60

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
        queue.async { [weak self] in self?.connect() }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.keepAlive?.cancel()
            self.keepAlive = nil
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
        }
    }

    // MARK: - Connection (all on `queue`)

    private func connect() {
        guard !stopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: url)
        self.task = task
        lastActivity = Date()
        task.resume()
        receiveNext(on: task)
        startKeepAlive()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.connect() }
    }

    private func startKeepAlive() {
        keepAlive?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in self?.keepAliveTick() }
        keepAlive = timer
        timer.resume()
    }

    private func keepAliveTick() {
        guard !stopped, let task else { return }
        // No traffic (not even a pong) for too long → the socket died silently.
        if Date().timeIntervalSince(lastActivity) > staleTimeout {
            scheduleReconnect()
            return
        }
        task.sendPing { [weak self] error in
            guard let self else { return }
            self.queue.async {
                guard !self.stopped, task === self.task else { return }
                if error != nil {
                    self.scheduleReconnect()
                } else {
                    self.lastActivity = Date()   // a live pong counts as activity
                }
            }
        }
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                // Ignore callbacks from a superseded connection.
                guard !self.stopped, task === self.task else { return }
                switch result {
                case .success(let message):
                    self.lastActivity = Date()
                    if case .string(let text) = message { self.handle(text) }
                    self.receiveNext(on: task)
                case .failure:
                    self.scheduleReconnect()
                }
            }
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
