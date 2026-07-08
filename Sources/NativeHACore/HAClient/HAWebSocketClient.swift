import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HAWebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case reconnecting
    case failed(String)
}

public enum HAWebSocketTransportMessage: Equatable {
    case string(String)
    case data(Data)
}

public protocol HAWebSocketTransport: AnyObject {
    func connect(url: URL, headers: [String: String]) async throws
    func send(_ string: String) async throws
    func receive() async throws -> HAWebSocketTransportMessage
    func disconnect()
}

public protocol HAWebSocketClientProtocol: AnyObject {
    func connect() async throws
    func disconnect() async
    func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T
    func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription
}

public struct HAPingConfiguration: Equatable {
    public var intervalSeconds: TimeInterval
    public var timeoutSeconds: TimeInterval

    public init(intervalSeconds: TimeInterval = 30, timeoutSeconds: TimeInterval = 15) {
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
    }
}

public final class URLSessionHAWebSocketTransport: HAWebSocketTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: url)
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    public func send(_ string: String) async throws {
        guard let task = task else {
            throw HAWebSocketClientError.disconnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(.string(string)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func receive() async throws -> HAWebSocketTransportMessage {
        guard let task = task else {
            throw HAWebSocketClientError.disconnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            task.receive { result in
                switch result {
                case let .success(message):
                    switch message {
                    case let .string(value):
                        continuation.resume(returning: .string(value))
                    case let .data(value):
                        continuation.resume(returning: .data(value))
                    @unknown default:
                        continuation.resume(throwing: HAWebSocketClientError.unsupportedTransportMessage)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

private final class HAAnySubscriptionHandler {
    private let handleValue: (HAJSONValue) -> Void

    init(handleValue: @escaping (HAJSONValue) -> Void) {
        self.handleValue = handleValue
    }

    func handle(_ value: HAJSONValue) {
        handleValue(value)
    }
}

public final class HAWebSocketClient: HAWebSocketClientProtocol {
    public private(set) var connectionState: HAWebSocketConnectionState = .disconnected

    private let auth: HAAuth
    private let transport: HAWebSocketTransport
    private let logger: Logger?
    private let pingConfiguration: HAPingConfiguration?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<HAJSONValue, Error>] = [:]
    private var subscriptions: [Int: HAAnySubscriptionHandler] = [:]
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var shouldReconnect = true

    public init(
        auth: HAAuth,
        transport: HAWebSocketTransport = URLSessionHAWebSocketTransport(),
        logger: Logger? = nil,
        pingConfiguration: HAPingConfiguration? = HAPingConfiguration()
    ) {
        self.auth = auth
        self.transport = transport
        self.logger = logger
        self.pingConfiguration = pingConfiguration
    }

    public func connect() async throws {
        shouldReconnect = true
        setConnectionState(.connecting)
        try await transport.connect(url: auth.webSocketURL(), headers: [:])
        setConnectionState(.authenticating)
        try await authenticate()
        setConnectionState(.connected)
        startReceiveLoop()
        startPingLoop()
    }

    public func disconnect() async {
        shouldReconnect = false
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        transport.disconnect()
        failAllPending(with: HAWebSocketClientError.disconnected)
        removeAllSubscriptions()
        setConnectionState(.disconnected)
    }

    public func reconnect(force: Bool = true) async throws {
        guard shouldReconnect || force else {
            return
        }
        setConnectionState(.reconnecting)
        receiveTask?.cancel()
        pingTask?.cancel()
        transport.disconnect()
        failAllPending(with: HAWebSocketClientError.disconnected)
        try await connect()
    }

    public func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T {
        let id = reserveRequestID()
        let outbound = try encodeOutboundMessage(message, id: id)
        let resultValue = try await sendRequest(id: id, outbound: outbound)
        return try decode(T.self, from: resultValue)
    }

    public func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        let id = reserveRequestID()
        let outbound = try encodeOutboundMessage(message, id: id)
        registerSubscription(id: id) { [weak self] value in
            guard let self = self else {
                return
            }
            do {
                let event = try self.decode(T.self, from: value)
                onEvent(event)
            } catch {
                self.logger?.warning(
                    "Failed to decode subscription event",
                    metadata: ["id": String(id), "error": String(describing: error)]
                )
            }
        }

        do {
            let ackValue = try await sendRequest(id: id, outbound: outbound)
            let _: HAEmptyResponse = try decode(HAEmptyResponse.self, from: ackValue)
            return HASubscription(id: id) { [weak self] in
                self?.removeSubscription(id: id)
            }
        } catch {
            removeSubscription(id: id)
            throw error
        }
    }

    public func ping() async throws {
        let _: HAEmptyResponse = try await callWS(HAWebSocketRequest(type: "ping"))
    }

    private func authenticate() async throws {
        let authRequired = try await receiveIncomingMessage()
        guard authRequired.type == "auth_required" else {
            throw HAWebSocketClientError.authRequiredExpected
        }

        let authData = try encoder.encode(auth.authRequest())
        guard let authText = String(data: authData, encoding: .utf8) else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }
        try await transport.send(authText)

        let authResult = try await receiveIncomingMessage()
        if authResult.type == "auth_ok" {
            return
        }
        if authResult.type == "auth_invalid" {
            throw HAWebSocketClientError.invalidAuth(authResult.message ?? "Authentication failed.")
        }
        throw HAWebSocketClientError.invalidInboundMessage
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            while !Task.isCancelled {
                do {
                    let message = try await self.receiveIncomingMessage()
                    self.route(message)
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    self.logger?.warning("Home Assistant WebSocket receive loop ended", metadata: ["error": String(describing: error)])
                    self.setConnectionState(.failed(String(describing: error)))
                    self.failAllPending(with: error)
                    if self.shouldReconnect {
                        do {
                            try await self.reconnect(force: false)
                        } catch {
                            self.logger?.error("Home Assistant WebSocket reconnect failed", metadata: ["error": String(describing: error)])
                        }
                    }
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        guard let pingConfiguration = pingConfiguration else {
            return
        }

        pingTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(pingConfiguration.intervalSeconds * 1_000_000_000))
                    try await self.withTimeout(seconds: pingConfiguration.timeoutSeconds) {
                        try await self.ping()
                    }
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    self.logger?.warning("Home Assistant WebSocket ping failed", metadata: ["error": String(describing: error)])
                    do {
                        try await self.reconnect(force: false)
                    } catch {
                        self.logger?.error("Home Assistant WebSocket ping reconnect failed", metadata: ["error": String(describing: error)])
                    }
                    return
                }
            }
        }
    }

    private func receiveIncomingMessage() async throws -> HAIncomingMessage {
        let transportMessage = try await transport.receive()
        let data: Data
        switch transportMessage {
        case let .string(value):
            data = Data(value.utf8)
        case let .data(value):
            data = value
        }
        return try decoder.decode(HAIncomingMessage.self, from: data)
    }

    private func route(_ message: HAIncomingMessage) {
        switch message.type {
        case "result":
            guard let id = message.id else {
                return
            }
            if message.success == true {
                completePendingRequest(id: id, result: .success(message.result ?? .null))
            } else {
                completePendingRequest(
                    id: id,
                    result: .failure(HAWebSocketClientError.requestFailed(
                        message.error ?? HAWebSocketErrorPayload(code: "unknown_error", message: "Home Assistant request failed.")
                    ))
                )
            }
        case "event":
            guard let id = message.id, let event = message.event else {
                return
            }
            dispatchSubscriptionEvent(id: id, event: event)
        case "pong":
            guard let id = message.id else {
                return
            }
            completePendingRequest(id: id, result: .success(.object([:])))
        default:
            logger?.debug("Ignoring Home Assistant WebSocket message", metadata: ["type": message.type])
        }
    }

    private func sendRequest(id: Int, outbound: String) async throws -> HAJSONValue {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerPendingRequest(id: id, continuation: continuation)
                Task { [weak self] in
                    guard let self = self else {
                        return
                    }
                    do {
                        try await self.transport.send(outbound)
                    } catch {
                        self.completePendingRequest(id: id, result: .failure(error))
                    }
                }
            }
        } onCancel: {
            self.completePendingRequest(id: id, result: .failure(HAWebSocketClientError.disconnected))
        }
    }

    private func encodeOutboundMessage<Message: Encodable>(_ message: Message, id: Int) throws -> String {
        let data = try encoder.encode(message)
        var object = try decoder.decode([String: HAJSONValue].self, from: data)
        guard object["type"] != nil else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }
        object["id"] = .integer(id)
        let outboundData = try encoder.encode(object)
        guard let outbound = String(data: outboundData, encoding: .utf8) else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }
        return outbound
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: HAJSONValue) throws -> T {
        if let value = value as? T {
            return value
        }
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private func reserveRequestID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextRequestID
        nextRequestID += 1
        return id
    }

    private func registerPendingRequest(id: Int, continuation: CheckedContinuation<HAJSONValue, Error>) {
        lock.lock()
        pendingRequests[id] = continuation
        lock.unlock()
    }

    private func completePendingRequest(id: Int, result: Result<HAJSONValue, Error>) {
        lock.lock()
        let continuation = pendingRequests.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func failAllPending(with error: Error) {
        lock.lock()
        let pending = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    private func registerSubscription(id: Int, handler: @escaping (HAJSONValue) -> Void) {
        lock.lock()
        subscriptions[id] = HAAnySubscriptionHandler(handleValue: handler)
        lock.unlock()
    }

    private func dispatchSubscriptionEvent(id: Int, event: HAJSONValue) {
        lock.lock()
        let handler = subscriptions[id]
        lock.unlock()
        handler?.handle(event)
    }

    private func removeSubscription(id: Int) {
        lock.lock()
        subscriptions.removeValue(forKey: id)
        lock.unlock()
    }

    private func removeAllSubscriptions() {
        lock.lock()
        subscriptions.removeAll()
        lock.unlock()
    }

    private func setConnectionState(_ state: HAWebSocketConnectionState) {
        lock.lock()
        connectionState = state
        lock.unlock()
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HAWebSocketClientError.timedOut
            }
            guard let result = try await group.next() else {
                throw HAWebSocketClientError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
