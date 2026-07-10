import NativeHACore
import SwiftUI

@MainActor
protocol HistoryGraphDataProviding: AnyObject {
    func fetchHistory(
        startTime: Date,
        endTime: Date,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity]
    ) async throws -> HistoryStates

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String]
    ) async throws -> Statistics
}

@MainActor
final class HomeAssistantHistoryGraphDataProvider: HistoryGraphDataProviding {
    private let historyAPI: HistoryAPI
    private let statisticsAPI: StatisticsAPI

    init(client: HAWebSocketClientProtocol) {
        historyAPI = HistoryAPI(client: client)
        statisticsAPI = StatisticsAPI(client: client)
    }

    func fetchHistory(
        startTime: Date,
        endTime: Date,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity]
    ) async throws -> HistoryStates {
        try await historyAPI.fetchHistoryDuringPeriod(
            startTime: startTime,
            endTime: endTime,
            entityIDs: entityIDs,
            currentStates: currentStates,
            minimalResponse: true
        )
    }

    func fetchStatistics(
        startTime: Date,
        endTime: Date,
        statisticIDs: [String]
    ) async throws -> Statistics {
        try await statisticsAPI.fetchStatisticsDuringPeriod(
            startTime: startTime,
            endTime: endTime,
            statisticIDs: statisticIDs,
            period: .hour,
            types: [.mean, .state]
        )
    }
}

private struct HistoryGraphDataProviderKey: EnvironmentKey {
    static let defaultValue: HistoryGraphDataProviding? = nil
}

extension EnvironmentValues {
    var historyGraphDataProvider: HistoryGraphDataProviding? {
        get { self[HistoryGraphDataProviderKey.self] }
        set { self[HistoryGraphDataProviderKey.self] = newValue }
    }
}
