import NativeHACore
import SwiftUI

@MainActor
protocol StatisticsGraphDataProviding: AnyObject {
    func fetchStatisticMetadata(statisticIDs: [String]) async throws -> [StatisticsMetaData]

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String],
        period: StatisticPeriod,
        types: [StatisticType]
    ) async throws -> Statistics
}

@MainActor
final class HomeAssistantStatisticsGraphDataProvider: StatisticsGraphDataProviding {
    private let statisticsAPI: StatisticsAPI

    init(client: HAWebSocketClientProtocol) {
        statisticsAPI = StatisticsAPI(client: client)
    }

    func fetchStatisticMetadata(statisticIDs: [String]) async throws -> [StatisticsMetaData] {
        try await statisticsAPI.fetchStatisticMetadata(statisticIDs: statisticIDs)
    }

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String],
        period: StatisticPeriod,
        types: [StatisticType]
    ) async throws -> Statistics {
        try await statisticsAPI.fetchStatisticsDuringPeriod(
            startTime: startTime,
            endTime: endTime,
            statisticIDs: statisticIDs,
            period: period,
            types: types
        )
    }
}

private struct StatisticsGraphDataProviderKey: EnvironmentKey {
    static let defaultValue: StatisticsGraphDataProviding? = nil
}

extension EnvironmentValues {
    var statisticsGraphDataProvider: StatisticsGraphDataProviding? {
        get { self[StatisticsGraphDataProviderKey.self] }
        set { self[StatisticsGraphDataProviderKey.self] = newValue }
    }
}
