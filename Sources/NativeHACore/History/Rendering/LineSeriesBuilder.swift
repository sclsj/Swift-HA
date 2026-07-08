import Foundation

public enum LineSeriesBuilder {
    public static let defaultPalette = [
        "#4269d0",
        "#f4bd4a",
        "#ff725c",
        "#6cc5b0",
        "#3ca951",
        "#ff8ab7",
        "#a463f2",
        "#97bbf5",
        "#9c6b4e",
        "#9498a0"
    ]

    public static func buildSeries(
        for unit: LineChartUnit,
        endTime: Double,
        now: Double? = nil,
        currentStates: [EntityID: HassEntity] = [:],
        names: [EntityID: String] = [:],
        colors: [EntityID: String] = [:],
        palette: [String] = defaultPalette,
        showNames: Bool = true
    ) -> LineSeriesBuildResult {
        buildSeries(
            data: unit.data,
            unit: unit.unit,
            deviceClass: unit.deviceClass,
            endTime: endTime,
            now: now,
            currentStates: currentStates,
            names: names,
            colors: colors,
            palette: palette,
            showNames: showNames
        )
    }

    public static func buildSeries(
        data: [LineChartEntity],
        unit: String? = nil,
        deviceClass: String? = nil,
        endTime: Double,
        now: Double? = nil,
        currentStates: [EntityID: HassEntity] = [:],
        names: [EntityID: String] = [:],
        colors: [EntityID: String] = [:],
        palette: [String] = defaultPalette,
        showNames: Bool = true
    ) -> LineSeriesBuildResult {
        var colorAllocator = ColorAllocator(palette: palette)
        var allSeries: [LineSeries] = []
        var legendItems: [LegendItem] = []
        var entityIDs: [EntityID] = []
        var seriesToEntityIndex: [Int] = []

        for (dataIndex, entity) in data.enumerated() {
            let displayName = names[entity.entityID] ?? entity.name
            let builtSeries: [LineSeries]

            switch entity.domain {
            case "climate", "thermostat", "water_heater":
                builtSeries = buildClimateSeries(
                    entity: entity,
                    displayName: displayName,
                    unit: unit,
                    deviceClass: deviceClass,
                    endTime: endTime,
                    configuredColor: colors[entity.entityID],
                    colorAllocator: &colorAllocator,
                    showNames: showNames
                )
            case "humidifier":
                builtSeries = buildHumidifierSeries(
                    entity: entity,
                    displayName: displayName,
                    unit: unit,
                    deviceClass: deviceClass,
                    endTime: endTime,
                    configuredColor: colors[entity.entityID],
                    colorAllocator: &colorAllocator,
                    showNames: showNames
                )
            default:
                builtSeries = buildNumericSeries(
                    entity: entity,
                    displayName: displayName,
                    unit: unit,
                    deviceClass: deviceClass,
                    endTime: endTime,
                    now: now,
                    currentState: currentStates[entity.entityID],
                    configuredColor: colors[entity.entityID],
                    colorAllocator: &colorAllocator
                )
            }

            guard !builtSeries.isEmpty else {
                continue
            }

            allSeries.append(contentsOf: builtSeries)
            entityIDs.append(contentsOf: builtSeries.map(\.entityID))
            seriesToEntityIndex.append(contentsOf: Array(repeating: dataIndex, count: builtSeries.count))
            legendItems.append(LegendItem(
                id: entity.entityID,
                entityID: entity.entityID,
                label: displayName,
                colorHex: builtSeries.first?.colorHex,
                seriesIDs: builtSeries.map(\.id)
            ))
        }

        let bounds = yBounds(in: allSeries)
        return LineSeriesBuildResult(
            series: allSeries,
            legendItems: legendItems,
            yAxis: AxisLabelFormatter.metadata(
                unit: unit,
                deviceClass: deviceClass,
                minimum: bounds.minimum,
                maximum: bounds.maximum
            ),
            entityIDs: entityIDs,
            seriesToEntityIndex: seriesToEntityIndex
        )
    }

    private static func buildNumericSeries(
        entity: LineChartEntity,
        displayName: String,
        unit: String?,
        deviceClass: String?,
        endTime: Double,
        now: Double?,
        currentState: HassEntity?,
        configuredColor: String?,
        colorAllocator: inout ColorAllocator
    ) -> [LineSeries] {
        let sourceRanges = statisticsSourceRanges(for: entity, endTime: endTime)
        let draft = LineSeriesDraft(
            id: entity.entityID,
            entityID: entity.entityID,
            name: displayName,
            unit: unit,
            deviceClass: deviceClass,
            colorHex: colorAllocator.nextColor(configured: configuredColor),
            isFilled: false,
            sourceRanges: sourceRanges
        )
        var accumulator = LineSeriesAccumulator(drafts: [draft], endTime: endTime)

        let firstHistoryTimestamp = entity.states.first?.lastChanged
        if let statistics = entity.statistics {
            for state in statistics {
                if let firstHistoryTimestamp = firstHistoryTimestamp,
                   state.lastChanged >= firstHistoryTimestamp {
                    break
                }
                accumulator.push(
                    timestamp: state.lastChanged,
                    values: [parseFiniteDouble(state.state)],
                    source: .statistics
                )
            }
        }

        for state in entity.states {
            accumulator.push(
                timestamp: state.lastChanged,
                values: [parseFiniteDouble(state.state)],
                source: .history
            )
        }
        accumulator.appendFinalPoint()

        var series = accumulator.series()
        if shouldAppendCurrentSensorState(entity: entity, endTime: endTime, now: now),
           let now = now,
           let currentValue = currentState.flatMap({ parseFiniteDouble($0.state) }),
           !series.isEmpty {
            series[0].points.append(LinePoint(x: now, y: currentValue, source: .generated))
        }
        return series
    }

    private static func buildClimateSeries(
        entity: LineChartEntity,
        displayName: String,
        unit: String?,
        deviceClass: String?,
        endTime: Double,
        configuredColor: String?,
        colorAllocator: inout ColorAllocator,
        showNames: Bool
    ) -> [LineSeries] {
        let states = entity.states
        guard !states.isEmpty else {
            return []
        }

        let hasTargetRange = states.contains { state in
            guard let attributes = state.attributes,
                  let high = parseFiniteDouble(attributes["target_temp_high"]),
                  let low = parseFiniteDouble(attributes["target_temp_low"]) else {
                return false
            }
            return high != low
        }

        var drafts = [
            LineSeriesDraft(
                id: entity.entityID + "-current_temperature",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) current temperature" : "Current temperature",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(configured: configuredColor),
                isFilled: false,
                sourceRanges: []
            )
        ]

        if hasTargetRange {
            drafts.append(LineSeriesDraft(
                id: entity.entityID + "-target_temperature_high",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) target high" : "Target high",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(),
                isFilled: false,
                sourceRanges: []
            ))
            drafts.append(LineSeriesDraft(
                id: entity.entityID + "-target_temperature_low",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) target low" : "Target low",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(),
                isFilled: false,
                sourceRanges: []
            ))
        } else {
            drafts.append(LineSeriesDraft(
                id: entity.entityID + "-target_temperature",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) target temperature" : "Target temperature",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(),
                isFilled: false,
                sourceRanges: []
            ))
        }

        var accumulator = LineSeriesAccumulator(drafts: drafts, endTime: endTime)
        for state in states {
            guard let attributes = state.attributes else {
                continue
            }
            let values: [Double?]
            if hasTargetRange {
                values = [
                    parseFiniteDouble(attributes["current_temperature"]),
                    parseFiniteDouble(attributes["target_temp_high"]),
                    parseFiniteDouble(attributes["target_temp_low"])
                ]
            } else {
                values = [
                    parseFiniteDouble(attributes["current_temperature"]),
                    parseFiniteDouble(attributes["temperature"])
                ]
            }
            accumulator.push(timestamp: state.lastChanged, values: values, source: .history)
        }
        accumulator.appendFinalPoint()
        return accumulator.series()
    }

    private static func buildHumidifierSeries(
        entity: LineChartEntity,
        displayName: String,
        unit: String?,
        deviceClass: String?,
        endTime: Double,
        configuredColor: String?,
        colorAllocator: inout ColorAllocator,
        showNames: Bool
    ) -> [LineSeries] {
        let states = entity.states
        guard !states.isEmpty else {
            return []
        }
        let hasCurrent = states.contains {
            $0.attributes?["current_humidity"] != nil
        }

        var drafts = [
            LineSeriesDraft(
                id: entity.entityID + "-target_humidity",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) target humidity" : "Target humidity",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(configured: configuredColor),
                isFilled: false,
                sourceRanges: []
            )
        ]
        if hasCurrent {
            drafts.append(LineSeriesDraft(
                id: entity.entityID + "-current_humidity",
                entityID: entity.entityID,
                name: showNames ? "\(displayName) current humidity" : "Current humidity",
                unit: unit,
                deviceClass: deviceClass,
                colorHex: colorAllocator.nextColor(),
                isFilled: false,
                sourceRanges: []
            ))
        }

        var accumulator = LineSeriesAccumulator(drafts: drafts, endTime: endTime)
        for state in states {
            guard let attributes = state.attributes else {
                continue
            }
            let target = parseFiniteDouble(attributes["humidity"])
            let values = hasCurrent
                ? [target, parseFiniteDouble(attributes["current_humidity"])]
                : [target]
            accumulator.push(timestamp: state.lastChanged, values: values, source: .history)
        }
        accumulator.appendFinalPoint()
        return accumulator.series()
    }

    private static func statisticsSourceRanges(
        for entity: LineChartEntity,
        endTime: Double
    ) -> [LineSeriesSourceRange] {
        guard entity.statistics?.isEmpty == false else {
            return []
        }

        let firstHistoryTimestamp = entity.states.first?.lastChanged ?? endTime
        return [
            LineSeriesSourceRange(
                source: .statistics,
                endX: firstHistoryTimestamp - 0.01,
                alpha: 0.5
            ),
            LineSeriesSourceRange(
                source: .history,
                startX: firstHistoryTimestamp,
                alpha: 1
            )
        ]
    }

    private static func shouldAppendCurrentSensorState(
        entity: LineChartEntity,
        endTime: Double,
        now: Double?
    ) -> Bool {
        guard entity.domain == "sensor", let now = now else {
            return false
        }
        return now - endTime <= 1_000
    }

    private static func yBounds(in series: [LineSeries]) -> (minimum: Double?, maximum: Double?) {
        var minimum: Double?
        var maximum: Double?

        for item in series {
            for point in item.points {
                guard let value = point.y, value.isFinite else {
                    continue
                }
                minimum = minimum.map { min($0, value) } ?? value
                maximum = maximum.map { max($0, value) } ?? value
            }
        }

        return (minimum, maximum)
    }

    private static func parseFiniteDouble(_ value: String) -> Double? {
        guard let parsed = Double(value), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    private static func parseFiniteDouble(_ value: HAJSONValue?) -> Double? {
        guard let value = value else {
            return nil
        }

        let parsed: Double?
        switch value {
        case let .integer(number):
            parsed = Double(number)
        case let .double(number):
            parsed = number
        case let .string(string):
            parsed = Double(string)
        default:
            parsed = nil
        }

        guard let parsed = parsed, parsed.isFinite else {
            return nil
        }
        return parsed
    }
}

private struct ColorAllocator {
    var palette: [String]
    private var index = 0

    init(palette: [String]) {
        self.palette = palette.isEmpty ? LineSeriesBuilder.defaultPalette : palette
    }

    mutating func nextColor(configured: String? = nil) -> String {
        if let configured = configured, !configured.isEmpty {
            return configured
        }

        let color = palette[index % palette.count]
        index += 1
        return color
    }
}

private struct LineSeriesDraft {
    var id: String
    var entityID: EntityID
    var name: String
    var unit: String?
    var deviceClass: String?
    var colorHex: String?
    var isFilled: Bool
    var sourceRanges: [LineSeriesSourceRange]
    var points: [LinePoint] = []

    func series() -> LineSeries {
        LineSeries(
            id: id,
            entityID: entityID,
            name: name,
            unit: unit,
            deviceClass: deviceClass,
            colorHex: colorHex,
            points: points,
            stepMode: .end,
            isFilled: isFilled,
            sourceRanges: sourceRanges
        )
    }
}

private struct LineSeriesAccumulator {
    private var drafts: [LineSeriesDraft]
    private let endTime: Double
    private var previousValues: [Double?]?
    private var previousSources: [LinePointSource?]?

    init(drafts: [LineSeriesDraft], endTime: Double) {
        self.drafts = drafts
        self.endTime = endTime
    }

    mutating func push(
        timestamp: Double,
        values: [Double?],
        source: LinePointSource
    ) {
        guard timestamp.isFinite, timestamp <= endTime, !drafts.isEmpty else {
            return
        }

        let values = normalizedValues(values)
        if values.allSatisfy({ $0 == nil }),
           previousValues?.allSatisfy({ $0 == nil }) == true {
            previousSources = Array(repeating: source, count: drafts.count)
            return
        }

        for index in drafts.indices {
            let value = values[index]
            if let value = value, value.isFinite {
                drafts[index].points.append(LinePoint(x: timestamp, y: value, source: source))
            } else if let previousValues = previousValues, let previousValue = previousValues[index] {
                let previousSource = previousSources?[index] ?? source
                drafts[index].points.append(LinePoint(x: timestamp, y: previousValue, source: previousSource))
                let nullTimestamp = timestamp + 1
                if nullTimestamp <= endTime {
                    drafts[index].points.append(LinePoint(x: nullTimestamp, y: nil, source: source))
                }
            } else {
                drafts[index].points.append(LinePoint(x: timestamp, y: nil, source: source))
            }
        }

        previousValues = values
        previousSources = Array(repeating: source, count: drafts.count)
    }

    mutating func appendFinalPoint() {
        guard let previousValues = previousValues, endTime.isFinite else {
            return
        }

        for index in drafts.indices {
            let source = previousSources?[index] ?? .history
            drafts[index].points.append(LinePoint(x: endTime, y: previousValues[index], source: source))
        }
    }

    func series() -> [LineSeries] {
        drafts.map { $0.series() }
    }

    private func normalizedValues(_ values: [Double?]) -> [Double?] {
        if values.count == drafts.count {
            return values.map { value in
                guard let value = value, value.isFinite else {
                    return nil
                }
                return value
            }
        }

        var normalized = Array(repeating: Optional<Double>.none, count: drafts.count)
        for index in 0..<min(values.count, drafts.count) {
            if let value = values[index], value.isFinite {
                normalized[index] = value
            }
        }
        return normalized
    }
}
