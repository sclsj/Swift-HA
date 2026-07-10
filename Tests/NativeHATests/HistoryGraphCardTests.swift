import XCTest
@testable import NativeHA
@testable import NativeHACore

@MainActor
final class HistoryGraphCardTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let fixedNow = Date(timeIntervalSince1970: 20_000)

    func testFactoryRoutesHistoryGraphToNativeCardKind() throws {
        let card = try decodeCard("""
        {
          "type": "history-graph",
          "title": "Temperature",
          "entities": ["sensor.temperature"]
        }
        """)

        let descriptor = LovelaceElementFactory.descriptor(for: card)

        XCTAssertEqual(descriptor.renderKind, .historyGraph)
        XCTAssertEqual(descriptor.type, "history-graph")
        XCTAssertEqual(descriptor.title, "Temperature")
        XCTAssertEqual(descriptor.entityID, "sensor.temperature")
    }

    func testStringEntityConfigBuildsModelWithDefaults() throws {
        let config = try decodeHistoryConfig("""
        {
          "type": "history-graph",
          "title": "Power",
          "entities": ["sensor.power"],
          "unsupported_future_field": {"ignored": true}
        }
        """)

        let model = HistoryGraphCardModel(config: config, displayContext: .empty)

        XCTAssertEqual(model.title, "Power")
        XCTAssertEqual(model.entityIDs, ["sensor.power"])
        XCTAssertEqual(model.hoursToShow, 24)
        XCTAssertEqual(model.showNames, true)
        XCTAssertNil(model.refreshIntervalSeconds)
        XCTAssertEqual(config.raw.objectValue?["unsupported_future_field"]?.objectValue?["ignored"], .bool(true))
    }

    func testObjectEntityConfigBuildsNamesColorsAndIgnoresUnsupportedOptions() throws {
        let config = try decodeHistoryConfig("""
        {
          "type": "history-graph",
          "entities": [
            {
              "entity": "sensor.temperature",
              "name": "Room",
              "color": "#ff0000",
              "unsupported": "safe"
            }
          ],
          "hours_to_show": 3,
          "show_names": false,
          "refresh_interval": 30
        }
        """)
        let context = EntityDisplayContext(states: [
            "sensor.temperature": entity(
                "sensor.temperature",
                state: "21",
                attributes: [
                    "friendly_name": .string("Ignored by override"),
                    "unit_of_measurement": .string("°C")
                ]
            )
        ])

        let model = HistoryGraphCardModel(config: config, displayContext: context)

        XCTAssertEqual(model.entityIDs, ["sensor.temperature"])
        XCTAssertEqual(model.displayNames["sensor.temperature"], "Room")
        XCTAssertEqual(model.colors["sensor.temperature"], "#ff0000")
        XCTAssertEqual(model.hoursToShow, 3)
        XCTAssertFalse(model.showNames)
        XCTAssertEqual(model.refreshIntervalSeconds, 30)
        XCTAssertEqual(config.entities.first?.raw.objectValue?["unsupported"], .string("safe"))
    }

    func testMissingEntitiesShowsSafeEmptyState() throws {
        let config = try decodeHistoryConfig("""
        {
          "type": "history-graph",
          "entities": [
            {"name": "Missing entity object"}
          ]
        }
        """)
        let provider = MockHistoryGraphDataProvider()
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(config: config, displayContext: .empty)

        viewModel.start(model: model, provider: provider, displayContext: .empty)

        XCTAssertEqual(viewModel.phase, .empty(.noEntities))
        XCTAssertEqual(provider.historyRequests.count, 0)
    }

    func testInitialHistoryFetchUsesConfiguredEntityIDsAndTimeWindow() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyResult = [
            "sensor.power": [historyState("10", attributes: ["unit_of_measurement": .string("W")], lu: 19_900)]
        ]
        provider.statisticsResult = [
            "sensor.power": [StatisticValue(start: 0, end: 19_000_000, mean: 8)]
        ]
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 3,
              "entities": ["sensor.power"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.power")
        )

        await viewModel.load(
            model: model,
            provider: provider,
            displayContext: numericContext(entityID: "sensor.power")
        )

        let historyRequest = try XCTUnwrap(provider.historyRequests.first)
        XCTAssertEqual(historyRequest.entityIDs, ["sensor.power"])
        XCTAssertEqual(historyRequest.startTime.timeIntervalSince1970, 9_200, accuracy: 0.001)
        XCTAssertEqual(historyRequest.endTime.timeIntervalSince1970, 20_000, accuracy: 0.001)

        let statisticsRequest = try XCTUnwrap(provider.statisticsRequests.first)
        XCTAssertEqual(statisticsRequest.statisticIDs, ["sensor.power"])
        XCTAssertEqual(statisticsRequest.startTime.timeIntervalSince1970, 5_600, accuracy: 0.001)
        XCTAssertEqual(statisticsRequest.endTime.timeIntervalSince1970, 20_000, accuracy: 0.001)
    }

    func testHoursToShowChangesStartTimeCalculation() async throws {
        let provider = MockHistoryGraphDataProvider()
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 12,
              "entities": ["sensor.energy"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.energy")
        )

        await viewModel.load(
            model: model,
            provider: provider,
            displayContext: numericContext(entityID: "sensor.energy")
        )

        let historyRequest = try XCTUnwrap(provider.historyRequests.first)
        let statisticsRequest = try XCTUnwrap(provider.statisticsRequests.first)
        XCTAssertEqual(historyRequest.startTime.timeIntervalSince1970, -23_200, accuracy: 0.001)
        XCTAssertEqual(statisticsRequest.startTime.timeIntervalSince1970, -26_800, accuracy: 0.001)
    }

    func testRefreshIntervalSchedulesAtMostOneRefreshLoop() throws {
        let provider = MockHistoryGraphDataProvider()
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "refresh_interval": 30,
              "entities": ["sensor.power"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.power")
        )

        viewModel.start(model: model, provider: provider, displayContext: numericContext(entityID: "sensor.power"))
        viewModel.start(model: model, provider: provider, displayContext: numericContext(entityID: "sensor.power"))

        XCTAssertEqual(viewModel.refreshLoopStartCount, 1)
        XCTAssertTrue(viewModel.hasScheduledRefresh)
        viewModel.cancel()
    }

    func testRefreshIntervalZeroDoesNotScheduleRefreshLoop() throws {
        let provider = MockHistoryGraphDataProvider()
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "refresh_interval": 0,
              "entities": ["sensor.power"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.power")
        )

        viewModel.start(model: model, provider: provider, displayContext: numericContext(entityID: "sensor.power"))

        XCTAssertEqual(viewModel.refreshLoopStartCount, 0)
        XCTAssertFalse(viewModel.hasScheduledRefresh)
        viewModel.cancel()
    }

    func testCancellationStopsInFlightFetchFromApplyingResult() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.suspendHistoryFetch = true
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let context = numericContext(entityID: "sensor.power")
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "entities": ["sensor.power"]
            }
            """),
            displayContext: context
        )

        viewModel.start(model: model, provider: provider, displayContext: context)
        await provider.waitForHistoryRequest()
        viewModel.cancel()
        provider.resumeSuspendedHistory([
            "sensor.power": [historyState("10", attributes: ["unit_of_measurement": .string("W")], lu: 19_900)]
        ])
        await Task.yield()

        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testHistoryFetchErrorProducesErrorState() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyError = TestHistoryError.fetchFailed
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "entities": ["sensor.power"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.power")
        )

        await viewModel.load(
            model: model,
            provider: provider,
            displayContext: numericContext(entityID: "sensor.power")
        )

        guard case let .error(message) = viewModel.phase else {
            return XCTFail("Expected error state.")
        }
        XCTAssertTrue(message.contains("fetchFailed"))
    }

    func testEmptyHistoryProducesEmptyState() async throws {
        let provider = MockHistoryGraphDataProvider()
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 0.5,
              "entities": ["sensor.missing"]
            }
            """),
            displayContext: .empty
        )

        await viewModel.load(model: model, provider: provider, displayContext: .empty)

        XCTAssertEqual(viewModel.phase, .empty(.noData))
    }

    func testNumericSensorHistoryProducesLineChartData() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyResult = [
            "sensor.power": [
                historyState("10", attributes: ["unit_of_measurement": .string("W")], lu: 19_800),
                historyState("12", lu: 19_900)
            ]
        ]
        let context = numericContext(entityID: "sensor.power")
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 0.5,
              "entities": ["sensor.power"]
            }
            """),
            displayContext: context
        )

        await viewModel.load(model: model, provider: provider, displayContext: context)

        let chartData = try loadedChartData(from: viewModel.phase)
        XCTAssertEqual(chartData.lineCharts.count, 1)
        XCTAssertNil(chartData.timelineChart)
        XCTAssertEqual(chartData.lineCharts.first?.series.series.first?.entityID, "sensor.power")
        XCTAssertEqual(chartData.lineCharts.first?.series.yAxis.unit, "W")
    }

    func testNonNumericHistoryProducesTimelineChartData() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyResult = [
            "binary_sensor.motion": [
                historyState("off", attributes: ["device_class": .string("motion")], lu: 19_800),
                historyState("on", lu: 19_900)
            ]
        ]
        let context = EntityDisplayContext(states: [
            "binary_sensor.motion": entity(
                "binary_sensor.motion",
                state: "on",
                attributes: [
                    "friendly_name": .string("Motion"),
                    "device_class": .string("motion")
                ]
            )
        ])
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 0.5,
              "entities": ["binary_sensor.motion"]
            }
            """),
            displayContext: context
        )

        await viewModel.load(model: model, provider: provider, displayContext: context)

        let chartData = try loadedChartData(from: viewModel.phase)
        XCTAssertTrue(chartData.lineCharts.isEmpty)
        XCTAssertEqual(chartData.timelineChart?.series.rows.first?.entityID, "binary_sensor.motion")
        XCTAssertEqual(chartData.timelineChart?.series.rows.first?.segments.map(\.state), ["off", "on"])
    }

    func testMixedEntitiesKeepCurrentModuleNineLineAndTimelineSemantics() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyResult = [
            "sensor.power": [
                historyState("10", attributes: ["unit_of_measurement": .string("W")], lu: 19_800)
            ],
            "binary_sensor.motion": [
                historyState("off", attributes: ["device_class": .string("motion")], lu: 19_800)
            ]
        ]
        let context = EntityDisplayContext(states: [
            "sensor.power": entity(
                "sensor.power",
                state: "10",
                attributes: [
                    "friendly_name": .string("Power"),
                    "unit_of_measurement": .string("W")
                ]
            ),
            "binary_sensor.motion": entity(
                "binary_sensor.motion",
                state: "off",
                attributes: [
                    "friendly_name": .string("Motion"),
                    "device_class": .string("motion")
                ]
            )
        ])
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 0.5,
              "entities": ["sensor.power", "binary_sensor.motion"]
            }
            """),
            displayContext: context
        )

        await viewModel.load(model: model, provider: provider, displayContext: context)

        let chartData = try loadedChartData(from: viewModel.phase)
        XCTAssertEqual(chartData.lineCharts.count, 1)
        XCTAssertEqual(chartData.timelineChart?.series.rows.count, 1)
    }

    func testUnknownAndUnavailableNumericGapsSurviveIntoLineSeries() async throws {
        let provider = MockHistoryGraphDataProvider()
        provider.historyResult = [
            "sensor.power": [
                historyState("10", attributes: ["unit_of_measurement": .string("W")], lu: 19_700),
                historyState("unknown", lu: 19_800),
                historyState("unavailable", lu: 19_850),
                historyState("12", lu: 19_900)
            ]
        ]
        let context = numericContext(entityID: "sensor.power")
        let viewModel = HistoryGraphCardViewModel(now: { self.fixedNow })
        let model = HistoryGraphCardModel(
            config: try decodeHistoryConfig("""
            {
              "type": "history-graph",
              "hours_to_show": 0.5,
              "entities": ["sensor.power"]
            }
            """),
            displayContext: context
        )

        await viewModel.load(model: model, provider: provider, displayContext: context)

        let points = try loadedChartData(from: viewModel.phase)
            .lineCharts[0]
            .series
            .series[0]
            .points

        XCTAssertTrue(points.contains { $0.y == nil })
    }

    func testRegressionUnknownCardsStillFallBackAndNonHistoryCardsStayNative() throws {
        let tile = try decodeCard("""
        {"type": "tile", "entity": "switch.power"}
        """)
        XCTAssertEqual(LovelaceElementFactory.descriptor(for: tile).renderKind, .nativePlaceholder)

        let unknown = try decodeCard("""
        {"type": "custom:apexcharts-card", "entity": "sensor.power"}
        """)
        XCTAssertEqual(LovelaceElementFactory.descriptor(for: unknown).renderKind, .fallback)
    }

    private func decodeCard(_ json: String) throws -> LovelaceCardConfig {
        try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8))
    }

    private func decodeHistoryConfig(_ json: String) throws -> HistoryGraphCardConfig {
        guard case let .historyGraph(config) = try decodeCard(json) else {
            throw TestDecodeError.unexpectedCardType
        }
        return config
    }

    private func loadedChartData(from phase: HistoryGraphCardPhase) throws -> HistoryGraphChartData {
        guard case let .loaded(data) = phase else {
            throw TestDecodeError.unexpectedPhase
        }
        return data
    }

    private func numericContext(entityID: EntityID) -> EntityDisplayContext {
        EntityDisplayContext(states: [
            entityID: entity(
                entityID,
                state: "11",
                attributes: [
                    "friendly_name": .string(EntityIDParser.displayObjectID(from: entityID)),
                    "unit_of_measurement": .string("W"),
                    "device_class": .string("power"),
                    "state_class": .string("measurement")
                ]
            )
        ])
    }

    private func entity(
        _ entityID: EntityID,
        state: String,
        attributes: [String: HAJSONValue]
    ) -> HassEntity {
        HassEntity(
            entityID: entityID,
            state: state,
            attributes: attributes,
            lastChanged: fixedNow,
            lastUpdated: fixedNow,
            context: HAContext(id: "test")
        )
    }

    private func historyState(
        _ state: String,
        attributes: [String: HAJSONValue] = [:],
        lu: Double,
        lc: Double? = nil
    ) -> EntityHistoryState {
        EntityHistoryState(state: state, attributes: attributes, lastChanged: lc, lastUpdated: lu)
    }
}

private enum TestDecodeError: Error {
    case unexpectedCardType
    case unexpectedPhase
}

private enum TestHistoryError: Error {
    case fetchFailed
}

@MainActor
private final class MockHistoryGraphDataProvider: HistoryGraphDataProviding {
    struct HistoryRequest: Equatable {
        var startTime: Date
        var endTime: Date
        var entityIDs: [EntityID]
        var currentStateIDs: [EntityID]
    }

    struct StatisticsRequest: Equatable {
        var startTime: Date
        var endTime: Date
        var statisticIDs: [String]
    }

    var historyResult: HistoryStates = [:]
    var statisticsResult: Statistics = [:]
    var historyError: Error?
    var suspendHistoryFetch = false

    private(set) var historyRequests: [HistoryRequest] = []
    private(set) var statisticsRequests: [StatisticsRequest] = []

    private var historyWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendedHistoryContinuation: CheckedContinuation<HistoryStates, Error>?

    func fetchHistory(
        startTime: Date,
        endTime: Date,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity]
    ) async throws -> HistoryStates {
        historyRequests.append(HistoryRequest(
            startTime: startTime,
            endTime: endTime,
            entityIDs: entityIDs,
            currentStateIDs: Array(currentStates.keys).sorted()
        ))
        historyWaiters.forEach { $0.resume() }
        historyWaiters.removeAll()

        if let historyError = historyError {
            throw historyError
        }

        if suspendHistoryFetch {
            return try await withCheckedThrowingContinuation { continuation in
                suspendedHistoryContinuation = continuation
            }
        }

        return historyResult
    }

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String]
    ) async throws -> Statistics {
        statisticsRequests.append(StatisticsRequest(
            startTime: startTime,
            endTime: endTime,
            statisticIDs: statisticIDs
        ))
        return statisticsResult
    }

    func waitForHistoryRequest() async {
        if !historyRequests.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            historyWaiters.append(continuation)
        }
    }

    func resumeSuspendedHistory(_ result: HistoryStates) {
        suspendedHistoryContinuation?.resume(returning: result)
        suspendedHistoryContinuation = nil
    }
}
