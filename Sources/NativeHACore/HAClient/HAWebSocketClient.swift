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
    func subscribe<T: Decodable>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription
}

public extension HAWebSocketClientProtocol {
    func subscribe<T: Decodable>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        try await subscribe(buildMessage(), onEvent: onEvent)
    }
}

public protocol HAWebSocketReconnectNotifying: AnyObject {
    var onReconnect: (() -> Void)? { get set }
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
        try await task.send(.string(string))
    }

    public func receive() async throws -> HAWebSocketTransportMessage {
        guard let task = task else {
            throw HAWebSocketClientError.disconnected
        }
        let message = try await task.receive()
        switch message {
        case let .string(value):
            return .string(value)
        case let .data(value):
            return .data(value)
        @unknown default:
            throw HAWebSocketClientError.unsupportedTransportMessage
        }
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

private final class AtomicID {
    private let lock = NSLock()
    private var value: Int?
    func set(_ val: Int) {
        lock.lock()
        value = val
        lock.unlock()
    }
    func get() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class HAAnySubscriptionHandler {
    let buildMessageObject: () throws -> [String: HAJSONValue]
    let onReplay: () -> Void
    private let handleValue: (HAJSONValue) -> Void

    init(
        buildMessageObject: @escaping () throws -> [String: HAJSONValue],
        onReplay: @escaping () -> Void,
        handleValue: @escaping (HAJSONValue) -> Void
    ) {
        self.buildMessageObject = buildMessageObject
        self.onReplay = onReplay
        self.handleValue = handleValue
    }

    func handle(_ value: HAJSONValue) {
        handleValue(value)
    }
}


private actor SerialSender {
    private var pending: [String] = []
    private var isSending = false
    private let transport: HAWebSocketTransport
    private let encoder: JSONEncoder
    private var nextRequestID = 1

    init(transport: HAWebSocketTransport, encoder: JSONEncoder) {
        self.transport = transport
        self.encoder = encoder
    }

    func enqueue(
        _ messageObject: [String: HAJSONValue],
        onReserve: (Int) -> Void
    ) throws {
        let id = nextRequestID
        nextRequestID += 1
        
        onReserve(id)
        
        guard messageObject["type"] != nil else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }
        
        var object = messageObject
        object["id"] = .integer(id)
        let data = try encoder.encode(object)
        guard let outbound = String(data: data, encoding: .utf8) else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }

        pending.append(outbound)
        if !isSending {
            isSending = true
            Task {
                await drain()
            }
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let nextStr = pending.removeFirst()
            do {
                try await transport.send(nextStr)
            } catch {
                // If it fails, transport disconnected, receive loop will handle disconnect.
            }
        }
        isSending = false
    }
}

public final class HAWebSocketClient: HAWebSocketClientProtocol, HAWebSocketReconnectNotifying {
    public private(set) var connectionState: HAWebSocketConnectionState = .disconnected
    public var onReconnect: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedReconnectHandler
        }
        set {
            lock.lock()
            storedReconnectHandler = newValue
            lock.unlock()
        }
    }

    private let credentialProvider: CredentialProvider
    private let transport: HAWebSocketTransport
    private let sender: SerialSender
    private let logger: Logger?
    private let pingConfiguration: HAPingConfiguration?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<HAJSONValue, Error>] = [:]
    private var subscriptions: [Int: HAAnySubscriptionHandler] = [:]
    private var serverSubscriptionIDs: [Int: Int] = [:]
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = true
    private var hasConnectedSuccessfully = false
    private var storedReconnectHandler: (() -> Void)?
    private var storedRequestReservationObserver: ((Int) -> Void)?
    var requestReservationObserver: ((Int) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedRequestReservationObserver
        }
        set {
            lock.lock()
            storedRequestReservationObserver = newValue
            lock.unlock()
        }
    }

    public init(
        credentialProvider: CredentialProvider,
        transport: HAWebSocketTransport = URLSessionHAWebSocketTransport(),
        logger: Logger? = nil,
        pingConfiguration: HAPingConfiguration? = HAPingConfiguration()
    ) {
        self.credentialProvider = credentialProvider
        self.transport = transport
        let encoder = JSONEncoder()
        self.encoder = encoder
        self.decoder = JSONDecoder()
        self.sender = SerialSender(transport: transport, encoder: encoder)
        self.logger = logger
        self.pingConfiguration = pingConfiguration
    }

    public func connect() async throws {
        let isReconnect = hasConnectedSuccessfully
        shouldReconnect = true
        setConnectionState(.connecting)
        
        print("DEBUG: HAAuth(...)")
        let auth = try HAAuth(credentialProvider: credentialProvider)
        print("DEBUG: transport.connect()")
        try await transport.connect(url: auth.webSocketURL(), headers: [:])
        setConnectionState(.authenticating)
        print("DEBUG: authenticate(...)")
        try await authenticate(auth: auth)
        setConnectionState(.connected)
        print("DEBUG: startReceiveLoop()")
        startReceiveLoop()
        try await replaySubscriptions()
        startPingLoop()
        hasConnectedSuccessfully = true
        if isReconnect {
            reconnectHandler()?()
        }
        print("DEBUG: connect() finished")
    }

    public func disconnect() async {
        shouldReconnect = false
        receiveTask?.cancel()
        pingTask?.cancel()
        reconnectTask?.cancel()
        receiveTask = nil
        pingTask = nil
        reconnectTask = nil
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
        // DO NOT cancel reconnectTask here, as reconnect() may be called FROM reconnectTask.
        transport.disconnect()
        failAllPending(with: HAWebSocketClientError.disconnected)
        try await connect()
    }

    public func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T {
        let messageObject = try encodeMessageObject(message)
        let resultValue = try await sendRequest(messageObject)
        return try decode(T.self, from: resultValue)
    }

    public func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        let messageObject = try encodeMessageObject(message)
        return try await subscribe(
            buildMessageObject: { messageObject },
            onReplay: {},
            onEvent: onEvent
        )
    }

    public func subscribe<T: Decodable>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        return try await subscribe(
            buildMessageObject: {
                let data = try encoder.encode(buildMessage())
                return try decoder.decode([String: HAJSONValue].self, from: data)
            },
            onReplay: onReplay,
            onEvent: onEvent
        )
    }

    private func subscribe<T: Decodable>(
        buildMessageObject: @escaping () throws -> [String: HAJSONValue],
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        let messageObject = try buildMessageObject()
        var assignedID: Int?
        
        do {
            let ackValue = try await sendRequest(messageObject) { [self] id in
                assignedID = id
                registerSubscription(
                    logicalID: id,
                    serverID: id,
                    buildMessageObject: buildMessageObject,
                    onReplay: onReplay
                ) { [weak self] value in
                    guard let self = self else { return }
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
            }
            
            guard let id = assignedID else {
                throw HAWebSocketClientError.disconnected
            }
            
            let _: HAEmptyResponse = try decode(HAEmptyResponse.self, from: ackValue)
            return HASubscription(id: id) { [weak self] in
                self?.cancelSubscription(logicalID: id)
            }
        } catch {
            if let id = assignedID {
                cancelSubscription(logicalID: id)
            }
            throw error
        }
    }

    public func ping() async throws {
        let _: HAEmptyResponse = try await callWS(HAWebSocketRequest(type: "ping"))
    }

    private func authenticate(auth: HAAuth) async throws {
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
                        if let task = self.reconnectTask, !task.isCancelled {
                            task.cancel()
                        }
                        self.reconnectTask = Task { [weak self] in
                            await self?.retryReconnectUntilSuccessful()
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

    private func retryReconnectUntilSuccessful() async {
        var backoffSeconds: TimeInterval = 0.1
        let maxBackoffSeconds: TimeInterval = 30.0

        while !Task.isCancelled && self.shouldReconnect {
            do {
                try await self.reconnect(force: false)
                return
            } catch let HAWebSocketClientError.invalidAuth(message) {
                self.logger?.info("Home Assistant WebSocket auth invalid: \(message), refreshing credentials")
                do {
                    try await credentialProvider.refreshCredentials()
                    continue
                } catch {
                    self.logger?.warning("Home Assistant WebSocket failed to refresh credentials", metadata: ["error": String(describing: error)])
                }
                do {
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                } catch {
                    return
                }
                backoffSeconds = min(backoffSeconds * 2, maxBackoffSeconds)
            } catch {
                self.logger?.warning("Home Assistant WebSocket reconnect attempt failed, retrying in \(backoffSeconds)s", metadata: ["error": String(describing: error)])
                do {
                    try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                } catch {
                    return
                }
                backoffSeconds = min(backoffSeconds * 2, maxBackoffSeconds)
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

    private func sendRequest(
        _ messageObject: [String: HAJSONValue],
        onReserve: ((Int) -> Void)? = nil
    ) async throws -> HAJSONValue {
        let assignedID = AtomicID()
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HAJSONValue, Error>) in
                Task { [weak self] in
                    guard let self = self else { return }
                    if Task.isCancelled {
                        continuation.resume(throwing: HAWebSocketClientError.disconnected)
                        return
                    }
                    do {
                        try await self.sender.enqueue(messageObject) { id in
                            assignedID.set(id)
                            self.requestReservationObserver?(id)
                            onReserve?(id)
                            self.registerPendingRequest(id: id, continuation: continuation)
                        }
                    } catch {
                        if let id = assignedID.get() {
                            self.completePendingRequest(id: id, result: .failure(error))
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            if let id = assignedID.get() {
                self.completePendingRequest(id: id, result: .failure(HAWebSocketClientError.disconnected))
            }
        }
    }

    private func encodeMessageObject<Message: Encodable>(_ message: Message) throws -> [String: HAJSONValue] {
        let data = try encoder.encode(message)
        return try decoder.decode([String: HAJSONValue].self, from: data)
    }

    private func validatedMessageObject(
        _ messageObject: [String: HAJSONValue]
    ) throws -> [String: HAJSONValue] {
        guard messageObject["type"] != nil else {
            throw HAWebSocketClientError.invalidOutboundMessage
        }
        return messageObject
    }

    private func encodeOutboundMessage(_ messageObject: [String: HAJSONValue], id: Int) throws -> String {
        var object = messageObject
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
        let id = nextRequestID
        nextRequestID += 1
        let observer = storedRequestReservationObserver
        lock.unlock()
        observer?(id)
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

    private func hasPendingRequest(id: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingRequests[id] != nil
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

    private func registerSubscription(
        logicalID: Int,
        serverID: Int,
        buildMessageObject: @escaping () throws -> [String: HAJSONValue],
        onReplay: @escaping () -> Void,
        handler: @escaping (HAJSONValue) -> Void
    ) {
        lock.lock()
        subscriptions[logicalID] = HAAnySubscriptionHandler(
            buildMessageObject: buildMessageObject,
            onReplay: onReplay,
            handleValue: handler
        )
        serverSubscriptionIDs[serverID] = logicalID
        lock.unlock()
    }

    private func dispatchSubscriptionEvent(id: Int, event: HAJSONValue) {
        lock.lock()
        let handler = serverSubscriptionIDs[id].flatMap { subscriptions[$0] }
        lock.unlock()
        handler?.handle(event)
    }

    private func cancelSubscription(logicalID: Int) {
        lock.lock()
        let wasActive = subscriptions.removeValue(forKey: logicalID) != nil
        let serverIDs = serverSubscriptionIDs.compactMap { serverID, mappedLogicalID in
            mappedLogicalID == logicalID ? serverID : nil
        }
        serverSubscriptionIDs = serverSubscriptionIDs.filter { $0.value != logicalID }
        let shouldUnsubscribe = wasActive && connectionState == .connected
        lock.unlock()

        guard shouldUnsubscribe else {
            return
        }
        for serverID in serverIDs.sorted() {
            sendUnsubscribe(serverID: serverID)
        }
    }

    private func sendUnsubscribe(serverID: Int) {
        let message = HAWebSocketRequest(
            type: "unsubscribe_events",
            payload: ["subscription": .integer(serverID)]
        )

        Task { [self] in
            do {
                let messageObject = try encodeMessageObject(message)
                let value = try await sendRequest(messageObject)
                let _: HAEmptyResponse = try decode(HAEmptyResponse.self, from: value)
            } catch {
                logger?.debug(
                    "Home Assistant unsubscribe request did not complete",
                    metadata: [
                        "subscription": String(serverID),
                        "error": String(describing: error)
                    ]
                )
            }
        }
    }

    private func removeAllSubscriptions() {
        lock.lock()
        subscriptions.removeAll()
        serverSubscriptionIDs.removeAll()
        lock.unlock()
    }

    private func replaySubscriptions() async throws {
        lock.lock()
        let logicalIDs = Array(subscriptions.keys).sorted()
        serverSubscriptionIDs.removeAll()
        lock.unlock()

        for logicalID in logicalIDs {
            lock.lock()
            let handler = subscriptions[logicalID]
            lock.unlock()
            guard let handler = handler else {
                continue
            }

            handler.onReplay()
            let messageObject = try handler.buildMessageObject()

            let ackValue = try await sendRequest(messageObject) { [self] serverID in
                lock.lock()
                let isActive = subscriptions[logicalID] === handler
                if isActive {
                    serverSubscriptionIDs[serverID] = logicalID
                }
                lock.unlock()
            }
            
            lock.lock()
            let isActive = subscriptions[logicalID] === handler
            lock.unlock()

            guard isActive else {
                continue
            }

            let _: HAEmptyResponse = try decode(HAEmptyResponse.self, from: ackValue)
        }
    }

    private func reconnectHandler() -> (() -> Void)? {
        onReconnect
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
