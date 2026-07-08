import Foundation

public struct HistoryAPI {
    public static let domainsNeedingAttributes: Set<String> = [
        "climate",
        "humidifier",
        "input_datetime",
        "water_heater",
        "person",
        "device_tracker"
    ]

    private let client: HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.client = client
    }

    public func fetchHistoryDuringPeriod(
        startTime: Date,
        endTime: Date? = nil,
        entityIDs: [EntityID] = [],
        currentStates: [EntityID: HassEntity] = [:],
        minimalResponse: Bool = true,
        noAttributes: Bool? = nil
    ) async throws -> HistoryStates {
        var payload = baseHistoryPayload(
            startTime: startTime,
            endTime: endTime,
            entityIDs: entityIDs,
            currentStates: currentStates,
            minimalResponse: minimalResponse,
            noAttributes: noAttributes
        )
        if entityIDs.isEmpty {
            payload.removeValue(forKey: "entity_ids")
        }

        return try await client.callWS(HAWebSocketRequest(
            type: "history/history_during_period",
            payload: payload
        ))
    }

    public func subscribeHistoryStream(
        startTime: Date,
        endTime: Date? = nil,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity] = [:],
        minimalResponse: Bool = true,
        significantChangesOnly: Bool? = nil,
        noAttributes: Bool? = nil,
        onMessage: @escaping (HistoryStreamMessage) -> Void
    ) async throws -> HASubscription {
        var payload = baseHistoryPayload(
            startTime: startTime,
            endTime: endTime,
            entityIDs: entityIDs,
            currentStates: currentStates,
            minimalResponse: minimalResponse,
            noAttributes: noAttributes
        )
        if let significantChangesOnly = significantChangesOnly {
            payload["significant_changes_only"] = .bool(significantChangesOnly)
        }

        return try await client.subscribe(
            HAWebSocketRequest(type: "history/stream", payload: payload),
            onEvent: onMessage
        )
    }

    public func subscribeHistoryStatesTimeWindow(
        hoursToShow: Double,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity] = [:],
        minimalResponse: Bool = true,
        significantChangesOnly: Bool = true,
        noAttributes: Bool? = nil,
        now: @escaping () -> Date = Date.init,
        onHistory: @escaping (HistoryStates) -> Void
    ) async throws -> HASubscription {
        let stream = HistoryStream(hoursToShow: hoursToShow, now: now)
        return try await subscribeHistoryStream(
            startTime: now().addingTimeInterval(-60 * 60 * hoursToShow),
            entityIDs: entityIDs,
            currentStates: currentStates,
            minimalResponse: minimalResponse,
            significantChangesOnly: significantChangesOnly,
            noAttributes: noAttributes
        ) { message in
            onHistory(stream.processMessage(message))
        }
    }

    public static func entityIDHistoryNeedsAttributes(
        currentStates: [EntityID: HassEntity],
        entityID: EntityID
    ) -> Bool {
        currentStates[entityID] == nil || domainsNeedingAttributes.contains(EntityIDParser.domain(from: entityID))
    }

    private func baseHistoryPayload(
        startTime: Date,
        endTime: Date?,
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity],
        minimalResponse: Bool,
        noAttributes: Bool?
    ) -> [String: HAJSONValue] {
        var payload: [String: HAJSONValue] = [
            "start_time": .string(HAHistoryDateCoding.isoString(from: startTime)),
            "entity_ids": .array(entityIDs.map(HAJSONValue.string)),
            "minimal_response": .bool(minimalResponse),
            "no_attributes": .bool(resolvedNoAttributes(
                entityIDs: entityIDs,
                currentStates: currentStates,
                explicitNoAttributes: noAttributes
            ))
        ]

        if let endTime = endTime {
            payload["end_time"] = .string(HAHistoryDateCoding.isoString(from: endTime))
        }

        return payload
    }

    private func resolvedNoAttributes(
        entityIDs: [EntityID],
        currentStates: [EntityID: HassEntity],
        explicitNoAttributes: Bool?
    ) -> Bool {
        if let explicitNoAttributes = explicitNoAttributes {
            return explicitNoAttributes
        }
        return !entityIDs.contains {
            Self.entityIDHistoryNeedsAttributes(currentStates: currentStates, entityID: $0)
        }
    }
}

enum HAHistoryDateCoding {
    static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
