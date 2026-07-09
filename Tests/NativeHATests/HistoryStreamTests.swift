import XCTest
@testable import NativeHACore

final class HistoryStreamTests: XCTestCase {
    func testTimeWindowSubscriptionRebuildsWindowAndStreamOnReplay() async throws {
        let client = ReplayCapturingWebSocketClient()
        let now = LockedDate(Date(timeIntervalSince1970: 10_000))
        let received = LockedHistoryValues()
        let api = HistoryAPI(client: client)

        let subscription = try await api.subscribeHistoryStatesTimeWindow(
            hoursToShow: 1,
            entityIDs: ["sensor.power"],
            now: { now.value }
        ) { history in
            received.append(history)
        }

        XCTAssertEqual(client.builtMessages.count, 1)
        XCTAssertEqual(
            client.builtMessages[0].payload["start_time"],
            .string(HAHistoryDateCoding.isoString(from: Date(timeIntervalSince1970: 6_400)))
        )

        client.emit(HistoryStreamMessage(states: [
            "sensor.power": [historyState("old-window", lu: 9_000)]
        ]))
        XCTAssertEqual(received.last?["sensor.power"]?.map(\.state), ["old-window"])

        now.value = Date(timeIntervalSince1970: 20_000)
        client.replay()
        XCTAssertEqual(client.builtMessages.count, 2)
        XCTAssertEqual(
            client.builtMessages[1].payload["start_time"],
            .string(HAHistoryDateCoding.isoString(from: Date(timeIntervalSince1970: 16_400)))
        )

        client.emit(HistoryStreamMessage(states: [
            "sensor.power": [historyState("new-window", lu: 19_000)]
        ]))
        XCTAssertEqual(received.last?["sensor.power"]?.map(\.state), ["new-window"])

        subscription.cancel()
    }

    func testProcessMessageInitializesKeepsEmptyMessagesAndMergesIncrementalUpdates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let stream = HistoryStream(hoursToShow: 1, now: { now })

        let initial = stream.processMessage(HistoryStreamMessage(states: [
            "sensor.power_a": [
                historyState("old-a", lu: 6_000, lc: 5_900),
                historyState("current-a", lu: 7_000)
            ],
            "sensor.power_b": [
                historyState("old-b", lu: 6_200, lc: 6_100),
                historyState("current-b", lu: 6_600)
            ]
        ]))
        XCTAssertEqual(initial["sensor.power_a"]?.map(\.state), ["old-a", "current-a"])

        let afterEmpty = stream.processMessage(HistoryStreamMessage(states: [:]))
        XCTAssertEqual(afterEmpty["sensor.power_a"]?.map(\.state), ["old-a", "current-a"])
        XCTAssertEqual(afterEmpty["sensor.power_b"]?.map(\.state), ["old-b", "current-b"])

        let incremental = stream.processMessage(HistoryStreamMessage(states: [
            "sensor.power_a": [
                historyState("late-arriving-a", lu: 6_500),
                historyState("new-a", lu: 8_000)
            ],
            "sensor.power_c": [
                historyState("brand-new-old-c", lu: 100),
                historyState("brand-new-c", lu: 9_000)
            ]
        ]))

        XCTAssertEqual(
            incremental["sensor.power_a"]?.map(\.state),
            ["old-a", "late-arriving-a", "current-a", "new-a"]
        )
        XCTAssertEqual(incremental["sensor.power_a"]?.first?.lastUpdated, 6_400)
        XCTAssertNil(incremental["sensor.power_a"]?.first?.lastChanged)
        XCTAssertEqual(incremental["sensor.power_b"]?.map(\.state), ["old-b", "current-b"])
        XCTAssertEqual(incremental["sensor.power_b"]?.first?.lastUpdated, 6_400)

        // Matches the TypeScript stream-only branch: a brand-new entity is not
        // purged until it has been part of combined history for a later update.
        XCTAssertEqual(incremental["sensor.power_c"]?.first?.lastUpdated, 100)
    }

    func testBoundaryStateDeletesLastChangedWhenPruningExpiredHistory() {
        let now = Date(timeIntervalSince1970: 20_000)
        let purgeBefore = now.timeIntervalSince1970 - 3_600
        let stream = HistoryStream(
            hoursToShow: 1,
            combinedHistory: [
                "sensor.power": [
                    historyState("500", lu: purgeBefore - 10, lc: purgeBefore - 3_600),
                    historyState("500", lu: purgeBefore + 100)
                ]
            ],
            now: { now }
        )

        let result = stream.processMessage(HistoryStreamMessage(states: [
            "sensor.power": [historyState("510", lu: purgeBefore + 200)]
        ]))

        let boundaryState = result["sensor.power"]?.first
        XCTAssertEqual(boundaryState?.state, "500")
        XCTAssertEqual(boundaryState?.lastUpdated, purgeBefore)
        XCTAssertNil(boundaryState?.lastChanged)
    }

    func testPruneDoesNotRewriteStatesWhenNothingIsExpired() {
        let now = Date(timeIntervalSince1970: 30_000)
        let purgeBefore = now.timeIntervalSince1970 - 3_600
        let stream = HistoryStream(
            hoursToShow: 1,
            combinedHistory: [
                "sensor.power": [
                    historyState("500", lu: purgeBefore + 100, lc: purgeBefore + 50)
                ]
            ],
            now: { now }
        )

        let result = stream.processMessage(HistoryStreamMessage(states: [
            "sensor.power": [historyState("510", lu: purgeBefore + 200)]
        ]))

        XCTAssertEqual(result["sensor.power"]?.first?.lastUpdated, purgeBefore + 100)
        XCTAssertEqual(result["sensor.power"]?.first?.lastChanged, purgeBefore + 50)
    }
}

private final class ReplayCapturingWebSocketClient: HAWebSocketClientProtocol {
    private var buildMessage: (() -> HAWebSocketRequest)?
    private var replayHandler: (() -> Void)?
    private var eventHandler: ((HistoryStreamMessage) -> Void)?
    private(set) var builtMessages: [HAWebSocketRequest] = []

    func connect() async throws {}
    func disconnect() async {}

    func callWS<T, Message>(_ message: Message) async throws -> T where T: Decodable, Message: Encodable {
        throw HAWebSocketClientError.disconnected
    }

    func subscribe<T, Message>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription where T: Decodable, Message: Encodable {
        throw HAWebSocketClientError.disconnected
    }

    func subscribe<T>(
        buildMessage: @escaping () -> HAWebSocketRequest,
        onReplay: @escaping () -> Void,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription where T: Decodable {
        self.buildMessage = buildMessage
        self.replayHandler = onReplay
        self.eventHandler = { message in
            onEvent(message as! T)
        }
        builtMessages.append(buildMessage())
        return HASubscription(id: 1) {}
    }

    func replay() {
        replayHandler?()
        if let buildMessage = buildMessage {
            builtMessages.append(buildMessage())
        }
    }

    func emit(_ message: HistoryStreamMessage) {
        eventHandler?(message)
    }
}

private final class LockedDate {
    private let lock = NSLock()
    private var storage: Date

    init(_ value: Date) {
        storage = value
    }

    var value: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private final class LockedHistoryValues {
    private let lock = NSLock()
    private var values: [HistoryStates] = []

    var last: HistoryStates? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    func append(_ value: HistoryStates) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private func historyState(
    _ state: String,
    attributes: [String: HAJSONValue] = [:],
    lu: Double,
    lc: Double? = nil
) -> EntityHistoryState {
    EntityHistoryState(state: state, attributes: attributes, lastChanged: lc, lastUpdated: lu)
}
