import XCTest
@testable import NativeHACore

final class LineSeriesBuilderTests: XCTestCase {
    func testBuildsNumericSensorSeriesWithStepMetadataAndYAxis() {
        let unit = LineChartUnit(
            unit: "W",
            deviceClass: "power",
            identifier: "sensor.power",
            data: [
                LineChartEntity(
                    domain: "sensor",
                    name: "Power",
                    entityID: "sensor.power",
                    states: [
                        LineChartState(state: "1", lastChanged: 1_000),
                        LineChartState(state: "2.5", lastChanged: 2_000)
                    ]
                )
            ]
        )

        let result = LineSeriesBuilder.buildSeries(for: unit, endTime: 4_000)

        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.series.first?.id, "sensor.power")
        XCTAssertEqual(result.series.first?.stepMode, .end)
        XCTAssertEqual(result.series.first?.points, [
            LinePoint(x: 1_000, y: 1),
            LinePoint(x: 2_000, y: 2.5),
            LinePoint(x: 4_000, y: 2.5)
        ])
        XCTAssertEqual(result.legendItems.first?.seriesIDs, ["sensor.power"])
        XCTAssertEqual(result.yAxis.minimum, 1)
        XCTAssertEqual(result.yAxis.maximum, 2.5)
        XCTAssertEqual(result.yAxis.fractionDigits, 1)
        XCTAssertEqual(AxisLabelFormatter.format(2.5, metadata: result.yAxis), "2.5 W")
    }

    func testBuildsNullBreaksForUnknownUnavailableAndNonNumericGaps() {
        let entity = LineChartEntity(
            domain: "sensor",
            name: "Power",
            entityID: "sensor.power",
            states: [
                LineChartState(state: "10", lastChanged: 1_000),
                LineChartState(state: "unavailable", lastChanged: 2_000),
                LineChartState(state: "unknown", lastChanged: 2_500),
                LineChartState(state: "15", lastChanged: 3_000)
            ]
        )

        let result = LineSeriesBuilder.buildSeries(
            data: [entity],
            unit: "W",
            deviceClass: "power",
            endTime: 4_000
        )

        XCTAssertEqual(result.series.first?.points, [
            LinePoint(x: 1_000, y: 10),
            LinePoint(x: 2_000, y: 10),
            LinePoint(x: 2_001, y: nil),
            LinePoint(x: 3_000, y: 15),
            LinePoint(x: 4_000, y: 15)
        ])
    }

    func testBuildsStatisticsSourceBoundaryMetadata() {
        let entity = LineChartEntity(
            domain: "sensor",
            name: "Power",
            entityID: "sensor.power",
            states: [
                LineChartState(state: "3", lastChanged: 3_000)
            ],
            statistics: [
                LineChartState(state: "1", lastChanged: 1_000),
                LineChartState(state: "2", lastChanged: 2_000),
                LineChartState(state: "99", lastChanged: 3_000)
            ]
        )

        let result = LineSeriesBuilder.buildSeries(
            data: [entity],
            unit: "W",
            endTime: 4_000
        )
        let series = result.series.first

        XCTAssertEqual(series?.points, [
            LinePoint(x: 1_000, y: 1, source: .statistics),
            LinePoint(x: 2_000, y: 2, source: .statistics),
            LinePoint(x: 3_000, y: 3, source: .history),
            LinePoint(x: 4_000, y: 3, source: .history)
        ])
        XCTAssertEqual(series?.sourceRanges, [
            LineSeriesSourceRange(source: .statistics, endX: 2_999.99, alpha: 0.5),
            LineSeriesSourceRange(source: .history, startX: 3_000, alpha: 1)
        ])
    }

    func testAppendsCurrentStateForRecentSingleSensorCharts() {
        let entity = LineChartEntity(
            domain: "sensor",
            name: "Power",
            entityID: "sensor.power",
            states: [
                LineChartState(state: "10", lastChanged: 1_000)
            ]
        )
        let currentState = makeLineSeriesEntity(
            entityID: "sensor.power",
            state: "12.5",
            attributes: ["unit_of_measurement": .string("W")]
        )

        let result = LineSeriesBuilder.buildSeries(
            data: [entity],
            unit: "W",
            endTime: 2_000,
            now: 2_500,
            currentStates: ["sensor.power": currentState]
        )

        XCTAssertEqual(result.series.first?.points, [
            LinePoint(x: 1_000, y: 10),
            LinePoint(x: 2_000, y: 10),
            LinePoint(x: 2_500, y: 12.5, source: .generated)
        ])
        XCTAssertEqual(result.yAxis.maximum, 12.5)
    }

    func testBuildsBasicClimateAttributeSeries() {
        let entity = LineChartEntity(
            domain: "climate",
            name: "Thermostat",
            entityID: "climate.thermostat",
            states: [
                LineChartState(state: "heat", lastChanged: 1_000, attributes: [
                    "current_temperature": .double(20.5),
                    "temperature": .integer(22)
                ]),
                LineChartState(state: "heat", lastChanged: 2_000, attributes: [
                    "current_temperature": .double(21),
                    "temperature": .integer(23)
                ])
            ]
        )

        let result = LineSeriesBuilder.buildSeries(
            data: [entity],
            unit: "\u{00B0}C",
            deviceClass: "temperature",
            endTime: 3_000
        )

        XCTAssertEqual(result.series.map(\.id), [
            "climate.thermostat-current_temperature",
            "climate.thermostat-target_temperature"
        ])
        XCTAssertEqual(result.series[0].points.map(\.y), [20.5, 21, 21])
        XCTAssertEqual(result.series[1].points.map(\.y), [22, 23, 23])
    }

    func testBuildsTimelineRowsWithDeterministicColors() {
        let motion = TimelineEntity(
            name: "Motion",
            entityID: "binary_sensor.motion",
            data: [
                TimelineState(stateLocalized: "Detected", state: "on", lastChanged: 1_000),
                TimelineState(stateLocalized: "Clear", state: "off", lastChanged: 3_000)
            ]
        )
        let currentState = makeLineSeriesEntity(
            entityID: "binary_sensor.motion",
            state: "off",
            attributes: ["device_class": .string("motion")]
        )

        let result = TimelineSeriesBuilder.buildRows(
            from: [motion],
            endTime: 5_000,
            currentStates: ["binary_sensor.motion": currentState]
        )

        XCTAssertEqual(result.rows, [
            TimelineRow(entityID: "binary_sensor.motion", name: "Motion", segments: [
                TimelineSegment(
                    start: 1_000,
                    end: 3_000,
                    state: "on",
                    stateLocalized: "Detected",
                    colorHex: HAStateColorResolver.active.hex,
                    colorName: HAStateColorResolver.active.name
                ),
                TimelineSegment(
                    start: 3_000,
                    end: 5_000,
                    state: "off",
                    stateLocalized: "Clear",
                    colorHex: HAStateColorResolver.inactive.hex,
                    colorName: HAStateColorResolver.inactive.name
                )
            ])
        ])
        XCTAssertEqual(result.legendItems.map(\.label), ["Detected", "Clear"])
    }
}

private func makeLineSeriesEntity(
    entityID: EntityID,
    state: String,
    attributes: [String: HAJSONValue]
) -> HassEntity {
    HassEntity(
        entityID: entityID,
        state: state,
        attributes: attributes,
        lastChanged: Date(timeIntervalSince1970: 1_000),
        lastUpdated: Date(timeIntervalSince1970: 1_000),
        context: HAContext(id: "line-series-test")
    )
}
