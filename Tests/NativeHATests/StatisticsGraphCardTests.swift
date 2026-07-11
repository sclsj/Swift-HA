import XCTest
@testable import NativeHA
@testable import NativeHACore

@MainActor
final class StatisticsGraphCardTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let fixedNow = Date(timeIntervalSince1970: 20_000)

    func testFactoryRoutesStatisticsGraphToNativeCardKind() throws {
        let card = try decodeCard("""
        {
          "type": "statistics-graph",
          "title": "Energy",
          "entities": ["sensor.energy"]
        }
        """)

        let descriptor = LovelaceElementFactory.descriptor(for: card)

        XCTAssertEqual(descriptor.renderKind, .statisticsGraph)
        XCTAssertEqual(descriptor.type, "statistics-graph")
        XCTAssertEqual(descriptor.title, "Energy")
        XCTAssertEqual(descriptor.entityID, "sensor.energy")
    }

    func testStringEntityConfigBuildsModelWithDefaultsAndPreservesRawFields() throws {
        let config = try decodeStatisticsConfig("""
        {
          "type": "statistics-graph",
          "title": "Power",
          "entities": ["sensor.power"],
          "unsupported_future_field": {"ignored": true}
        }
        """)

        let model = StatisticsGraphCardModel(config: config, displayContext: .empty)

        XCTAssertEqual(model.title, "Power")
        XCTAssertEqual(model.entityIDs, ["sensor.power"])
        XCTAssertEqual(model.daysToShow, 30)
        XCTAssertEqual(model.period, .hour)
        XCTAssertEqual(model.statTypes, StatisticsSeriesBuilder.defaultStatTypes)
        XCTAssertEqual(model.chartType, .line)
        XCTAssertEqual(config.raw.objectValue?["unsupported_future_field"]?.objectValue?["ignored"], .bool(true))
    }

    func testObjectEntityConfigBuildsNamesColorsAndDecodesCommonOptions() throws {
        let config = try decodeStatisticsConfig("""
        {
          "type": "statistics-graph",
          "entities": [
            {
              "entity": "sensor.temperature",
              "name": "Room",
              "color": "#ff0000",
              "unsupported": "safe"
            }
          ],
          "days_to_show": 7,
          "period": "day",
          "stat_types": "mean",
          "chart_type": "bar",
          "min_y_axis": 0,
          "max_y_axis": 50
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

        let model = StatisticsGraphCardModel(config: config, displayContext: context)

        XCTAssertEqual(model.entityIDs, ["sensor.temperature"])
        XCTAssertEqual(model.displayNames["sensor.temperature"], "Room")
        XCTAssertEqual(model.colors["sensor.temperature"], "#ff0000")
        XCTAssertEqual(model.daysToShow, 7)
        XCTAssertEqual(model.period, .day)
        XCTAssertEqual(model.statTypes, [.mean])
        XCTAssertEqual(model.chartType, .bar)
        XCTAssertEqual(model.minYAxis, 0)
        XCTAssertEqual(model.maxYAxis, 50)
        XCTAssertEqual(config.entities.first?.raw.objectValue?["unsupported"], .string("safe"))
    }

    func testMalformedEntityEntriesDoNotPreventValidSiblings() throws {
        let config = try decodeStatisticsConfig("""
        {
          "type": "statistics-graph",
          "entities": [
            "sensor.power",
            42,
            {"entity": null},
            {"entity": "missing_dot"},
            {"entity": "sensor.temperature"}
          ],
          "stat_types": ["mean", 99, "max", "unsupported"]
        }
        """)

        let model = StatisticsGraphCardModel(config: config, displayContext: .empty)

        XCTAssertEqual(config.entities.count, 5)
        XCTAssertEqual(model.entityIDs, ["sensor.power", "sensor.temperature"])
        XCTAssertEqual(model.statTypes, [.mean, .max])
    }

    func testInitialStatisticsFetchUsesConfiguredPayloadAndWindow() async throws {
        let provider = MockStatisticsGraphDataProvider()
        provider.metadataResult = [metadata("sensor.energy", unit: "kWh", hasSum: true)]
        provider.statisticsResult = [
            "sensor.energy": [
                StatisticValue(start: 0, end: 1_000, change: 4, sum: 12)
            ]
        ]
        let viewModel = StatisticsGraphCardViewModel(now: { self.fixedNow })
        let model = StatisticsGraphCardModel(
            config: try decodeStatisticsConfig("""
            {
              "type": "statistics-graph",
              "days_to_show": 2,
              "period": "day",
              "stat_types": ["sum", "change"],
              "entities": ["sensor.energy"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.energy", unit: "kWh")
        )

        await viewModel.load(
            model: model,
            provider: provider,
            displayContext: numericContext(entityID: "sensor.energy", unit: "kWh")
        )

        XCTAssertEqual(provider.metadataRequests, [["sensor.energy"]])
        let statisticsRequest = try XCTUnwrap(provider.statisticsRequests.first)
        XCTAssertEqual(statisticsRequest.statisticIDs, ["sensor.energy"])
        XCTAssertEqual(statisticsRequest.period, .day)
        XCTAssertEqual(statisticsRequest.types, [.sum, .change])
        XCTAssertEqual(statisticsRequest.startTime.timeIntervalSince1970, -156_400, accuracy: 0.001)
        XCTAssertEqual(statisticsRequest.endTime.timeIntervalSince1970, 20_000, accuracy: 0.001)
    }

    func testEmptyStatisticsProducesEmptyState() async throws {
        let provider = MockStatisticsGraphDataProvider()
        provider.metadataResult = [metadata("sensor.missing")]
        let viewModel = StatisticsGraphCardViewModel(now: { self.fixedNow })
        let model = StatisticsGraphCardModel(
            config: try decodeStatisticsConfig("""
            {
              "type": "statistics-graph",
              "entities": ["sensor.missing"]
            }
            """),
            displayContext: .empty
        )

        await viewModel.load(model: model, provider: provider, displayContext: .empty)

        XCTAssertEqual(viewModel.phase, .empty(.noData))
    }

    func testStatisticsErrorProducesSafeErrorState() async throws {
        let provider = MockStatisticsGraphDataProvider()
        provider.metadataResult = [metadata("sensor.power")]
        provider.statisticsError = TestStatisticsError.fetchFailed
        let viewModel = StatisticsGraphCardViewModel(now: { self.fixedNow })
        let model = StatisticsGraphCardModel(
            config: try decodeStatisticsConfig("""
            {
              "type": "statistics-graph",
              "entities": ["sensor.power"]
            }
            """),
            displayContext: numericContext(entityID: "sensor.power")
        )

        await viewModel.load(model: model, provider: provider, displayContext: numericContext(entityID: "sensor.power"))

        guard case let .error(message) = viewModel.phase else {
            return XCTFail("Expected error state.")
        }
        XCTAssertTrue(message.contains("fetchFailed"))
    }

    func testLineChartDataGeneratedFromMeanStatistics() async throws {
        let provider = MockStatisticsGraphDataProvider()
        provider.metadataResult = [metadata("sensor.temperature", unit: "°C")]
        provider.statisticsResult = [
            "sensor.temperature": [
                StatisticValue(start: 1_000, end: 2_000, mean: 21),
                StatisticValue(start: 2_000, end: 3_000, mean: 22)
            ]
        ]
        let viewModel = StatisticsGraphCardViewModel(now: { self.fixedNow })
        let model = StatisticsGraphCardModel(
            config: try decodeStatisticsConfig("""
            {
              "type": "statistics-graph",
              "stat_types": ["mean"],
              "entities": [{"entity": "sensor.temperature", "name": "Room"}]
            }
            """),
            displayContext: numericContext(entityID: "sensor.temperature", unit: "°C")
        )

        await viewModel.load(model: model, provider: provider, displayContext: numericContext(entityID: "sensor.temperature", unit: "°C"))

        let chartData = try loadedChartData(from: viewModel.phase)
        XCTAssertEqual(chartData.series.series.count, 1)
        XCTAssertEqual(chartData.series.series[0].id, "sensor.temperature-mean")
        XCTAssertEqual(chartData.series.series[0].name, "Room")
        XCTAssertEqual(chartData.series.series[0].unit, "°C")
        XCTAssertEqual(chartData.series.series[0].points.map(\.y), [21, 22, 22])
        XCTAssertTrue(chartData.series.series[0].points.allSatisfy { $0.source == .statistics })
    }

    func testMultipleStatTypesGenerateSeparateSeries() {
        let result = StatisticsSeriesBuilder.buildSeries(
            statistics: [
                "sensor.temperature": [
                    StatisticValue(start: 1_000, end: 2_000, max: 24, mean: 22, min: 20)
                ]
            ],
            metadata: ["sensor.temperature": metadata("sensor.temperature", unit: "°C")],
            statisticIDs: ["sensor.temperature"],
            statTypes: [.min, .mean, .max],
            names: ["sensor.temperature": "Room"]
        )

        XCTAssertEqual(result.series.map(\.id), [
            "sensor.temperature-min",
            "sensor.temperature-mean",
            "sensor.temperature-max"
        ])
        XCTAssertEqual(result.series.map(\.name), ["Room min", "Room mean", "Room max"])
        XCTAssertEqual(result.yAxis.minimum, 20)
        XCTAssertEqual(result.yAxis.maximum, 24)
    }

    func testRegressionUnknownCardFallbackUnchanged() throws {
        let unknown = try decodeCard("""
        {"type": "custom:apexcharts-card", "entity": "sensor.power"}
        """)

        XCTAssertEqual(LovelaceElementFactory.descriptor(for: unknown).renderKind, .fallback)
    }

    private func decodeCard(_ json: String) throws -> LovelaceCardConfig {
        try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8))
    }

    private func decodeStatisticsConfig(_ json: String) throws -> StatisticsGraphCardConfig {
        guard case let .statisticsGraph(config) = try decodeCard(json) else {
            throw TestDecodeError.unexpectedCardType
        }
        return config
    }

    private func loadedChartData(from phase: StatisticsGraphCardPhase) throws -> StatisticsGraphChartData {
        guard case let .loaded(data) = phase else {
            throw TestDecodeError.unexpectedPhase
        }
        return data
    }

    private func numericContext(entityID: EntityID, unit: String = "W") -> EntityDisplayContext {
        EntityDisplayContext(states: [
            entityID: entity(
                entityID,
                state: "11",
                attributes: [
                    "friendly_name": .string(EntityIDParser.displayObjectID(from: entityID)),
                    "unit_of_measurement": .string(unit),
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
}

private enum TestDecodeError: Error {
    case unexpectedCardType
    case unexpectedPhase
}

private enum TestStatisticsError: Error {
    case fetchFailed
}

@MainActor
private final class MockStatisticsGraphDataProvider: StatisticsGraphDataProviding {
    struct StatisticsRequest: Equatable {
        var startTime: Date
        var endTime: Date
        var statisticIDs: [String]
        var period: StatisticPeriod
        var types: [StatisticType]
    }

    var metadataResult: [StatisticsMetaData] = []
    var statisticsResult: Statistics = [:]
    var metadataError: Error?
    var statisticsError: Error?

    private(set) var metadataRequests: [[String]] = []
    private(set) var statisticsRequests: [StatisticsRequest] = []

    func fetchStatisticMetadata(statisticIDs: [String]) async throws -> [StatisticsMetaData] {
        metadataRequests.append(statisticIDs)
        if let metadataError = metadataError {
            throw metadataError
        }
        return metadataResult
    }

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String],
        period: StatisticPeriod,
        types: [StatisticType]
    ) async throws -> Statistics {
        statisticsRequests.append(StatisticsRequest(
            startTime: startTime,
            endTime: endTime,
            statisticIDs: statisticIDs,
            period: period,
            types: types
        ))
        if let statisticsError = statisticsError {
            throw statisticsError
        }
        return statisticsResult
    }
}

private func metadata(
    _ statisticID: String,
    unit: String = "W",
    hasSum: Bool = false
) -> StatisticsMetaData {
    StatisticsMetaData(
        statisticsUnitOfMeasurement: unit,
        statisticID: statisticID,
        source: "recorder",
        name: nil,
        hasSum: hasSum,
        meanType: hasSum ? .none : .arithmetic,
        unitClass: hasSum ? "energy" : "power"
    )
}
