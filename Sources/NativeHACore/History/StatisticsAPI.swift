import Foundation

public struct StatisticsAPI {
    private let client: HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.client = client
    }

    public func fetchStatisticsDuringPeriod(
        startTime: Date,
        endTime: Date? = nil,
        statisticIDs: [String]? = nil,
        period: StatisticPeriod = .hour,
        units: StatisticsUnitConfiguration? = nil,
        types: [StatisticType]? = nil
    ) async throws -> Statistics {
        var payload: [String: HAJSONValue] = [
            "start_time": .string(HAHistoryDateCoding.isoString(from: startTime)),
            "period": .string(period.rawValue)
        ]

        if let endTime = endTime {
            payload["end_time"] = .string(HAHistoryDateCoding.isoString(from: endTime))
        }
        if let statisticIDs = statisticIDs {
            payload["statistic_ids"] = .array(statisticIDs.map(HAJSONValue.string))
        }
        if let units = units {
            payload["units"] = units.historyPayload
        }
        if let types = types {
            payload["types"] = .array(types.map { .string($0.rawValue) })
        }

        return try await client.callWS(HAWebSocketRequest(
            type: "recorder/statistics_during_period",
            payload: payload
        ))
    }

    public func fetchStatisticMetadata(statisticIDs: [String]? = nil) async throws -> [StatisticsMetaData] {
        var payload: [String: HAJSONValue] = [:]
        if let statisticIDs = statisticIDs {
            payload["statistic_ids"] = .array(statisticIDs.map(HAJSONValue.string))
        }
        return try await client.callWS(HAWebSocketRequest(
            type: "recorder/get_statistics_metadata",
            payload: payload
        ))
    }
}
