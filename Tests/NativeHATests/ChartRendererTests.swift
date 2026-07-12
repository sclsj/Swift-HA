import XCTest
@testable import NativeHA
@testable import NativeHACore

final class ChartGeometryScaleTests: XCTestCase {
    func testXScaleMapsRangeEdgesToPlotEdges() {
        let plotRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let scale = AxisScale.xScale(
            visibleRange: ChartVisibleRange(1_000, 2_000),
            plotRect: plotRect
        )

        XCTAssertEqual(Double(scale.pixel(for: 1_000)), 10, accuracy: 0.001)
        XCTAssertEqual(Double(scale.pixel(for: 2_000)), 110, accuracy: 0.001)
    }

    func testXInverseMappingReturnsTimestamp() {
        let plotRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let scale = AxisScale.xScale(
            visibleRange: ChartVisibleRange(1_000, 2_000),
            plotRect: plotRect
        )

        XCTAssertEqual(scale.value(for: 60), 1_500, accuracy: 0.001)
    }

    func testYScaleMapsMinimumToBottomAndMaximumToTop() {
        let plotRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        let scale = AxisScale.yScale(
            domain: ChartValueRange(10, 20),
            plotRect: plotRect
        )

        XCTAssertEqual(Double(scale.pixel(for: 10)), 70, accuracy: 0.001)
        XCTAssertEqual(Double(scale.pixel(for: 20)), 20, accuracy: 0.001)
    }

    func testFlatYRangeExpandsSafely() {
        let series = [
            makeLineSeries(points: [
                LinePoint(x: 0, y: 5),
                LinePoint(x: 10, y: 5)
            ])
        ]

        let domain = AxisScale.lineYDomain(
            in: series,
            visibleRange: ChartVisibleRange(0, 10)
        )

        XCTAssertEqual(domain.lowerBound, 4, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 6, accuracy: 0.001)
    }

    func testEmptyDataCreatesDefaultYDomain() {
        let domain = AxisScale.lineYDomain(
            in: [],
            visibleRange: ChartVisibleRange(0, 10)
        )

        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertEqual(domain.upperBound, 1)
    }

    func testFixedYAxisCanExpandWhenFitYDataIsEnabled() {
        let series = [
            makeLineSeries(points: [
                LinePoint(x: 0, y: 5),
                LinePoint(x: 10, y: 20)
            ])
        ]

        let fixed = AxisScale.lineYDomain(
            in: series,
            visibleRange: ChartVisibleRange(0, 10),
            fixedMinimum: 10,
            fixedMaximum: 15
        )
        let fit = AxisScale.lineYDomain(
            in: series,
            visibleRange: ChartVisibleRange(0, 10),
            fixedMinimum: 10,
            fixedMaximum: 15,
            fitYData: true
        )

        XCTAssertEqual(fixed.lowerBound, 10, accuracy: 0.001)
        XCTAssertEqual(fixed.upperBound, 15, accuracy: 0.001)
        XCTAssertEqual(fit.lowerBound, 5, accuracy: 0.001)
        XCTAssertEqual(fit.upperBound, 20, accuracy: 0.001)
    }

    func testLogarithmicYDomainIgnoresNonPositiveValues() {
        let series = [
            makeLineSeries(points: [
                LinePoint(x: 0, y: -5),
                LinePoint(x: 5, y: 0),
                LinePoint(x: 10, y: 10),
                LinePoint(x: 20, y: 100)
            ])
        ]

        let domain = AxisScale.lineYDomain(
            in: series,
            visibleRange: ChartVisibleRange(0, 20),
            scaleKind: .logarithmic
        )
        let scale = AxisScale.yScale(
            domain: domain,
            plotRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            kind: .logarithmic
        )

        XCTAssertGreaterThan(domain.lowerBound, 0)
        XCTAssertNil(scale.pixelIfValid(for: 0))
        XCTAssertNotNil(scale.pixelIfValid(for: 10))
        XCTAssertEqual(scale.value(for: scale.pixel(for: 100)), 100, accuracy: 0.001)
    }
}

final class LineChartPreparationTests: XCTestCase {
    func testNilGapSegmentationDoesNotConnectFiniteRuns() {
        let chart = prepareLineChart(points: [
            LinePoint(x: 0, y: 1),
            LinePoint(x: 10, y: 1),
            LinePoint(x: 11, y: nil),
            LinePoint(x: 20, y: 2),
            LinePoint(x: 30, y: 2)
        ])
        let segments = chart.series[0].segments

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].points.map(\.timestamp), [0, 10])
        XCTAssertEqual(segments[1].points.map(\.timestamp), [20, 30])
    }

    func testStepEndPathPointsAreCorrect() {
        let chart = prepareLineChart(points: [
            LinePoint(x: 0, y: 1),
            LinePoint(x: 10, y: 3),
            LinePoint(x: 20, y: 2)
        ])
        let points = chart.series[0].segments[0].points

        XCTAssertEqual(points.map(\.timestamp), [0, 10, 10, 20, 20])
        XCTAssertEqual(points.map(\.value), [1, 1, 3, 3, 2])
    }

    func testSinglePointSeriesProducesStableMarker() {
        let chart = prepareLineChart(points: [
            LinePoint(x: 5, y: 4)
        ])

        XCTAssertEqual(chart.series[0].segments.count, 0)
        XCTAssertEqual(chart.series[0].singlePoints.count, 1)
        XCTAssertEqual(chart.series[0].singlePoints[0].timestamp, 5)
    }

    func testAllNullSeriesProducesNoDrawablePath() {
        let chart = prepareLineChart(points: [
            LinePoint(x: 0, y: nil),
            LinePoint(x: 10, y: nil)
        ])

        XCTAssertEqual(chart.series[0].segments.count, 0)
        XCTAssertEqual(chart.series[0].singlePoints.count, 0)
        XCTAssertEqual(chart.drawableVertexCount, 0)
    }

    func testVisibleRangeClippingExcludesOffscreenPointsSafely() {
        let chart = prepareLineChart(
            points: [
                LinePoint(x: -10, y: 1),
                LinePoint(x: 10, y: 2),
                LinePoint(x: 30, y: 3)
            ],
            visibleRange: ChartVisibleRange(0, 20)
        )
        let points = chart.series[0].segments[0].points

        XCTAssertEqual(points.map(\.timestamp), [0, 10, 10, 20])
        XCTAssertEqual(points.map(\.value), [1, 1, 2, 2])
        XCTAssertTrue(points.allSatisfy { chart.visibleRange.contains($0.timestamp) })
    }

    func testDownsampledVisibleWindowKeepsStepBoundaryPoints() {
        let chart = LineChartRenderer.prepare(
            series: [
                makeLineSeries(points: [
                    LinePoint(x: 0, y: 12),
                    LinePoint(x: 100, y: 12)
                ])
            ],
            visibleRange: ChartVisibleRange(40, 60),
            size: defaultChartSize,
            maximumDetail: 1
        )
        let points = chart.series[0].segments[0].points

        XCTAssertEqual(points.map(\.timestamp), [40, 60])
        XCTAssertEqual(points.map(\.value), [12, 12])
    }

    func testDownsampledVisibleWindowPreservesNullBreaks() {
        let chart = LineChartRenderer.prepare(
            series: [
                makeLineSeries(points: [
                    LinePoint(x: 0, y: 1),
                    LinePoint(x: 50, y: 1),
                    LinePoint(x: 51, y: nil),
                    LinePoint(x: 100, y: 2)
                ])
            ],
            visibleRange: ChartVisibleRange(40, 60),
            size: defaultChartSize,
            maximumDetail: 1
        )

        XCTAssertEqual(chart.series[0].segments.count, 1)
        XCTAssertEqual(chart.series[0].segments[0].points.map(\.timestamp), [40, 50])
        XCTAssertEqual(chart.series[0].segments[0].points.map(\.value), [1, 1])
    }

    func testLogarithmicPreparationSkipsNonPositivePoints() {
        let chart = LineChartRenderer.prepare(
            series: [
                makeLineSeries(points: [
                    LinePoint(x: 0, y: -5),
                    LinePoint(x: 5, y: 0),
                    LinePoint(x: 10, y: 10),
                    LinePoint(x: 20, y: 100)
                ])
            ],
            visibleRange: ChartVisibleRange(0, 20),
            size: defaultChartSize,
            logarithmicScale: true
        )
        let values = chart.series[0].segments.flatMap(\.points).map(\.value)

        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { $0 > 0 })
        XCTAssertNil(LineChartRenderer.nearestTooltip(in: chart, timestamp: 5)?.item)
    }

    func testStatisticsSourceMetadataSurvivesRenderPreparation() {
        let sourceRanges = [
            LineSeriesSourceRange(source: .statistics, endX: 4.99, alpha: 0.5),
            LineSeriesSourceRange(source: .history, startX: 5, alpha: 1)
        ]
        let chart = prepareLineChart(
            series: makeLineSeries(
                points: [
                    LinePoint(x: 0, y: 1, source: .statistics),
                    LinePoint(x: 10, y: 2, source: .history)
                ],
                sourceRanges: sourceRanges
            )
        )

        XCTAssertEqual(chart.series[0].sourceRanges, sourceRanges)
        XCTAssertEqual(chart.series[0].segments.map(\.alpha), [0.5, 1])
        XCTAssertEqual(chart.series[0].segments.map(\.source), [.statistics, .history])
    }

    func testTooltipLookupRespectsNullGapsAndVisibleRange() {
        let series = makeLineSeries(points: [
            LinePoint(x: 0, y: 1),
            LinePoint(x: 10, y: nil),
            LinePoint(x: 20, y: 2)
        ])
        let visibleRange = ChartVisibleRange(0, 30)

        XCTAssertEqual(
            LineChartRenderer.lineValue(at: 5, in: series, visibleRange: visibleRange)?.y,
            1
        )
        XCTAssertNil(LineChartRenderer.lineValue(at: 15, in: series, visibleRange: visibleRange))
        XCTAssertEqual(
            LineChartRenderer.lineValue(at: 25, in: series, visibleRange: visibleRange)?.y,
            2
        )
        XCTAssertNil(LineChartRenderer.lineValue(at: 35, in: series, visibleRange: visibleRange))
    }

    func testNearestLineTooltipReturnsExpectedSeriesPoint() {
        let chart = LineChartRenderer.prepare(
            series: [
                makeLineSeries(
                    id: "sensor.a",
                    name: "A",
                    points: [LinePoint(x: 0, y: 1), LinePoint(x: 10, y: 1)]
                ),
                makeLineSeries(
                    id: "sensor.b",
                    name: "B",
                    points: [LinePoint(x: 0, y: 8), LinePoint(x: 10, y: 8)]
                )
            ],
            visibleRange: ChartVisibleRange(0, 10),
            size: defaultChartSize
        )
        let y = chart.geometry.yScale!.pixel(for: 8)
        let tooltip = LineChartRenderer.nearestTooltip(
            in: chart,
            timestamp: 5,
            screenLocation: CGPoint(x: chart.geometry.xScale.pixel(for: 5), y: y)
        )

        guard case let .line(item)? = tooltip?.item else {
            XCTFail("Expected line tooltip")
            return
        }
        XCTAssertEqual(item.seriesID, "sensor.b")
        XCTAssertEqual(item.value, 8)
    }

    func testLargeLineSeriesPreparationIsDeterministicAfterDownsampling() {
        let series = makeLineSeries(points: generatedLinePoints(count: 100_000))
        let first = LineChartRenderer.prepare(
            series: [series],
            visibleRange: ChartVisibleRange(0, 99_999),
            size: defaultChartSize,
            maximumDetail: 500
        )
        let second = LineChartRenderer.prepare(
            series: [series],
            visibleRange: ChartVisibleRange(0, 99_999),
            size: defaultChartSize,
            maximumDetail: 500
        )

        XCTAssertEqual(first, second)
        XCTAssertLessThanOrEqual(first.drawableVertexCount, 2_100)
    }
}

final class TimelineChartPreparationTests: XCTestCase {
    func testTimelineIntervalClippingToVisibleRange() {
        let chart = prepareTimelineChart(rows: [
            TimelineRow(entityID: "binary_sensor.motion", name: "Motion", segments: [
                TimelineSegment(start: 0, end: 100, state: "on", stateLocalized: "Detected", colorHex: "#fdd663")
            ])
        ], visibleRange: ChartVisibleRange(25, 75))
        let segment = chart.rows[0].segments[0]

        XCTAssertEqual(segment.clippedStart, 25)
        XCTAssertEqual(segment.clippedEnd, 75)
        XCTAssertEqual(segment.rect.minX, chart.geometry.plotRect.minX, accuracy: 0.001)
        XCTAssertEqual(segment.rect.maxX, chart.geometry.plotRect.maxX, accuracy: 0.001)
    }

    func testTimelineRowLayoutIsDeterministic() {
        let chart = prepareTimelineChart(rows: [
            timelineRow(entityID: "binary_sensor.a", name: "A"),
            timelineRow(entityID: "binary_sensor.b", name: "B")
        ])

        XCTAssertEqual(chart.rows.map(\.entityID), ["binary_sensor.a", "binary_sensor.b"])
        XCTAssertEqual(chart.rows.map(\.index), [0, 1])
        XCTAssertLessThan(chart.rows[0].rect.minY, chart.rows[1].rect.minY)
    }

    func testZeroDurationTimelineIntervalDoesNotCrash() {
        let chart = prepareTimelineChart(rows: [
            TimelineRow(entityID: "binary_sensor.motion", name: "Motion", segments: [
                TimelineSegment(start: 50, end: 50, state: "on", stateLocalized: "Detected", colorHex: "#fdd663")
            ])
        ])

        XCTAssertEqual(chart.drawableSegmentCount, 1)
        XCTAssertGreaterThanOrEqual(chart.rows[0].segments[0].rect.width, 0)
    }

    func testZeroDurationTimelineIntervalAtUpperBoundRemainsVisible() {
        let chart = prepareTimelineChart(rows: [
            TimelineRow(entityID: "binary_sensor.motion", name: "Motion", segments: [
                TimelineSegment(start: 100, end: 100, state: "on", stateLocalized: "Detected", colorHex: "#fdd663")
            ])
        ])
        let rect = chart.rows[0].segments[0].rect

        XCTAssertGreaterThanOrEqual(rect.width, 1)
        XCTAssertLessThanOrEqual(rect.maxX, chart.geometry.plotRect.maxX)
    }

    func testTimelineDeterministicColorAssignmentIsPreserved() {
        let chart = prepareTimelineChart(rows: [
            TimelineRow(entityID: "sensor.mode", name: "Mode", segments: [
                TimelineSegment(start: 0, end: 100, state: "eco", stateLocalized: "Eco", colorHex: "#123456")
            ])
        ])

        XCTAssertEqual(chart.rows[0].segments[0].colorHex, "#123456")
    }

    func testTimelineLabelsAreHiddenWhenTheyCannotFit() {
        let chart = prepareTimelineChart(
            rows: [
                TimelineRow(entityID: "sensor.mode", name: "Mode", segments: [
                    TimelineSegment(
                        start: 0,
                        end: 1,
                        state: "very_long_state",
                        stateLocalized: "Very long state name",
                        colorHex: "#123456"
                    )
                ])
            ],
            visibleRange: ChartVisibleRange(0, 100)
        )

        XCTAssertFalse(chart.rows[0].segments[0].labelVisible)
    }

    func testTimelineHitTestingReturnsExpectedInterval() {
        let chart = prepareTimelineChart(rows: [
            TimelineRow(entityID: "binary_sensor.motion", name: "Motion", segments: [
                TimelineSegment(start: 0, end: 40, state: "off", stateLocalized: "Clear", colorHex: "#44739e"),
                TimelineSegment(start: 40, end: 100, state: "on", stateLocalized: "Detected", colorHex: "#fdd663")
            ])
        ])
        let target = chart.rows[0].segments[1].rect
        let tooltip = TimelineChartRenderer.hitTest(
            chart,
            point: CGPoint(x: target.midX, y: target.midY)
        )

        guard case let .timeline(item)? = tooltip?.item else {
            XCTFail("Expected timeline tooltip")
            return
        }
        XCTAssertEqual(item.entityID, "binary_sensor.motion")
        XCTAssertEqual(item.state, "on")
        XCTAssertEqual(item.start, 40)
        XCTAssertEqual(item.end, 100)
    }

    func testLargeTimelineIntervalLayoutIsDeterministic() {
        let rows = (0..<10).map { rowIndex in
            TimelineRow(
                entityID: "sensor.mode_\(rowIndex)",
                name: "Mode \(rowIndex)",
                segments: (0..<1_000).map { index in
                    TimelineSegment(
                        start: Double(index * 10),
                        end: Double(index * 10 + 10),
                        state: index % 2 == 0 ? "on" : "off",
                        stateLocalized: index % 2 == 0 ? "On" : "Off",
                        colorHex: index % 2 == 0 ? "#fdd663" : "#44739e"
                    )
                }
            )
        }

        let first = prepareTimelineChart(rows: rows, visibleRange: ChartVisibleRange(0, 10_000))
        let second = prepareTimelineChart(rows: rows, visibleRange: ChartVisibleRange(0, 10_000))

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.drawableSegmentCount, 10_000)
    }
}

final class ChartInteractionTests: XCTestCase {
    func testPanShiftsVisibleRangeByExpectedAmount() {
        var state = ChartInteractionState(
            dataBounds: ChartVisibleRange(0, 100),
            visibleRange: ChartVisibleRange(20, 60)
        )

        state.pan(pixelDelta: 20, plotWidth: 200)

        XCTAssertEqual(state.visibleRange.lowerBound, 16, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.upperBound, 56, accuracy: 0.001)
    }

    func testZoomAboutCenterPreservesCenter() {
        var state = ChartInteractionState(dataBounds: ChartVisibleRange(0, 100))

        state.zoom(magnification: 2)

        XCTAssertEqual(state.visibleRange.lowerBound, 25, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.upperBound, 75, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.midpoint, 50, accuracy: 0.001)
    }

    func testZoomAboutAnchorPreservesAnchorTimestampPosition() {
        var state = ChartInteractionState(dataBounds: ChartVisibleRange(0, 100))

        state.zoom(magnification: 2, anchorTimestamp: 25)

        XCTAssertEqual(state.visibleRange.lowerBound, 12.5, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.upperBound, 62.5, accuracy: 0.001)
    }

    func testVisibleRangeIsClampedToDataBounds() {
        var state = ChartInteractionState(
            dataBounds: ChartVisibleRange(0, 100),
            visibleRange: ChartVisibleRange(10, 50)
        )

        state.pan(pixelDelta: -1_000, plotWidth: 200)

        XCTAssertEqual(state.visibleRange.lowerBound, 60, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.upperBound, 100, accuracy: 0.001)
    }

    func testResetRestoresOriginalRange() {
        var state = ChartInteractionState(dataBounds: ChartVisibleRange(0, 100))
        state.zoom(magnification: 2)

        state.reset()

        XCTAssertEqual(state.visibleRange, ChartVisibleRange(0, 100))
        XCTAssertFalse(state.isZoomed)
    }

    func testPercentageRangeRoundTrips() {
        var state = ChartInteractionState(dataBounds: ChartVisibleRange(0, 200))

        state.setPercentageRange(start: 25, end: 75)

        XCTAssertEqual(state.visibleRange.lowerBound, 50, accuracy: 0.001)
        XCTAssertEqual(state.visibleRange.upperBound, 150, accuracy: 0.001)
        XCTAssertEqual(state.percentageRange.start, 25, accuracy: 0.001)
        XCTAssertEqual(state.percentageRange.end, 75, accuracy: 0.001)
    }

    func testReplacingDataBoundsTracksUnzoomedWindow() {
        let state = ChartInteractionState(dataBounds: ChartVisibleRange(0, 100))

        let updated = state.replacingDataBounds(ChartVisibleRange(10, 110))

        XCTAssertEqual(updated.dataBounds, ChartVisibleRange(10, 110))
        XCTAssertEqual(updated.visibleRange, ChartVisibleRange(10, 110))
    }

    func testReplacingDataBoundsClampsZoomedWindow() {
        var state = ChartInteractionState(
            dataBounds: ChartVisibleRange(0, 100),
            visibleRange: ChartVisibleRange(40, 80)
        )
        state.pan(pixelDelta: -40, plotWidth: 200)

        let updated = state.replacingDataBounds(ChartVisibleRange(0, 70))

        XCTAssertEqual(updated.visibleRange.lowerBound, 30, accuracy: 0.001)
        XCTAssertEqual(updated.visibleRange.upperBound, 70, accuracy: 0.001)
    }
}

private let defaultChartSize = CGSize(width: 244, height: 128)

private func prepareLineChart(
    series: LineSeries,
    visibleRange: ChartVisibleRange = ChartVisibleRange(0, 40)
) -> PreparedLineChart {
    LineChartRenderer.prepare(
        series: [series],
        visibleRange: visibleRange,
        size: defaultChartSize
    )
}

private func prepareLineChart(
    points: [LinePoint],
    visibleRange: ChartVisibleRange = ChartVisibleRange(0, 40)
) -> PreparedLineChart {
    prepareLineChart(series: makeLineSeries(points: points), visibleRange: visibleRange)
}

private func makeLineSeries(
    id: String = "sensor.power",
    name: String = "Power",
    points: [LinePoint],
    sourceRanges: [LineSeriesSourceRange] = []
) -> LineSeries {
    LineSeries(
        id: id,
        entityID: id,
        name: name,
        unit: "W",
        deviceClass: "power",
        colorHex: "#4269d0",
        points: points,
        sourceRanges: sourceRanges
    )
}

private func generatedLinePoints(count: Int) -> [LinePoint] {
    (0..<count).map { index in
        let x = Double(index)
        let y = 50 + sin(Double(index) / 9) * 20 + cos(Double(index) / 17) * 8
        return LinePoint(x: x, y: y)
    }
}

private func prepareTimelineChart(
    rows: [TimelineRow],
    visibleRange: ChartVisibleRange = ChartVisibleRange(0, 100)
) -> PreparedTimelineChart {
    TimelineChartRenderer.prepare(
        rows: rows,
        visibleRange: visibleRange,
        size: CGSize(width: 260, height: 140)
    )
}

private func timelineRow(entityID: EntityID, name: String) -> TimelineRow {
    TimelineRow(entityID: entityID, name: name, segments: [
        TimelineSegment(start: 0, end: 100, state: "on", stateLocalized: "On", colorHex: "#fdd663")
    ])
}
