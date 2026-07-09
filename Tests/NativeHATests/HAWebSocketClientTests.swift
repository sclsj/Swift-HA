import XCTest
@testable import NativeHACore

final class HAWebSocketClientTests: XCTestCase {
    func testAuthBuildsWebSocketURLFromHTTPServerURL() throws {
        let auth = HAAuth(credentials: HomeAssistantCredentials(
            serverURL: URL(string: "http://homeassistant.local:8123")!,
            accessToken: "token"
        ))

        XCTAssertEqual(try auth.webSocketURL().absoluteString, "ws://homeassistant.local:8123/api/websocket")
    }

    func testCallWSRoutesOutOfOrderResultsByRequestID() async throws {
        let (client, transport) = try await makeConnectedClient()

        let firstTask = Task { () -> HAConfig in
            try await client.callWS(HAWebSocketRequest(type: "get_config"))
        }
        try await waitForSentCount(2, transport: transport)
        let firstRequest = try transport.sentObject(at: 1)
        let firstID = try XCTUnwrap(firstRequest["id"]?.integerValue)

        let secondTask = Task { () -> HAPanels in
            try await client.callWS(HAWebSocketRequest(type: "get_panels"))
        }
        try await waitForSentCount(3, transport: transport)
        let secondRequest = try transport.sentObject(at: 2)
        let secondID = try XCTUnwrap(secondRequest["id"]?.integerValue)

        XCTAssertEqual(firstRequest["type"], .string("get_config"))
        XCTAssertEqual(secondRequest["type"], .string("get_panels"))
        XCTAssertNotEqual(firstID, secondID)

        transport.enqueue("""
        {"id":\(secondID),"type":"result","success":true,"result":{"lovelace":{"component_name":"lovelace","config":{"mode":"storage"},"icon":"mdi:view-dashboard","title":"Overview","url_path":"lovelace","show_in_sidebar":true}}}
        """)
        transport.enqueue("""
        {"id":\(firstID),"type":"result","success":true,"result":{"latitude":1.0,"longitude":2.0,"elevation":3,"location_name":"Home","time_zone":"UTC","unit_system":{"temperature":"C"},"version":"2026.5.4","components":["lovelace"],"safe_mode":false}}
        """)

        let second = try await secondTask.value
        let first = try await firstTask.value

        XCTAssertEqual(first.locationName, "Home")
        XCTAssertEqual(second["lovelace"]?.componentName, "lovelace")

        await client.disconnect()
    }

    func testSubscribeRoutesEventsToMatchingCallback() async throws {
        let (client, transport) = try await makeConnectedClient()
        let callback = expectation(description: "subscription callback")
        let receivedEntity = LockedValue<String?>(nil)

        let subscriptionTask = Task { () -> HASubscription in
            try await client.subscribe(
                HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("state_changed")])
            ) { (event: HAEvent<HAStateChangedEventData>) in
                receivedEntity.set(event.data.entityID)
                callback.fulfill()
            }
        }

        try await waitForSentCount(2, transport: transport)
        let subscribeRequest = try transport.sentObject(at: 1)
        let subscriptionID = try XCTUnwrap(subscribeRequest["id"]?.integerValue)
        XCTAssertEqual(subscribeRequest["type"], .string("subscribe_events"))
        XCTAssertEqual(subscribeRequest["event_type"], .string("state_changed"))

        transport.enqueue("""
        {"id":\(subscriptionID),"type":"result","success":true,"result":null}
        """)
        let subscription = try await subscriptionTask.value

        transport.enqueue("""
        {"id":\(subscriptionID),"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"sensor.temperature","old_state":null,"new_state":{"entity_id":"sensor.temperature","state":"23.4","attributes":{"friendly_name":"Temperature"},"last_changed":"2026-07-06T00:00:00.000000+00:00","last_updated":"2026-07-06T00:00:00.000000+00:00","last_reported":"2026-07-06T00:00:00.000000+00:00","context":{"id":"ctx","parent_id":null,"user_id":null}}},"origin":"LOCAL","time_fired":"2026-07-06T00:00:00.000000+00:00","context":{"id":"ctx","parent_id":null,"user_id":null}}}
        """)

        wait(for: [callback], timeout: 1.0)
        XCTAssertEqual(receivedEntity.value(), "sensor.temperature")

        subscription.cancel()
        await client.disconnect()
    }

    func testActiveSubscriptionCancellationSendsUnsubscribeWithServerIDAndIsIdempotent() async throws {
        let (client, transport) = try await makeConnectedClient()
        let subscriptionTask = Task { () -> HASubscription in
            try await client.subscribe(
                HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("test_event")])
            ) { (_: HAJSONValue) in }
        }

        try await waitForNumberedRequestCount(1, transport: transport)
        let subscriptionID = try XCTUnwrap(transport.numberedSentObjects()[0]["id"]?.integerValue)
        transport.enqueue(resultMessage(id: subscriptionID))
        let subscription = try await subscriptionTask.value

        subscription.cancel()
        subscription.cancel()

        try await waitForNumberedRequestCount(2, transport: transport)
        let unsubscribe = try transport.numberedSentObjects()[1]
        XCTAssertEqual(unsubscribe["type"], .string("unsubscribe_events"))
        XCTAssertEqual(unsubscribe["subscription"]?.integerValue, subscriptionID)
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertEqual(try transport.numberedSentObjects().count, 2)

        let unsubscribeID = try XCTUnwrap(unsubscribe["id"]?.integerValue)
        transport.enqueue(resultMessage(id: unsubscribeID))
        await client.disconnect()
    }

    func testCancellationBeforeSubscribeResultDoesNotLeakServerSubscription() async throws {
        let (client, transport) = try await makeConnectedClient()
        let subscriptionTask = Task { () -> HASubscription in
            try await client.subscribe(
                HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("test_event")])
            ) { (_: HAJSONValue) in }
        }

        try await waitForNumberedRequestCount(1, transport: transport)
        let subscriptionID = try XCTUnwrap(transport.numberedSentObjects()[0]["id"]?.integerValue)
        subscriptionTask.cancel()

        try await waitForNumberedRequestCount(2, transport: transport)
        let unsubscribe = try transport.numberedSentObjects()[1]
        XCTAssertEqual(unsubscribe["type"], .string("unsubscribe_events"))
        XCTAssertEqual(unsubscribe["subscription"]?.integerValue, subscriptionID)

        transport.enqueue(resultMessage(id: subscriptionID))
        let unsubscribeID = try XCTUnwrap(unsubscribe["id"]?.integerValue)
        transport.enqueue(resultMessage(id: unsubscribeID))
        guard case .failure = await subscriptionTask.result else {
            return XCTFail("Expected the cancelled subscription setup to fail.")
        }

        await client.disconnect()
    }

    func testReconnectReplaysActiveSubscriptionWithFreshServerIDOnce() async throws {
        let (client, transport) = try await makeConnectedClient()
        let callback = expectation(description: "replayed subscription callback")
        let receivedValues = LockedValue<[String]>([])

        let subscriptionTask = Task { () -> HASubscription in
            try await client.subscribe(
                HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("test_event")])
            ) { (event: HAJSONValue) in
                if let value = event.objectValue?["value"]?.stringValue {
                    receivedValues.mutate { $0.append(value) }
                    callback.fulfill()
                }
            }
        }

        try await waitForNumberedRequestCount(1, transport: transport)
        let initialRequest = try XCTUnwrap(transport.numberedSentObjects().first)
        let initialID = try XCTUnwrap(initialRequest["id"]?.integerValue)
        transport.enqueue(resultMessage(id: initialID))
        let subscription = try await subscriptionTask.value

        let reconnectCallback = expectation(description: "reconnect callback")
        client.onReconnect = {
            reconnectCallback.fulfill()
        }
        transport.queueAuthenticationForNextConnection()
        let reconnectTask = Task {
            try await client.reconnect()
        }

        try await waitForNumberedRequestCount(2, transport: transport)
        let replayRequest = try transport.numberedSentObjects()[1]
        let replayID = try XCTUnwrap(replayRequest["id"]?.integerValue)
        XCTAssertGreaterThan(replayID, initialID)
        XCTAssertEqual(replayRequest["event_type"], .string("test_event"))
        transport.enqueue(resultMessage(id: replayID))
        try await reconnectTask.value
        wait(for: [reconnectCallback], timeout: 1.0)

        transport.enqueue("""
        {"id":\(initialID),"type":"event","event":{"value":"stale"}}
        """)
        transport.enqueue("""
        {"id":\(replayID),"type":"event","event":{"value":"fresh"}}
        """)

        wait(for: [callback], timeout: 1.0)
        XCTAssertEqual(receivedValues.value(), ["fresh"])

        let beforeCancelCount = try transport.numberedSentObjects().count
        subscription.cancel()

        try await waitForNumberedRequestCount(beforeCancelCount + 1, transport: transport)
        let unsubscribe = try transport.numberedSentObjects()[beforeCancelCount]
        XCTAssertEqual(unsubscribe["type"], .string("unsubscribe_events"))
        XCTAssertEqual(unsubscribe["subscription"]?.integerValue, replayID)

        await client.disconnect()
    }

    func testCancelledSubscriptionIsNotReplayed() async throws {
        let (client, transport) = try await makeConnectedClient()
        let subscriptionTask = Task { () -> HASubscription in
            try await client.subscribe(
                HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("test_event")])
            ) { (_: HAJSONValue) in }
        }

        try await waitForNumberedRequestCount(1, transport: transport)
        let initialID = try XCTUnwrap(transport.numberedSentObjects()[0]["id"]?.integerValue)
        transport.enqueue(resultMessage(id: initialID))
        let subscription = try await subscriptionTask.value
        subscription.cancel()
        try await waitForNumberedRequestCount(2, transport: transport)
        let unsubscribe = try transport.numberedSentObjects()[1]
        XCTAssertEqual(unsubscribe["subscription"]?.integerValue, initialID)
        transport.enqueue(resultMessage(id: try XCTUnwrap(unsubscribe["id"]?.integerValue)))

        transport.queueAuthenticationForNextConnection()
        try await client.reconnect()

        XCTAssertEqual(try transport.numberedSentObjects().count, 2)
        await client.disconnect()
    }

    func testOutboundEncodingFailureDoesNotWedgeLaterRequestOrdering() async throws {
        let (client, transport) = try await makeConnectedClient()
        let firstReserved = expectation(description: "invalid request reserved")
        let secondReserved = expectation(description: "valid request reserved")
        client.requestReservationObserver = { id in
            if id == 1 {
                firstReserved.fulfill()
            } else if id == 2 {
                secondReserved.fulfill()
            }
        }

        do {
            let _: HAEmptyResponse = try await client.callWS(MissingTypeRequest(value: "invalid"))
            XCTFail("Expected outbound encoding to reject a request without a type.")
        } catch HAWebSocketClientError.invalidOutboundMessage {
            // Expected.
        }
        wait(for: [firstReserved], timeout: 1.0)

        let validTask = Task { () -> HAEmptyResponse in
            try await client.callWS(HAWebSocketRequest(type: "valid_request"))
        }
        wait(for: [secondReserved], timeout: 1.0)
        try await waitForNumberedRequestCount(1, transport: transport)

        let validRequest = try transport.numberedSentObjects()[0]
        XCTAssertEqual(validRequest["id"]?.integerValue, 2)
        XCTAssertEqual(validRequest["type"], .string("valid_request"))
        transport.enqueue(resultMessage(id: 2))
        _ = try await validTask.value

        await client.disconnect()
    }

    func testCancelledLaterRequestDoesNotAdvanceSendOrderPastEarlierRequests() async throws {
        let (client, transport) = try await makeConnectedClient()
        transport.blockSends(types: ["request_1", "request_2", "request_3", "request_4"])

        let reserved1 = expectation(description: "request 1 reserved")
        let reserved2 = expectation(description: "request 2 reserved")
        let reserved3 = expectation(description: "request 3 reserved")
        let reserved4 = expectation(description: "request 4 reserved")
        client.requestReservationObserver = { id in
            switch id {
            case 1: reserved1.fulfill()
            case 2: reserved2.fulfill()
            case 3: reserved3.fulfill()
            case 4: reserved4.fulfill()
            default: break
            }
        }

        let first = Task { () -> HAEmptyResponse in
            try await client.callWS(HAWebSocketRequest(type: "request_1"))
        }
        wait(for: [reserved1], timeout: 1.0)
        try await waitForNumberedRequestCount(1, transport: transport)

        let second = Task { () -> HAEmptyResponse in
            try await client.callWS(HAWebSocketRequest(type: "request_2"))
        }
        wait(for: [reserved2], timeout: 1.0)
        let third = Task { () -> HAEmptyResponse in
            try await client.callWS(HAWebSocketRequest(type: "request_3"))
        }
        wait(for: [reserved3], timeout: 1.0)
        third.cancel()

        let fourth = Task { () -> HAEmptyResponse in
            try await client.callWS(HAWebSocketRequest(type: "request_4"))
        }
        wait(for: [reserved4], timeout: 1.0)
        XCTAssertEqual(try transport.numberedSentObjects().compactMap { $0["id"]?.integerValue }, [1])

        XCTAssertTrue(transport.releaseNextSend(type: "request_1"))
        try await waitForNumberedRequestCount(2, transport: transport)
        XCTAssertEqual(try transport.numberedSentObjects().compactMap { $0["id"]?.integerValue }, [1, 2])
        transport.enqueue(resultMessage(id: 1))

        XCTAssertTrue(transport.releaseNextSend(type: "request_2"))
        try await waitForNumberedRequestCount(3, transport: transport)
        XCTAssertEqual(try transport.numberedSentObjects().compactMap { $0["id"]?.integerValue }, [1, 2, 4])
        transport.enqueue(resultMessage(id: 2))

        XCTAssertTrue(transport.releaseNextSend(type: "request_4"))
        transport.enqueue(resultMessage(id: 4))

        _ = try await first.value
        _ = try await second.value
        _ = try await fourth.value
        guard case .failure = await third.result else {
            return XCTFail("Expected the cancelled third request to fail.")
        }

        await client.disconnect()
    }

    func testHAConnectionReconnectObserverIsCalledAndCanBeCancelled() async throws {
        let client = MockReconnectClient()
        let connection = HAConnection(client: client)

        let observerCalled = LockedValue<Int>(0)
        let observation = connection.subscribeReconnects {
            observerCalled.mutate { $0 += 1 }
        }

        do {
            try await connection.connect()
        } catch {}

        client.onReconnect?()
        XCTAssertEqual(observerCalled.value(), 1)

        observation.cancel()

        client.onReconnect?()
        XCTAssertEqual(observerCalled.value(), 1)
    }

    private func makeConnectedClient() async throws -> (HAWebSocketClient, MockWebSocketTransport) {
        let transport = MockWebSocketTransport()
        transport.enqueue("""
        {"type":"auth_required","ha_version":"2026.5.4"}
        """)
        transport.enqueue("""
        {"type":"auth_ok","ha_version":"2026.5.4"}
        """)
        let client = HAWebSocketClient(
            auth: HAAuth(credentials: HomeAssistantCredentials(
                serverURL: URL(string: "http://homeassistant.local:8123")!,
                accessToken: "test-token"
            )),
            transport: transport,
            pingConfiguration: nil
        )
        try await client.connect()
        try await waitForSentCount(1, transport: transport)
        return (client, transport)
    }

    private func waitForSentCount(_ count: Int, transport: MockWebSocketTransport) async throws {
        for _ in 0..<100 {
            if transport.sentMessages().count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected at least \(count) sent WebSocket messages.")
        throw HAWebSocketClientError.timedOut
    }

    private func waitForNumberedRequestCount(_ count: Int, transport: MockWebSocketTransport) async throws {
        for _ in 0..<100 {
            if try transport.numberedSentObjects().count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected at least \(count) numbered WebSocket requests.")
        throw HAWebSocketClientError.timedOut
    }

    private func resultMessage(id: Int) -> String {
        """
        {"id":\(id),"type":"result","success":true,"result":null}
        """
    }
}

private struct MissingTypeRequest: Encodable {
    var value: String
}

private extension HAJSONValue {
    var integerValue: Int? {
        switch self {
        case let .integer(value):
            return value
        case let .double(value):
            return Int(value)
        default:
            return nil
        }
    }
}

private final class MockWebSocketTransport: HAWebSocketTransport {
    private let lock = NSLock()
    private var sent: [String] = []
    private var queuedMessages: [Result<HAWebSocketTransportMessage, Error>] = []
    private var receivers: [CheckedContinuation<HAWebSocketTransportMessage, Error>] = []
    private var connectedURL: URL?
    private var nextConnectionMessages: [String] = []
    private var blockedSendTypes: Set<String> = []
    private var blockedSendContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]

    func connect(url: URL, headers: [String: String]) async throws {
        lock.lock()
        connectedURL = url
        let connectionMessages = nextConnectionMessages
        nextConnectionMessages.removeAll()
        lock.unlock()
        for message in connectionMessages {
            deliver(.success(.string(message)))
        }
    }

    func send(_ string: String) async throws {
        let type = try? JSONDecoder()
            .decode([String: HAJSONValue].self, from: Data(string.utf8))["type"]?
            .stringValue

        lock.lock()
        let shouldBlock = type.map { blockedSendTypes.contains($0) } ?? false
        lock.unlock()

        if let type = type, shouldBlock {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                sent.append(string)
                blockedSendContinuations[type, default: []].append(continuation)
                lock.unlock()
            }
        } else {
            lock.lock()
            sent.append(string)
            lock.unlock()
        }
    }

    func receive() async throws -> HAWebSocketTransportMessage {
        lock.lock()
        if !queuedMessages.isEmpty {
            let result = queuedMessages.removeFirst()
            lock.unlock()
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            receivers.append(continuation)
            lock.unlock()
        }
    }

    func disconnect() {
        lock.lock()
        let pending = receivers
        receivers.removeAll()
        lock.unlock()

        for receiver in pending {
            receiver.resume(throwing: HAWebSocketClientError.disconnected)
        }
    }

    func enqueue(_ text: String) {
        deliver(.success(.string(text)))
    }

    func sentMessages() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    func sentObject(at index: Int) throws -> [String: HAJSONValue] {
        let messages = sentMessages()
        let data = try XCTUnwrap(messages[index].data(using: .utf8))
        return try JSONDecoder().decode([String: HAJSONValue].self, from: data)
    }

    func numberedSentObjects() throws -> [[String: HAJSONValue]] {
        try sentMessages().compactMap { message in
            let object = try JSONDecoder().decode([String: HAJSONValue].self, from: Data(message.utf8))
            return object["id"] == nil ? nil : object
        }
    }

    func queueAuthenticationForNextConnection() {
        lock.lock()
        nextConnectionMessages = [
            #"{"type":"auth_required","ha_version":"2026.5.4"}"#,
            #"{"type":"auth_ok","ha_version":"2026.5.4"}"#
        ]
        lock.unlock()
    }

    func blockSends(types: Set<String>) {
        lock.lock()
        blockedSendTypes.formUnion(types)
        lock.unlock()
    }

    func releaseNextSend(type: String) -> Bool {
        lock.lock()
        guard var continuations = blockedSendContinuations[type], !continuations.isEmpty else {
            lock.unlock()
            return false
        }
        let continuation = continuations.removeFirst()
        blockedSendContinuations[type] = continuations
        lock.unlock()
        continuation.resume()
        return true
    }

    private func deliver(_ result: Result<HAWebSocketTransportMessage, Error>) {
        lock.lock()
        if !receivers.isEmpty {
            let receiver = receivers.removeFirst()
            lock.unlock()
            receiver.resume(with: result)
        } else {
            queuedMessages.append(result)
            lock.unlock()
        }
    }
}

private final class LockedValue<Value> {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func value() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mutate(_ mutation: (inout Value) -> Void) {
        lock.lock()
        mutation(&storage)
        lock.unlock()
    }
}

private final class MockReconnectClient: HAWebSocketClientProtocol, HAWebSocketReconnectNotifying {
    var onReconnect: (() -> Void)?

    struct IntentionalError: Error {}

    func connect() async throws { throw IntentionalError() }
    func disconnect() async {}

    func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T {
        throw IntentionalError()
    }

    func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        throw IntentionalError()
    }

    func subscribe<T: Decodable>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        throw IntentionalError()
    }
}
