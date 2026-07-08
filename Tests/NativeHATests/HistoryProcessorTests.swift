import XCTest
@testable import NativeHACore

final class HistoryProcessorTests: XCTestCase {
    func testComputeHistoryClassifiesGroupsAndDeduplicatesLineAndTimelineData() {
        let context = HistoryProcessingContext(states: [
            "sensor.power": makeEntity(
                entityID: "sensor.power",
                state: "15",
                attributes: [
                    "friendly_name": .string("Power"),
                    "unit_of_measurement": .string("W"),
                    "device_class": .string("power"),
                    "state_class": .string("measurement")
                ]
            ),
            "binary_sensor.motion": makeEntity(
                entityID: "binary_sensor.motion",
                state: "off",
                attributes: [
                    "friendly_name": .string("Motion"),
                    "device_class": .string("motion")
                ]
            )
        ])

        let result = HistoryProcessor.computeHistory(
            stateHistory: [
                "sensor.power": [
                    processorState("10", attributes: [
                        "friendly_name": .string("Power"),
                        "unit_of_measurement": .string("W"),
                        "device_class": .string("power"),
                        "state_class": .string("measurement")
                    ], lu: 100),
                    processorState("10", lu: 120, lc: 100),
                    processorState("10", lu: 140, lc: 100),
                    processorState("15", lu: 160)
                ],
                "binary_sensor.motion": [
                    processorState("on", attributes: ["device_class": .string("motion")], lu: 100),
                    processorState("on", lu: 110),
                    processorState("off", lu: 120)
                ],
                "sensor.room_temperature": [
                    processorState("21.5", attributes: [
                        "friendly_name": .string("Room temperature"),
                        "unit_of_measurement": .string("\u{00B0}C"),
                        "device_class": .string("temperature")
                    ], lu: 100)
                ]
            ],
            context: context,
            splitDeviceClasses: true
        )

        XCTAssertEqual(result.line.count, 2)
        XCTAssertEqual(result.timeline.count, 1)

        let powerUnit = result.line.first { $0.unit == "W" }
        XCTAssertEqual(powerUnit?.deviceClass, "power")
        XCTAssertEqual(powerUnit?.data.first?.name, "Power")
        XCTAssertEqual(powerUnit?.data.first?.states.map(\.state), ["10", "10", "15"])
        XCTAssertEqual(powerUnit?.data.first?.states.map(\.lastChanged), [100_000, 100_000, 160_000])

        let temperatureUnit = result.line.first { $0.unit == "\u{00B0}C" }
        XCTAssertEqual(temperatureUnit?.deviceClass, "temperature")
        XCTAssertEqual(temperatureUnit?.data.first?.name, "Room temperature")

        XCTAssertEqual(result.timeline.first?.entityID, "binary_sensor.motion")
        XCTAssertEqual(result.timeline.first?.data.map(\.state), ["on", "off"])
    }

    func testComputeHistoryFallsBackToCurrentStateForMissingHistory() {
        let current = makeEntity(
            entityID: "sensor.power",
            state: "42",
            attributes: [
                "friendly_name": .string("Power"),
                "unit_of_measurement": .string("W")
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_700)
        )
        let result = computeHistory(
            stateHistory: [:],
            entityIDs: ["sensor.power", "sensor.not_present"],
            context: HistoryProcessingContext(states: ["sensor.power": current])
        )

        XCTAssertEqual(result.line.count, 1)
        XCTAssertEqual(result.line.first?.data.first?.states.first?.state, "42")
        XCTAssertEqual(result.line.first?.data.first?.states.first?.lastChanged, 1_700_000)
    }

    func testSpecialDomainLineHistoryKeepsOnlyChartRelevantAttributes() {
        let result = HistoryProcessor.computeHistory(
            stateHistory: [
                "climate.thermostat": [
                    processorState("heat", attributes: [
                        "friendly_name": .string("Thermostat"),
                        "temperature": .integer(21),
                        "current_temperature": .double(20.5),
                        "ignored": .string("not charted")
                    ], lu: 100),
                    processorState("heat", attributes: [
                        "temperature": .integer(22),
                        "current_temperature": .double(20.7),
                        "hvac_action": .string("heating")
                    ], lu: 130)
                ]
            ],
            context: HistoryProcessingContext(config: makeConfig())
        )

        let unit = result.line.first
        XCTAssertEqual(unit?.unit, "\u{00B0}C")
        XCTAssertEqual(unit?.deviceClass, "temperature")
        XCTAssertEqual(unit?.data.first?.states.first?.lastChanged, 100_000)
        XCTAssertEqual(unit?.data.first?.states.first?.attributes?["current_temperature"], .double(20.5))
        XCTAssertNil(unit?.data.first?.states.first?.attributes?["ignored"])
    }

    func testStatisticsConvertToHistoryAndMergeDropsOverlappingStatistics() {
        let context = HistoryProcessingContext(states: [
            "sensor.power": makeEntity(
                entityID: "sensor.power",
                state: "4",
                attributes: [
                    "friendly_name": .string("Power"),
                    "unit_of_measurement": .string("W"),
                    "device_class": .string("power")
                ]
            )
        ])
        let statisticsResult = convertStatisticsToHistory(
            statistics: [
                "sensor.power": [
                    StatisticValue(start: 0, end: 1_000, mean: 1.25),
                    StatisticValue(start: 1_000, end: 2_000, mean: 2),
                    StatisticValue(start: 2_000, end: 3_000, state: 3)
                ]
            ],
            statisticIDs: ["sensor.power"],
            context: context
        )

        XCTAssertEqual(statisticsResult.line.first?.unit, "W")
        XCTAssertEqual(statisticsResult.line.first?.data.first?.states, [])
        XCTAssertEqual(statisticsResult.line.first?.data.first?.statistics?.map(\.state), ["1.25", "2", "3"])

        let liveResult = computeHistory(
            stateHistory: [
                "sensor.power": [
                    processorState("2.5", attributes: ["unit_of_measurement": .string("W")], lu: 2.5),
                    processorState("4", lu: 4)
                ]
            ],
            context: context
        )

        let merged = mergeHistoryResults(
            historyResult: liveResult,
            longTermStatisticsResult: statisticsResult
        )
        let mergedEntity = merged.line.first?.data.first
        XCTAssertEqual(mergedEntity?.statistics?.map(\.lastChanged), [1_000, 2_000])
        XCTAssertEqual(mergedEntity?.states.map(\.state), ["2.5", "4"])
    }

    func testHistoryAndStatisticsAPIBuildExpectedWebSocketPayloads() async throws {
        let client = RecordingHistoryWebSocketClient(callResult: HistoryStates())
        let historyAPI = HistoryAPI(client: client)
        let current = makeEntity(
            entityID: "sensor.power",
            state: "10",
            attributes: ["unit_of_measurement": .string("W")]
        )

        _ = try await historyAPI.fetchHistoryDuringPeriod(
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            entityIDs: ["sensor.power"],
            currentStates: ["sensor.power": current]
        )

        let historyRequest = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(historyRequest["type"], .string("history/history_during_period"))
        XCTAssertEqual(historyRequest["entity_ids"]?.arrayValue, [.string("sensor.power")])
        XCTAssertEqual(historyRequest["minimal_response"], .bool(true))
        XCTAssertEqual(historyRequest["no_attributes"], .bool(true))
        XCTAssertTrue(historyRequest["start_time"]?.stringValue?.hasPrefix("1970-01-01T00:16:40") == true)

        client.callResult = Statistics()
        let statisticsAPI = StatisticsAPI(client: client)
        _ = try await statisticsAPI.fetchStatisticsDuringPeriod(
            startTime: Date(timeIntervalSince1970: 1_000),
            statisticIDs: ["sensor.power"],
            period: .hour,
            types: [.mean, .state]
        )

        let statisticsRequest = try XCTUnwrap(client.requests.last)
        XCTAssertEqual(statisticsRequest["type"], .string("recorder/statistics_during_period"))
        XCTAssertEqual(statisticsRequest["period"], .string("hour"))
        XCTAssertEqual(statisticsRequest["statistic_ids"]?.arrayValue, [.string("sensor.power")])
        XCTAssertEqual(statisticsRequest["types"]?.arrayValue, [.string("mean"), .string("state")])
    }

    func testComputeHistoryLargeGeneratedPayloadPerformanceStyle() {
        let states = (0..<1_500).map { index in
            processorState(
                String(index % 200),
                attributes: index == 0 ? [
                    "unit_of_measurement": .string("W"),
                    "device_class": .string("power")
                ] : [:],
                lu: Double(index * 30)
            )
        }
        let history: HistoryStates = ["sensor.power": states]
        let result = computeHistory(stateHistory: history)
        XCTAssertEqual(result.line.first?.data.first?.states.count, 1_500)

        measure {
            _ = computeHistory(stateHistory: history)
        }
    }
}

private func processorState(
    _ state: String,
    attributes: [String: HAJSONValue] = [:],
    lu: Double,
    lc: Double? = nil
) -> EntityHistoryState {
    EntityHistoryState(state: state, attributes: attributes, lastChanged: lc, lastUpdated: lu)
}

private func makeEntity(
    entityID: EntityID,
    state: String,
    attributes: [String: HAJSONValue],
    lastUpdated: Date = Date(timeIntervalSince1970: 1_000)
) -> HassEntity {
    HassEntity(
        entityID: entityID,
        state: state,
        attributes: attributes,
        lastChanged: lastUpdated,
        lastUpdated: lastUpdated,
        context: HAContext(id: "test")
    )
}

private func makeConfig() -> HAConfig {
    HAConfig(
        latitude: 0,
        longitude: 0,
        elevation: 0,
        locationName: "Home",
        timeZone: "UTC",
        unitSystem: ["temperature": "\u{00B0}C"],
        version: "test",
        components: ["history"],
        configDir: nil,
        configSource: nil,
        country: nil,
        currency: nil,
        language: "en",
        internalURL: nil,
        externalURL: nil,
        safeMode: false,
        recoveryMode: nil,
        state: nil
    )
}

private final class RecordingHistoryWebSocketClient: HAWebSocketClientProtocol {
    var callResult: Any
    private(set) var requests: [[String: HAJSONValue]] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(callResult: Any) {
        self.callResult = callResult
    }

    func connect() async throws {}

    func disconnect() async {}

    func callWS<T, Message>(_ message: Message) async throws -> T where T: Decodable, Message: Encodable {
        requests.append(try requestObject(from: message))
        guard let result = callResult as? T else {
            throw HAWebSocketClientError.invalidInboundMessage
        }
        return result
    }

    func subscribe<T, Message>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription where T: Decodable, Message: Encodable {
        requests.append(try requestObject(from: message))
        return HASubscription(id: requests.count) {}
    }

    private func requestObject<Message: Encodable>(from message: Message) throws -> [String: HAJSONValue] {
        let data = try encoder.encode(message)
        return try decoder.decode([String: HAJSONValue].self, from: data)
    }
}
