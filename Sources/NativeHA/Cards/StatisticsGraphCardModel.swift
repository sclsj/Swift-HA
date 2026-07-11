import Foundation
import NativeHACore

struct StatisticsGraphCardModel: Equatable {
    static let defaultDaysToShow: Double = 30

    var title: String?
    var entries: [StatisticsGraphEntityEntry]
    var daysToShow: Double
    var period: StatisticPeriod
    var statTypes: [StatisticType]
    var chartType: StatisticsGraphChartType
    var logarithmicScale: Bool
    var minYAxis: Double?
    var maxYAxis: Double?
    var fitYData: Bool
    var hideLegend: Bool
    var expandLegend: Bool
    var displayNames: [EntityID: String]
    var colors: [EntityID: String]
    var configurationKey: String

    var entityIDs: [EntityID] {
        entries.map(\.entityID)
    }

    init(config: StatisticsGraphCardConfig, displayContext: EntityDisplayContext) {
        title = config.title
        daysToShow = Self.resolvedDaysToShow(config.daysToShow)
        period = config.period ?? .hour
        statTypes = Self.normalizedStatTypes(config.statTypes)
        chartType = config.chartType ?? .line
        logarithmicScale = config.logarithmicScale ?? false
        minYAxis = config.minYAxis
        maxYAxis = config.maxYAxis
        fitYData = config.fitYData ?? false
        hideLegend = config.hideLegend ?? false
        expandLegend = config.expandLegend ?? false

        var seen: Set<EntityID> = []
        var normalizedEntries: [StatisticsGraphEntityEntry] = []
        for entity in config.entities {
            guard let entityID = entity.entity?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !entityID.isEmpty,
                  EntityIDParser.isValid(entityID),
                  seen.insert(entityID).inserted else {
                continue
            }
            normalizedEntries.append(StatisticsGraphEntityEntry(
                entityID: entityID,
                configuredName: entity.name,
                configuredColor: Self.normalizedColor(entity.configuredColor)
            ))
        }
        entries = normalizedEntries

        var names: [EntityID: String] = [:]
        var colorMap: [EntityID: String] = [:]
        for entry in normalizedEntries {
            if let stateObj = displayContext.states[entry.entityID] {
                names[entry.entityID] = displayContext.displayName(
                    for: stateObj,
                    overrideName: entry.configuredName
                )
            } else {
                names[entry.entityID] = entry.configuredName ?? entry.entityID
            }

            if let color = entry.configuredColor {
                colorMap[entry.entityID] = color
            }
        }
        displayNames = names
        colors = colorMap

        configurationKey = Self.configurationKey(
            entries: normalizedEntries,
            daysToShow: daysToShow,
            period: period,
            statTypes: statTypes,
            chartType: chartType,
            logarithmicScale: logarithmicScale,
            minYAxis: minYAxis,
            maxYAxis: maxYAxis,
            fitYData: fitYData,
            hideLegend: hideLegend,
            expandLegend: expandLegend
        )
    }

    func visibleRange(endingAt endTime: Date) -> ChartVisibleRange {
        let end = endTime.timeIntervalSince1970 * 1_000
        let start = endTime.addingTimeInterval(-daysToShow * 24 * 60 * 60).timeIntervalSince1970 * 1_000
        return ChartVisibleRange(start, end)
    }

    func fetchWindow(endingAt endTime: Date) -> (start: Date, end: Date) {
        let fetchHours = daysToShow * 24 + 1
        return (endTime.addingTimeInterval(-fetchHours * 60 * 60), endTime)
    }

    private static func resolvedDaysToShow(_ configured: Double?) -> Double {
        guard let configured = configured, configured.isFinite, configured > 0 else {
            return defaultDaysToShow
        }
        return configured
    }

    private static func normalizedStatTypes(_ configured: [StatisticType]?) -> [StatisticType] {
        var result: [StatisticType] = []
        var seen: Set<StatisticType> = []
        for type in configured ?? StatisticsSeriesBuilder.defaultStatTypes
            where type != .lastReset && seen.insert(type).inserted {
            result.append(type)
        }
        return result.isEmpty ? StatisticsSeriesBuilder.defaultStatTypes : result
    }

    private static func normalizedColor(_ color: String?) -> String? {
        guard let color = color?.trimmingCharacters(in: .whitespacesAndNewlines), !color.isEmpty else {
            return nil
        }
        return color
    }

    private static func configurationKey(
        entries: [StatisticsGraphEntityEntry],
        daysToShow: Double,
        period: StatisticPeriod,
        statTypes: [StatisticType],
        chartType: StatisticsGraphChartType,
        logarithmicScale: Bool,
        minYAxis: Double?,
        maxYAxis: Double?,
        fitYData: Bool,
        hideLegend: Bool,
        expandLegend: Bool
    ) -> String {
        let entityKey = entries.map {
            "\($0.entityID):\($0.configuredName ?? ""):\($0.configuredColor ?? "")"
        }.joined(separator: ",")
        return [
            entityKey,
            String(daysToShow),
            period.rawValue,
            statTypes.map(\.rawValue).joined(separator: ","),
            chartType.rawValue,
            String(logarithmicScale),
            minYAxis.map { String($0) } ?? "",
            maxYAxis.map { String($0) } ?? "",
            String(fitYData),
            String(hideLegend),
            String(expandLegend)
        ].joined(separator: "|")
    }
}

struct StatisticsGraphEntityEntry: Equatable {
    var entityID: EntityID
    var configuredName: String?
    var configuredColor: String?
}

private extension LovelaceGraphEntityConfig {
    var configuredColor: String? {
        guard case let .config(config) = self else {
            return nil
        }
        return config.color
    }
}
