import Foundation
import NativeHACore

struct HistoryGraphCardModel: Equatable {
    static let defaultHoursToShow: Double = 24
    static let minimumRefreshInterval: Double = 5

    var title: String?
    var entries: [HistoryGraphEntityEntry]
    var hoursToShow: Double
    var refreshInterval: Double?
    var showNames: Bool
    var logarithmicScale: Bool
    var minYAxis: Double?
    var maxYAxis: Double?
    var fitYData: Bool
    var splitDeviceClasses: Bool
    var expandLegend: Bool
    var displayNames: [EntityID: String]
    var colors: [EntityID: String]
    var configurationKey: String

    var entityIDs: [EntityID] {
        entries.map(\.entityID)
    }

    var refreshIntervalSeconds: Double? {
        guard let refreshInterval = refreshInterval, refreshInterval > 0 else {
            return nil
        }
        return max(refreshInterval, Self.minimumRefreshInterval)
    }

    init(config: HistoryGraphCardConfig, displayContext: EntityDisplayContext) {
        title = config.title
        hoursToShow = Self.resolvedHoursToShow(config.hoursToShow)
        refreshInterval = config.refreshInterval
        showNames = config.showNames ?? true
        logarithmicScale = config.logarithmicScale ?? false
        minYAxis = config.minYAxis
        maxYAxis = config.maxYAxis
        fitYData = config.fitYData ?? false
        splitDeviceClasses = config.splitDeviceClasses ?? false
        expandLegend = config.expandLegend ?? false

        var seen: Set<EntityID> = []
        var normalizedEntries: [HistoryGraphEntityEntry] = []
        for entity in config.entities {
            guard let entityID = entity.entity?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !entityID.isEmpty,
                  EntityIDParser.isValid(entityID),
                  seen.insert(entityID).inserted else {
                continue
            }

            normalizedEntries.append(HistoryGraphEntityEntry(
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
            hoursToShow: hoursToShow,
            refreshInterval: refreshInterval,
            showNames: showNames,
            logarithmicScale: logarithmicScale,
            minYAxis: minYAxis,
            maxYAxis: maxYAxis,
            fitYData: fitYData,
            splitDeviceClasses: splitDeviceClasses,
            expandLegend: expandLegend
        )
    }

    func visibleRange(endingAt endTime: Date) -> ChartVisibleRange {
        let end = endTime.timeIntervalSince1970 * 1_000
        let start = endTime.addingTimeInterval(-hoursToShow * 60 * 60).timeIntervalSince1970 * 1_000
        return ChartVisibleRange(start, end)
    }

    func fetchWindow(endingAt endTime: Date) -> (start: Date, end: Date) {
        (endTime.addingTimeInterval(-hoursToShow * 60 * 60), endTime)
    }

    func statisticsWindow(endingAt endTime: Date) -> (start: Date, end: Date)? {
        guard hoursToShow >= 1 else {
            return nil
        }

        return (
            endTime.addingTimeInterval(-(hoursToShow + 1) * 60 * 60),
            endTime
        )
    }

    private static func resolvedHoursToShow(_ configured: Double?) -> Double {
        guard let configured = configured, configured.isFinite, configured > 0 else {
            return defaultHoursToShow
        }
        return configured
    }

    private static func normalizedColor(_ color: String?) -> String? {
        guard let color = color?.trimmingCharacters(in: .whitespacesAndNewlines), !color.isEmpty else {
            return nil
        }
        return color
    }

    private static func configurationKey(
        entries: [HistoryGraphEntityEntry],
        hoursToShow: Double,
        refreshInterval: Double?,
        showNames: Bool,
        logarithmicScale: Bool,
        minYAxis: Double?,
        maxYAxis: Double?,
        fitYData: Bool,
        splitDeviceClasses: Bool,
        expandLegend: Bool
    ) -> String {
        let entityKey = entries.map {
            "\($0.entityID):\($0.configuredName ?? ""):\($0.configuredColor ?? "")"
        }.joined(separator: ",")
        return [
            entityKey,
            String(hoursToShow),
            refreshInterval.map { String($0) } ?? "",
            String(showNames),
            String(logarithmicScale),
            minYAxis.map { String($0) } ?? "",
            maxYAxis.map { String($0) } ?? "",
            String(fitYData),
            String(splitDeviceClasses),
            String(expandLegend)
        ].joined(separator: "|")
    }
}

struct HistoryGraphEntityEntry: Equatable {
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
