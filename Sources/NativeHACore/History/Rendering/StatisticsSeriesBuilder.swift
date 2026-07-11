import Foundation

public enum StatisticsSeriesBuilder {
    public static let defaultStatTypes: [StatisticType] = [
        .change,
        .state,
        .sum,
        .min,
        .max,
        .mean
    ]

    public static func buildSeries(
        statistics: Statistics,
        metadata: [String: StatisticsMetaData] = [:],
        statisticIDs: [String],
        statTypes requestedStatTypes: [StatisticType] = defaultStatTypes,
        chartType: StatisticsGraphChartType = .line,
        names: [EntityID: String] = [:],
        colors: [EntityID: String] = [:],
        currentStates: [EntityID: HassEntity] = [:],
        endTime: Double? = nil,
        now: Double? = nil,
        unit explicitUnit: String? = nil,
        palette: [String] = LineSeriesBuilder.defaultPalette
    ) -> LineSeriesBuildResult {
        var colorAllocator = StatisticsColorAllocator(palette: palette)
        var allSeries: [LineSeries] = []
        var legendItems: [LegendItem] = []
        var entityIDs: [EntityID] = []
        var seriesToEntityIndex: [Int] = []
        let orderedIDs = orderedStatisticIDs(statisticIDs, statistics: statistics)
        let requestedStatTypes = normalizedStatTypes(requestedStatTypes)
        let unit = explicitUnit ?? inferredUnit(for: orderedIDs, metadata: metadata)

        for (entityIndex, statisticID) in orderedIDs.enumerated() {
            guard let values = statistics[statisticID], !values.isEmpty else {
                continue
            }

            let availableTypes = requestedStatTypes.filter { statisticsHaveType(values, type: $0) }
            guard !availableTypes.isEmpty else {
                continue
            }

            let displayName = names[statisticID]
                ?? metadata[statisticID]?.displayName
                ?? statisticID
            let color = colorAllocator.nextColor(configured: colors[statisticID])
            let drafts = availableTypes.map { type in
                StatisticsLineSeriesDraft(
                    id: "\(statisticID)-\(type.rawValue)",
                    entityID: statisticID,
                    name: seriesName(displayName: displayName, type: type, multipleTypes: availableTypes.count > 1),
                    unit: unit,
                    deviceClass: metadata[statisticID]?.unitClass,
                    colorHex: color,
                    isFilled: chartType.isStacked,
                    sourceRanges: [
                        LineSeriesSourceRange(source: .statistics, alpha: 1)
                    ]
                )
            }

            var accumulator = StatisticsLineSeriesAccumulator(drafts: drafts)
            var previousStart: Double?
            var firstSum: Double?

            for value in values {
                guard value.start.isFinite, value.end.isFinite else {
                    continue
                }
                if previousStart == value.start {
                    continue
                }
                previousStart = value.start

                let pointValues = availableTypes.map { type -> Double? in
                    switch type {
                    case .sum:
                        if let baseline = firstSum {
                            return (value.sum ?? 0) - baseline
                        }
                        firstSum = value.sum
                        return 0
                    case .change:
                        return finite(value.change)
                    case .state:
                        return finite(value.state)
                    case .min:
                        return finite(value.min)
                    case .max:
                        return finite(value.max)
                    case .mean:
                        return finite(value.mean)
                    case .lastReset:
                        return nil
                    }
                }
                accumulator.push(start: value.start, end: value.end, values: pointValues)
            }

            if shouldAppendCurrentState(
                statisticID: statisticID,
                chartType: chartType,
                metadata: metadata[statisticID],
                unit: unit,
                accumulatorEndTime: accumulator.lastEndTime,
                now: now
            ), let now = now,
               let currentValue = currentStates[statisticID].flatMap({ finite(Double($0.state)) }) {
                for (index, type) in availableTypes.enumerated() where type != .sum && type != .change {
                    accumulator.append(timestamp: now, value: currentValue, draftIndex: index)
                }
            }

            let built = accumulator.series()
            guard !built.isEmpty else {
                continue
            }

            allSeries.append(contentsOf: built)
            entityIDs.append(contentsOf: built.map(\.entityID))
            seriesToEntityIndex.append(contentsOf: Array(repeating: entityIndex, count: built.count))
            legendItems.append(LegendItem(
                id: statisticID,
                entityID: statisticID,
                label: displayName,
                colorHex: color,
                seriesIDs: built.map(\.id)
            ))
        }

        let bounds = yBounds(in: allSeries)
        return LineSeriesBuildResult(
            series: allSeries,
            legendItems: legendItems,
            yAxis: YAxisMetadata(
                unit: unit,
                deviceClass: commonDeviceClass(for: orderedIDs, metadata: metadata),
                minimum: bounds.minimum,
                maximum: bounds.maximum,
                fractionDigits: AxisLabelFormatter.fractionDigits(
                    minimum: bounds.minimum,
                    maximum: bounds.maximum
                )
            ),
            entityIDs: entityIDs,
            seriesToEntityIndex: seriesToEntityIndex
        )
    }

    private static func orderedStatisticIDs(
        _ statisticIDs: [String],
        statistics: Statistics
    ) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        for id in statisticIDs where seen.insert(id).inserted {
            ordered.append(id)
        }
        for id in statistics.keys.sorted() where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }

    private static func normalizedStatTypes(_ statTypes: [StatisticType]) -> [StatisticType] {
        var result: [StatisticType] = []
        var seen: Set<StatisticType> = []
        for type in statTypes where type != .lastReset && seen.insert(type).inserted {
            result.append(type)
        }
        return result.isEmpty ? defaultStatTypes : result
    }

    private static func statisticsHaveType(_ values: [StatisticValue], type: StatisticType) -> Bool {
        values.contains { value in
            switch type {
            case .change:
                return finite(value.change) != nil
            case .state:
                return finite(value.state) != nil
            case .sum:
                return finite(value.sum) != nil
            case .min:
                return finite(value.min) != nil
            case .max:
                return finite(value.max) != nil
            case .mean:
                return finite(value.mean) != nil
            case .lastReset:
                return false
            }
        }
    }

    private static func inferredUnit(
        for statisticIDs: [String],
        metadata: [String: StatisticsMetaData]
    ) -> String? {
        var inferred: String?
        for id in statisticIDs {
            let unit = metadata[id]?.statisticsUnitOfMeasurement
            if inferred == nil {
                inferred = unit
            } else if inferred != unit {
                return nil
            }
        }
        return inferred
    }

    private static func commonDeviceClass(
        for statisticIDs: [String],
        metadata: [String: StatisticsMetaData]
    ) -> String? {
        var inferred: String?
        for id in statisticIDs {
            let unitClass = metadata[id]?.unitClass
            if inferred == nil {
                inferred = unitClass
            } else if inferred != unitClass {
                return nil
            }
        }
        return inferred
    }

    private static func seriesName(
        displayName: String,
        type: StatisticType,
        multipleTypes: Bool
    ) -> String {
        multipleTypes ? "\(displayName) \(statisticLabel(type))" : displayName
    }

    private static func statisticLabel(_ type: StatisticType) -> String {
        switch type {
        case .change:
            return "change"
        case .state:
            return "state"
        case .sum:
            return "sum"
        case .min:
            return "min"
        case .max:
            return "max"
        case .mean:
            return "mean"
        case .lastReset:
            return "last reset"
        }
    }

    private static func shouldAppendCurrentState(
        statisticID: String,
        chartType: StatisticsGraphChartType,
        metadata: StatisticsMetaData?,
        unit: String?,
        accumulatorEndTime: Double?,
        now: Double?
    ) -> Bool {
        guard !chartType.isStacked,
              !isExternalStatistic(statisticID),
              let accumulatorEndTime = accumulatorEndTime,
              let now = now,
              now - accumulatorEndTime <= 600_000 else {
            return false
        }

        let statisticUnit = metadata?.statisticsUnitOfMeasurement
        return unit == nil || statisticUnit == nil || unit == statisticUnit
    }

    private static func isExternalStatistic(_ statisticID: String) -> Bool {
        statisticID.contains(":")
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

    private static func finite(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite else {
            return nil
        }
        return value
    }
}

private struct StatisticsLineSeriesDraft {
    var id: String
    var entityID: EntityID
    var name: String
    var unit: String?
    var deviceClass: String?
    var colorHex: String?
    var isFilled: Bool
    var sourceRanges: [LineSeriesSourceRange]
    var points: [LinePoint] = []

    func series() -> LineSeries? {
        guard points.contains(where: { $0.y != nil }) else {
            return nil
        }
        return LineSeries(
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

private struct StatisticsLineSeriesAccumulator {
    private var drafts: [StatisticsLineSeriesDraft]
    private var previousValues: [Double?]?
    private var previousEndTime: Double?

    init(drafts: [StatisticsLineSeriesDraft]) {
        self.drafts = drafts
    }

    var lastEndTime: Double? {
        previousEndTime
    }

    mutating func push(start: Double, end: Double, values: [Double?]) {
        guard !drafts.isEmpty else {
            return
        }

        let values = normalized(values)
        if let previousEndTime = previousEndTime,
           let previousValues = previousValues,
           previousEndTime != start {
            for index in drafts.indices {
                drafts[index].points.append(LinePoint(x: previousEndTime, y: previousValues[index], source: .statistics))
                drafts[index].points.append(LinePoint(x: previousEndTime, y: nil, source: .statistics))
            }
        }

        for index in drafts.indices {
            drafts[index].points.append(LinePoint(x: start, y: values[index], source: .statistics))
        }
        previousValues = values
        previousEndTime = end
    }

    mutating func append(timestamp: Double, value: Double, draftIndex: Int) {
        guard drafts.indices.contains(draftIndex) else {
            return
        }
        drafts[draftIndex].points.append(LinePoint(x: timestamp, y: value, source: .generated))
    }

    func series() -> [LineSeries] {
        var result: [LineSeries] = []
        for draftIndex in drafts.indices {
            var draft = drafts[draftIndex]
            if let previousValues = previousValues, let previousEndTime = previousEndTime {
                draft.points.append(LinePoint(x: previousEndTime, y: previousValues[draftIndex], source: .statistics))
            }
            if let series = draft.series() {
                result.append(series)
            }
        }
        return result
    }

    private func normalized(_ values: [Double?]) -> [Double?] {
        if values.count == drafts.count {
            return values
        }

        var normalized = Array(repeating: Optional<Double>.none, count: drafts.count)
        for index in 0..<min(values.count, drafts.count) {
            normalized[index] = values[index]
        }
        return normalized
    }
}

private struct StatisticsColorAllocator {
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

private extension StatisticsMetaData {
    var displayName: String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }
}
