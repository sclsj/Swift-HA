import Foundation

public typealias HistoryLocalizer = (String) -> String

public struct HistoryProcessingContext {
    public var states: [EntityID: HassEntity]
    public var config: HAConfig?
    public var registryEntries: [EntityID: HAEntityRegistryDisplayEntry]
    public var locale: Locale
    public var localize: HistoryLocalizer

    public init(
        states: [EntityID: HassEntity] = [:],
        config: HAConfig? = nil,
        registryEntries: [EntityID: HAEntityRegistryDisplayEntry] = [:],
        locale: Locale = HANumberFormatting.defaultLocale,
        localize: @escaping HistoryLocalizer = { $0 }
    ) {
        self.states = states
        self.config = config
        self.registryEntries = registryEntries
        self.locale = locale
        self.localize = localize
    }
}

public enum HistoryProcessor {
    public static let blankUnit = " "

    private static let domainsUseLastUpdated: Set<String> = [
        "climate",
        "humidifier",
        "water_heater"
    ]

    private static let lineAttributesToKeep = [
        "temperature",
        "current_temperature",
        "target_temp_low",
        "target_temp_high",
        "hvac_action",
        "humidity",
        "mode",
        "action",
        "current_humidity"
    ]

    private static let specialDomainClasses: [String: String] = [
        "climate": "temperature",
        "humidifier": "humidity",
        "water_heater": "temperature"
    ]

    public static func computeHistory(
        stateHistory: HistoryStates,
        entityIDs: [EntityID] = [],
        context: HistoryProcessingContext = HistoryProcessingContext(),
        splitDeviceClasses: Bool = false,
        forceNumeric: Bool = false
    ) -> HistoryResult {
        var localStateHistory: HistoryStates = [:]
        var orderedEntityIDs: [EntityID] = []
        var seenEntityIDs: Set<EntityID> = []

        for entityID in entityIDs where seenEntityIDs.insert(entityID).inserted {
            orderedEntityIDs.append(entityID)
        }
        for entityID in stateHistory.keys where seenEntityIDs.insert(entityID).inserted {
            orderedEntityIDs.append(entityID)
        }

        for entityID in orderedEntityIDs {
            if let states = stateHistory[entityID] {
                localStateHistory[entityID] = states
            } else if let currentState = context.states[entityID] {
                localStateHistory[entityID] = limitedHistory(from: currentState)
            }
        }

        var lineGroups: [GroupedLineHistory] = []
        var lineGroupIndexes: [String: Int] = [:]
        var timelineDevices: [TimelineEntity] = []

        for entityID in orderedEntityIDs {
            guard let stateInfo = localStateHistory[entityID], !stateInfo.isEmpty else {
                continue
            }

            let domain = EntityIDParser.domain(from: entityID)
            let currentState = context.states[entityID]
            let numericStateFromHistory: EntityHistoryState?
            if currentState != nil || isNumericFromDomain(domain) {
                numericStateFromHistory = nil
            } else {
                numericStateFromHistory = stateInfo.first {
                    isNumericFromAttributes($0.attributes)
                }
            }

            let isNumeric = isNumericEntity(
                domain: domain,
                currentState: currentState,
                numericStateFromHistory: numericStateFromHistory,
                forceNumeric: forceNumeric
            )

            let unit: String?
            if isNumeric {
                unit = currentState?.attributes["unit_of_measurement"]?.stringValue
                    ?? numericStateFromHistory?.attributes["unit_of_measurement"]?.stringValue
                    ?? blankUnit
            } else {
                unit = nonNumericUnit(domain: domain, context: context)
            }

            let deviceClass = specialDomainClasses[domain]
                ?? (currentState?.attributes["device_class"] ?? numericStateFromHistory?.attributes["device_class"])?.stringValue
            let key = computeGroupKey(unit: unit, deviceClass: deviceClass, splitDeviceClasses: splitDeviceClasses)

            guard let unit = unit, let key = key else {
                timelineDevices.append(processTimelineEntity(
                    context: context,
                    entityID: entityID,
                    states: stateInfo,
                    currentState: currentState
                ))
                continue
            }

            if let index = lineGroupIndexes[key] {
                var group = lineGroups[index]
                if group.entityStates[entityID] != nil {
                    group.entityStates[entityID, default: []].append(contentsOf: stateInfo)
                } else {
                    group.entityOrder.append(entityID)
                    group.entityStates[entityID] = stateInfo
                }
                lineGroups[index] = group
            } else {
                lineGroupIndexes[key] = lineGroups.count
                lineGroups.append(GroupedLineHistory(
                    key: key,
                    unit: unit,
                    deviceClass: deviceClass,
                    entityOrder: [entityID],
                    entityStates: [entityID: stateInfo]
                ))
            }
        }

        let lineUnits = lineGroups.map {
            processLineChartEntities(group: $0, currentStates: context.states)
        }

        return HistoryResult(line: lineUnits, timeline: timelineDevices)
    }

    public static func limitedHistory(from state: HassEntity) -> [EntityHistoryState] {
        [
            EntityHistoryState(
                state: state.state,
                attributes: state.attributes,
                lastUpdated: state.lastUpdated.timeIntervalSince1970
            )
        ]
    }

    public static func convertStatisticsToHistory(
        statistics: Statistics,
        statisticIDs: [String],
        context: HistoryProcessingContext = HistoryProcessingContext(),
        splitDeviceClasses: Bool = false
    ) -> HistoryResult {
        var statsHistoryStates: HistoryStates = [:]

        for statisticID in statisticIDs {
            guard let values = statistics[statisticID] else {
                continue
            }
            let states = values.compactMap { value -> EntityHistoryState? in
                guard let statisticState = value.mean ?? value.state else {
                    return nil
                }
                let endSeconds = value.end / 1000
                return EntityHistoryState(
                    state: HistoryModelCoding.statisticString(from: statisticState),
                    attributes: [:],
                    lastChanged: endSeconds,
                    lastUpdated: endSeconds
                )
            }
            statsHistoryStates[statisticID] = states
        }

        var result = computeHistory(
            stateHistory: statsHistoryStates,
            entityIDs: [],
            context: context,
            splitDeviceClasses: splitDeviceClasses,
            forceNumeric: true
        )

        for lineIndex in result.line.indices {
            for dataIndex in result.line[lineIndex].data.indices {
                result.line[lineIndex].data[dataIndex].statistics = result.line[lineIndex].data[dataIndex].states
                result.line[lineIndex].data[dataIndex].states = []
            }
        }

        return result
    }

    public static func mergeHistoryResults(
        historyResult: HistoryResult,
        longTermStatisticsResult: HistoryResult?,
        splitDeviceClasses: Bool = true
    ) -> HistoryResult {
        guard let longTermStatisticsResult = longTermStatisticsResult else {
            return historyResult
        }

        var result = historyResult
        result.line = []

        var lookup: [String: (historyItem: LineChartUnit?, statisticsItem: LineChartUnit?)] = [:]
        var orderedKeys: [String] = []

        func ensureKey(_ key: String) {
            if lookup[key] == nil {
                lookup[key] = (nil, nil)
                orderedKeys.append(key)
            }
        }

        for item in historyResult.line {
            guard let key = computeGroupKey(
                unit: item.unit,
                deviceClass: item.deviceClass,
                splitDeviceClasses: splitDeviceClasses
            ) else {
                continue
            }
            ensureKey(key)
            lookup[key]?.historyItem = item
        }

        for originalItem in longTermStatisticsResult.line {
            var item = originalItem
            if item.unit == blankUnit {
                item.unit = historyResult.line.first {
                    $0.identifier == item.identifier
                }?.unit ?? blankUnit
            }

            guard let key = computeGroupKey(
                unit: item.unit,
                deviceClass: item.deviceClass,
                splitDeviceClasses: splitDeviceClasses
            ) else {
                continue
            }
            ensureKey(key)
            lookup[key]?.statisticsItem = item
        }

        for key in orderedKeys {
            guard let pair = lookup[key] else {
                continue
            }

            guard let historyItem = pair.historyItem, let statisticsItem = pair.statisticsItem else {
                if let historyItem = pair.historyItem {
                    result.line.append(historyItem)
                } else if let statisticsItem = pair.statisticsItem {
                    result.line.append(statisticsItem)
                }
                continue
            }

            var newLineItem = historyItem
            newLineItem.data = []

            let historyDataByEntity = Dictionary(uniqueKeysWithValues: historyItem.data.map { ($0.entityID, $0) })
            let statisticsDataByEntity = Dictionary(uniqueKeysWithValues: statisticsItem.data.map { ($0.entityID, $0) })
            var entityOrder: [EntityID] = []
            var seenEntities: Set<EntityID> = []
            for entityID in historyItem.data.map(\.entityID) where seenEntities.insert(entityID).inserted {
                entityOrder.append(entityID)
            }
            for entityID in statisticsItem.data.map(\.entityID) where seenEntities.insert(entityID).inserted {
                entityOrder.append(entityID)
            }

            for entityID in entityOrder {
                let historyDataItem = historyDataByEntity[entityID]
                let statisticsDataItem = statisticsDataByEntity[entityID]

                guard let historyDataItem = historyDataItem, let statisticsDataItem = statisticsDataItem else {
                    if let historyDataItem = historyDataItem {
                        newLineItem.data.append(historyDataItem)
                    } else if let statisticsDataItem = statisticsDataItem {
                        newLineItem.data.append(statisticsDataItem)
                    }
                    continue
                }

                let oldestState = historyDataItem.states.first?.lastChanged
                    ?? ((statisticsDataItem.statistics?.last?.lastChanged ?? 0) + 1)
                var statistics: [LineChartState] = []
                for state in statisticsDataItem.statistics ?? [] {
                    if state.lastChanged >= oldestState {
                        break
                    }
                    statistics.append(state)
                }

                if statistics.isEmpty {
                    newLineItem.data.append(historyDataItem)
                } else {
                    var mergedDataItem = historyDataItem
                    mergedDataItem.statistics = statistics
                    newLineItem.data.append(mergedDataItem)
                }
            }

            result.line.append(newLineItem)
        }

        return result
    }

    public static func computeGroupKey(
        unit: String?,
        deviceClass: String?,
        splitDeviceClasses: Bool
    ) -> String? {
        guard let unit = unit else {
            return nil
        }
        return splitDeviceClasses ? "\(unit)_\(deviceClass ?? "")" : unit
    }

    public static func isNumericEntity(
        domain: String,
        currentState: HassEntity?,
        numericStateFromHistory: EntityHistoryState?,
        forceNumeric: Bool = false
    ) -> Bool {
        forceNumeric
            || isNumericFromDomain(domain)
            || currentState.map { isNumericFromAttributes($0.attributes) } == true
            || (
                currentState != nil
                    && domain == "sensor"
                    && currentState?.attributes["device_class"]?.stringValue.map(HADomainLogic.numericSensorDeviceClasses.contains) == true
            )
            || numericStateFromHistory != nil
    }

    private static func processTimelineEntity(
        context: HistoryProcessingContext,
        entityID: EntityID,
        states: [EntityHistoryState],
        currentState: HassEntity?
    ) -> TimelineEntity {
        var data: [TimelineState] = []
        data.reserveCapacity(states.count)

        for state in states {
            if data.last?.state == state.state {
                continue
            }

            var attributes = state.attributes
            if let deviceClass = currentState?.attributes["device_class"] {
                attributes["device_class"] = deviceClass
            }

            data.append(TimelineState(
                stateLocalized: HAEntityFormatting.stateDisplay(
                    entityID: entityID,
                    state: state.state,
                    attributes: attributes,
                    registryEntry: context.registryEntries[entityID],
                    config: context.config,
                    locale: context.locale
                ),
                state: state.state,
                lastChanged: lastChangedMilliseconds(for: state)
            ))
        }

        return TimelineEntity(
            name: entityName(entityID: entityID, currentState: currentState, fallbackAttributes: states.first?.attributes ?? [:]),
            entityID: entityID,
            data: data
        )
    }

    private static func processLineChartEntities(
        group: GroupedLineHistory,
        currentStates: [EntityID: HassEntity]
    ) -> LineChartUnit {
        var data: [LineChartEntity] = []
        data.reserveCapacity(group.entityOrder.count)

        for entityID in group.entityOrder {
            guard let states = group.entityStates[entityID], let first = states.first else {
                continue
            }

            let domain = EntityIDParser.domain(from: entityID)
            let useLastUpdated = domainsUseLastUpdated.contains(domain)
            var processedStates: [LineChartState] = []
            processedStates.reserveCapacity(states.count)

            for state in states {
                let processedState: LineChartState
                if useLastUpdated {
                    var keptAttributes: [String: HAJSONValue] = [:]
                    for attribute in lineAttributesToKeep {
                        if let value = state.attributes[attribute] {
                            keptAttributes[attribute] = value
                        }
                    }
                    processedState = LineChartState(
                        state: state.state,
                        lastChanged: state.lastUpdated * 1000,
                        attributes: keptAttributes
                    )
                } else {
                    processedState = LineChartState(
                        state: state.state,
                        lastChanged: lastChangedMilliseconds(for: state),
                        attributes: [:]
                    )
                }

                let count = processedStates.count
                if count > 1,
                   equalLineState(processedState, processedStates[count - 1]),
                   equalLineState(processedState, processedStates[count - 2]) {
                    continue
                }

                processedStates.append(processedState)
            }

            let nameAttributes: [String: HAJSONValue]
            if currentStates[entityID] != nil {
                nameAttributes = currentStates[entityID]?.attributes ?? [:]
            } else if first.attributes["friendly_name"] != nil {
                nameAttributes = first.attributes
            } else {
                nameAttributes = [:]
            }

            data.append(LineChartEntity(
                domain: domain,
                name: entityName(entityID: entityID, currentState: currentStates[entityID], fallbackAttributes: nameAttributes),
                entityID: entityID,
                states: processedStates
            ))
        }

        return LineChartUnit(
            unit: group.unit,
            deviceClass: group.deviceClass,
            identifier: group.entityOrder.joined(),
            data: data
        )
    }

    private static func nonNumericUnit(domain: String, context: HistoryProcessingContext) -> String? {
        switch domain {
        case "zone":
            return context.localize("ui.dialogs.more_info_control.zone.graph_unit")
        case "climate", "water_heater":
            return context.config?.unitSystem["temperature"] ?? "\u{00B0}C"
        case "humidifier":
            return "%"
        default:
            return nil
        }
    }

    private static func isNumericFromDomain(_ domain: String) -> Bool {
        HADomainLogic.numericDomains.contains(domain)
    }

    private static func isNumericFromAttributes(_ attributes: [String: HAJSONValue]) -> Bool {
        attributes.keys.contains("unit_of_measurement") || attributes.keys.contains("state_class")
    }

    private static func entityName(
        entityID: EntityID,
        currentState: HassEntity?,
        fallbackAttributes: [String: HAJSONValue]
    ) -> String {
        if let currentState = currentState {
            return HAEntityFormatting.displayName(for: currentState)
        }
        if let friendlyName = fallbackAttributes["friendly_name"] {
            return friendlyName.haScalarStringValue ?? ""
        }
        return EntityIDParser.displayObjectID(from: entityID)
    }

    private static func lastChangedMilliseconds(for state: EntityHistoryState) -> Double {
        let seconds: Double
        if let lastChanged = state.lastChanged, lastChanged != 0 {
            seconds = lastChanged
        } else {
            seconds = state.lastUpdated
        }
        return seconds * 1000
    }

    private static func equalLineState(_ lhs: LineChartState, _ rhs: LineChartState) -> Bool {
        guard lhs.state == rhs.state else {
            return false
        }

        guard let lhsAttributes = lhs.attributes, let rhsAttributes = rhs.attributes else {
            return true
        }

        return lineAttributesToKeep.allSatisfy {
            historyAttributeEqual(lhsAttributes[$0], rhsAttributes[$0])
        }
    }

    private static func historyAttributeEqual(_ lhs: HAJSONValue?, _ rhs: HAJSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.integer(lhs), .integer(rhs)):
            return lhs == rhs
        case let (.double(lhs), .double(rhs)):
            return lhs == rhs
        case let (.integer(lhs), .double(rhs)):
            return Double(lhs) == rhs
        case let (.double(lhs), .integer(rhs)):
            return lhs == Double(rhs)
        default:
            return lhs == rhs
        }
    }
}

private struct GroupedLineHistory {
    var key: String
    var unit: String
    var deviceClass: String?
    var entityOrder: [EntityID]
    var entityStates: HistoryStates
}

public func computeHistory(
    stateHistory: HistoryStates,
    entityIDs: [EntityID] = [],
    context: HistoryProcessingContext = HistoryProcessingContext(),
    splitDeviceClasses: Bool = false,
    forceNumeric: Bool = false
) -> HistoryResult {
    HistoryProcessor.computeHistory(
        stateHistory: stateHistory,
        entityIDs: entityIDs,
        context: context,
        splitDeviceClasses: splitDeviceClasses,
        forceNumeric: forceNumeric
    )
}

public func convertStatisticsToHistory(
    statistics: Statistics,
    statisticIDs: [String],
    context: HistoryProcessingContext = HistoryProcessingContext(),
    splitDeviceClasses: Bool = false
) -> HistoryResult {
    HistoryProcessor.convertStatisticsToHistory(
        statistics: statistics,
        statisticIDs: statisticIDs,
        context: context,
        splitDeviceClasses: splitDeviceClasses
    )
}

public func mergeHistoryResults(
    historyResult: HistoryResult,
    longTermStatisticsResult: HistoryResult?,
    splitDeviceClasses: Bool = true
) -> HistoryResult {
    HistoryProcessor.mergeHistoryResults(
        historyResult: historyResult,
        longTermStatisticsResult: longTermStatisticsResult,
        splitDeviceClasses: splitDeviceClasses
    )
}
