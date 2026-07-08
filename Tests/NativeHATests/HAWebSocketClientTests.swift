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

    func connect(url: URL, headers: [String: String]) async throws {
        lock.lock()
        connectedURL = url
        lock.unlock()
    }

    func send(_ string: String) async throws {
        lock.lock()
        sent.append(string)
        lock.unlock()
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
}
