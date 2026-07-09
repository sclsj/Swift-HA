import XCTest
@testable import NativeHACore

final class HAConnectionTests: XCTestCase {
    func testReconnectObserverCancellationIsIdempotent() async throws {
        let connection = HAConnection(client: MockClient())
        try await connection.connect()
        let observerCalled = LockedValue<Int>(0)
        let observation = connection.subscribeReconnects {
            observerCalled.mutate { $0 += 1 }
        }

        (connection.client as? MockClient)?.triggerReconnect()
        XCTAssertEqual(observerCalled.value(), 1)

        observation.cancel()
        observation.cancel() // Idempotent

        (connection.client as? MockClient)?.triggerReconnect()
        XCTAssertEqual(observerCalled.value(), 1) // Should not increment
    }

    func testReconnectObserverDoesNotHoldLockWhileInvokingCallbacks() async throws {
        let connection = HAConnection(client: MockClient())
        try await connection.connect()
        let observerAdded = LockedValue<Bool>(false)
        
        let subscription = connection.subscribeReconnects {
            // If the lock is held, adding another observer here will deadlock
            let _ = connection.subscribeReconnects { }
            observerAdded.set(true)
        }
        
        let mockClient = try XCTUnwrap(connection.client as? MockClient)
        mockClient.triggerReconnect()
        
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(observerAdded.value())
    }

    func testStateChangedEventUpdatesStateStoreOnMainActor() async throws {
        let client = MockClient()
        let connection = HAConnection(client: client)
        
        try await connection.connect()
        
        let json = """
        {
            "event_type": "state_changed",
            "data": {
                "entity_id": "sensor.test",
                "old_state": null,
                "new_state": {
                    "entity_id": "sensor.test",
                    "state": "on",
                    "attributes": {},
                    "last_changed": "2026-07-06T00:00:00+00:00",
                    "last_updated": "2026-07-06T00:00:00+00:00",
                    "context": {"id": "c1", "parent_id": null, "user_id": null}
                }
            },
            "origin": "LOCAL",
            "time_fired": "2026-07-06T00:00:00+00:00",
            "context": {"id": "c1", "parent_id": null, "user_id": null}
        }
        """
        
        client.triggerEventJSON(json, forType: "state_changed")
        
        // Let main actor process
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let state = await MainActor.run { connection.stateStore.states["sensor.test"] }
        XCTAssertEqual(state?.state, "on")
    }

    func testRegistryUpdateEventsTriggerRefresh() async throws {
        let client = MockClient()
        let connection = HAConnection(client: client)
        
        try await connection.connect()
        
        _ = client.getAndResetCallCount("config/entity_registry/list")
        
        let json = """
        {
            "event_type": "entity_registry_updated",
            "data": {"action": "create"},
            "origin": "LOCAL",
            "time_fired": "2026-07-06T00:00:00+00:00",
            "context": {"id": "c1", "parent_id": null, "user_id": null}
        }
        """
        
        client.triggerEventJSON(json, forType: "entity_registry_updated")
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let refreshCalls = client.getAndResetCallCount("config/entity_registry/list")
        XCTAssertGreaterThan(refreshCalls, 0)
    }

    func testServiceCallMappingForSupportedDomainsDoesNotRegress() async throws {
        let client = MockClient()
        let connection = HAConnection(client: client)
        
        try await connection.connect()
        
        XCTAssertNotNil(connection.serviceClient)
        
        // Ensure known domains are handled correctly
        let serviceClient = try XCTUnwrap(connection.serviceClient)
        
        _ = try? await serviceClient.callService(domain: "light", service: "turn_on", target: HAServiceTarget(entityIDs: ["light.test"]))
        
        let calls = client.getCalls("call_service")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?["domain"], .string("light"))
        XCTAssertEqual(calls.first?["service"], .string("turn_on"))
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

private final class MockClient: HAWebSocketClientProtocol, HAWebSocketReconnectNotifying {
    var onReconnect: (() -> Void)?
    
    private let lock = NSLock()
    private var subscribers: [String: (String) -> Void] = [:]
    private var callCounts: [String: Int] = [:]
    private var serviceCalls: [[String: HAJSONValue]] = []

    func connect() async throws {}
    func disconnect() async {}

    func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T {
        let json = try! JSONEncoder().encode(message)
        let dict = try! JSONDecoder().decode([String: HAJSONValue].self, from: json)
        let type = dict["type"]?.stringValue ?? ""
        
        lock.lock()
        callCounts[type, default: 0] += 1
        if type == "call_service" {
            serviceCalls.append(dict)
            let json = """
            {"context": {"id": "c1", "parent_id": null, "user_id": null}}
            """
            do {
                let result = try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
                lock.unlock()
                return result
            } catch { 
                lock.unlock()
                print("DECODE ERROR call_service: \(error)")
                throw error 
            }
        }
        lock.unlock()

        if type == "get_states" || type == "config/entity_registry/list" || type == "config/device_registry/list" || type == "config/area_registry/list" || type == "config/floor_registry/list" {
            let emptyArray = try JSONEncoder().encode([String]())
            do {
                return try JSONDecoder().decode(T.self, from: emptyArray)
            } catch { print("DECODE ERROR \(type): \(error)"); throw error }
        }
        
        if type == "config/entity_registry/list_for_display" {
            let json = """
            {"entities": [], "entity_categories": {}}
            """
            do {
                return try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
            } catch { print("DECODE ERROR \(type): \(error)"); throw error }
        }
        
        if type == "get_config" {
            let json = """
            {"latitude":0,"longitude":0,"elevation":0,"location_name":"Home","time_zone":"UTC","unit_system":{},"version":"1.0","components":[],"safe_mode":false}
            """
            do {
                return try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
            } catch { print("DECODE ERROR get_config: \(error)"); throw error }
        }
        
        if type == "auth/current_user" {
            let json = """
            {"id":"u1","is_owner":true,"is_admin":true,"name":"User"}
            """
            do {
                return try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
            } catch { print("DECODE ERROR auth/current_user: \(error)"); throw error }
        }
        
        let emptyDict = try JSONEncoder().encode([String: String]())
        do {
            return try JSONDecoder().decode(T.self, from: emptyDict)
        } catch { print("DECODE ERROR \(type): \(error)"); throw error }
    }

    func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        let json = try! JSONEncoder().encode(message)
        let dict = try! JSONDecoder().decode([String: HAJSONValue].self, from: json)
        let eventType = dict["event_type"]?.stringValue ?? ""
        
        lock.lock()
        subscribers[eventType] = { jsonString in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: string) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            let event = try! decoder.decode(T.self, from: jsonString.data(using: .utf8)!)
            onEvent(event)
        }
        lock.unlock()
        
        return HASubscription(id: 1, cancellationHandler: {})
    }

    func subscribe<T: Decodable>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        try await subscribe(buildMessage(), onEvent: onEvent)
    }
    
    func triggerReconnect() {
        onReconnect?()
    }
    
    func triggerEventJSON(_ json: String, forType type: String) {
        lock.lock()
        let sub = subscribers[type]
        lock.unlock()
        
        if let sub = sub {
            sub(json)
        }
    }
    
    func getAndResetCallCount(_ type: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = callCounts[type] ?? 0
        callCounts[type] = 0
        return count
    }
    
    func getCalls(_ type: String) -> [[String: HAJSONValue]] {
        lock.lock()
        defer { lock.unlock() }
        return type == "call_service" ? serviceCalls : []
    }
}
