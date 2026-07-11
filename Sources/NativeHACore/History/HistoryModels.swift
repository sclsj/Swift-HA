import Foundation

public typealias HistoryStates = [EntityID: [EntityHistoryState]]
public typealias Statistics = [String: [StatisticValue]]

public struct EntityHistoryState: Codable, Equatable {
    public var state: String
    public var attributes: [String: HAJSONValue]
    public var lastChanged: Double?
    public var lastUpdated: Double

    public init(
        state: String,
        attributes: [String: HAJSONValue] = [:],
        lastChanged: Double? = nil,
        lastUpdated: Double
    ) {
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }

    enum CodingKeys: String, CodingKey {
        case state = "s"
        case attributes = "a"
        case lastChanged = "lc"
        case lastUpdated = "lu"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decodeIfPresent([String: HAJSONValue].self, forKey: .attributes) ?? [:]
        lastChanged = try container.decodeHistoryDoubleIfPresent(forKey: .lastChanged)
        lastUpdated = try container.decodeHistoryDouble(forKey: .lastUpdated)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(attributes, forKey: .attributes)
        try container.encodeIfPresent(lastChanged, forKey: .lastChanged)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

public struct HistoryStreamMessage: Codable, Equatable {
    public var states: HistoryStates
    public var startTime: Double?
    public var endTime: Double?

    public init(states: HistoryStates, startTime: Double? = nil, endTime: Double? = nil) {
        self.states = states
        self.startTime = startTime
        self.endTime = endTime
    }

    enum CodingKeys: String, CodingKey {
        case states
        case startTime = "start_time"
        case endTime = "end_time"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        states = try container.decodeIfPresent(HistoryStates.self, forKey: .states) ?? [:]
        startTime = try container.decodeHistoryDoubleIfPresent(forKey: .startTime)
        endTime = try container.decodeHistoryDoubleIfPresent(forKey: .endTime)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(states, forKey: .states)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
    }
}

public struct LineChartState: Codable, Equatable {
    public var state: String
    public var lastChanged: Double
    public var attributes: [String: HAJSONValue]?

    public init(state: String, lastChanged: Double, attributes: [String: HAJSONValue]? = nil) {
        self.state = state
        self.lastChanged = lastChanged
        self.attributes = attributes
    }

    enum CodingKeys: String, CodingKey {
        case state
        case lastChanged = "last_changed"
        case attributes
    }
}

public struct LineChartEntity: Codable, Equatable {
    public var domain: String
    public var name: String
    public var entityID: EntityID
    public var states: [LineChartState]
    public var statistics: [LineChartState]?

    public init(
        domain: String,
        name: String,
        entityID: EntityID,
        states: [LineChartState],
        statistics: [LineChartState]? = nil
    ) {
        self.domain = domain
        self.name = name
        self.entityID = entityID
        self.states = states
        self.statistics = statistics
    }

    enum CodingKeys: String, CodingKey {
        case domain
        case name
        case entityID = "entity_id"
        case states
        case statistics
    }
}

public struct LineChartUnit: Codable, Equatable {
    public var unit: String
    public var deviceClass: String?
    public var identifier: String
    public var data: [LineChartEntity]

    public init(unit: String, deviceClass: String? = nil, identifier: String, data: [LineChartEntity]) {
        self.unit = unit
        self.deviceClass = deviceClass
        self.identifier = identifier
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case unit
        case deviceClass = "device_class"
        case identifier
        case data
    }
}

public struct TimelineState: Codable, Equatable {
    public var stateLocalized: String
    public var state: String
    public var lastChanged: Double

    public init(stateLocalized: String, state: String, lastChanged: Double) {
        self.stateLocalized = stateLocalized
        self.state = state
        self.lastChanged = lastChanged
    }

    enum CodingKeys: String, CodingKey {
        case stateLocalized = "state_localize"
        case state
        case lastChanged = "last_changed"
    }
}

public struct TimelineEntity: Codable, Equatable {
    public var name: String
    public var entityID: EntityID
    public var data: [TimelineState]

    public init(name: String, entityID: EntityID, data: [TimelineState]) {
        self.name = name
        self.entityID = entityID
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case name
        case entityID = "entity_id"
        case data
    }
}

public struct HistoryResult: Codable, Equatable {
    public var line: [LineChartUnit]
    public var timeline: [TimelineEntity]

    public init(line: [LineChartUnit] = [], timeline: [TimelineEntity] = []) {
        self.line = line
        self.timeline = timeline
    }
}

public enum StatisticType: String, Codable, Equatable {
    case change
    case lastReset = "last_reset"
    case max
    case mean
    case min
    case state
    case sum
}

public enum StatisticPeriod: String, Codable, Equatable {
    case fiveMinute = "5minute"
    case hour
    case day
    case week
    case month
}

public enum StatisticsGraphChartType: String, Codable, Equatable {
    case line
    case lineStack = "line-stack"
    case bar
    case barStack = "bar-stack"

    public var isStacked: Bool {
        self == .lineStack || self == .barStack
    }

    public var isBar: Bool {
        self == .bar || self == .barStack
    }
}

public struct StatisticValue: Codable, Equatable {
    public var start: Double
    public var end: Double
    public var change: Double?
    public var lastReset: Double?
    public var max: Double?
    public var mean: Double?
    public var min: Double?
    public var sum: Double?
    public var state: Double?

    public init(
        start: Double,
        end: Double,
        change: Double? = nil,
        lastReset: Double? = nil,
        max: Double? = nil,
        mean: Double? = nil,
        min: Double? = nil,
        sum: Double? = nil,
        state: Double? = nil
    ) {
        self.start = start
        self.end = end
        self.change = change
        self.lastReset = lastReset
        self.max = max
        self.mean = mean
        self.min = min
        self.sum = sum
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case change
        case lastReset = "last_reset"
        case max
        case mean
        case min
        case sum
        case state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeHistoryDouble(forKey: .start)
        end = try container.decodeHistoryDouble(forKey: .end)
        change = try container.decodeHistoryDoubleIfPresent(forKey: .change)
        lastReset = try container.decodeHistoryDoubleIfPresent(forKey: .lastReset)
        max = try container.decodeHistoryDoubleIfPresent(forKey: .max)
        mean = try container.decodeHistoryDoubleIfPresent(forKey: .mean)
        min = try container.decodeHistoryDoubleIfPresent(forKey: .min)
        sum = try container.decodeHistoryDoubleIfPresent(forKey: .sum)
        state = try container.decodeHistoryDoubleIfPresent(forKey: .state)
    }
}

public enum StatisticMeanType: Int, Codable, Equatable {
    case none = 0
    case arithmetic = 1
    case circular = 2
}

public struct StatisticsMetaData: Codable, Equatable {
    public var statisticsUnitOfMeasurement: String?
    public var statisticID: String
    public var source: String
    public var name: String?
    public var hasSum: Bool
    public var meanType: StatisticMeanType
    public var unitClass: String?

    public init(
        statisticsUnitOfMeasurement: String?,
        statisticID: String,
        source: String,
        name: String? = nil,
        hasSum: Bool,
        meanType: StatisticMeanType,
        unitClass: String?
    ) {
        self.statisticsUnitOfMeasurement = statisticsUnitOfMeasurement
        self.statisticID = statisticID
        self.source = source
        self.name = name
        self.hasSum = hasSum
        self.meanType = meanType
        self.unitClass = unitClass
    }

    enum CodingKeys: String, CodingKey {
        case statisticsUnitOfMeasurement = "statistics_unit_of_measurement"
        case statisticID = "statistic_id"
        case source
        case name
        case hasSum = "has_sum"
        case meanType = "mean_type"
        case unitClass = "unit_class"
    }
}

public struct StatisticsUnitConfiguration: Codable, Equatable {
    public var energy: String?
    public var power: String?
    public var pressure: String?
    public var temperature: String?
    public var volume: String?

    public init(
        energy: String? = nil,
        power: String? = nil,
        pressure: String? = nil,
        temperature: String? = nil,
        volume: String? = nil
    ) {
        self.energy = energy
        self.power = power
        self.pressure = pressure
        self.temperature = temperature
        self.volume = volume
    }

    var historyPayload: HAJSONValue {
        var object: [String: HAJSONValue] = [:]
        if let energy = energy {
            object["energy"] = .string(energy)
        }
        if let power = power {
            object["power"] = .string(power)
        }
        if let pressure = pressure {
            object["pressure"] = .string(pressure)
        }
        if let temperature = temperature {
            object["temperature"] = .string(temperature)
        }
        if let volume = volume {
            object["volume"] = .string(volume)
        }
        return .object(object)
    }
}

enum HistoryModelCoding {
    static func decodeDouble(from decoder: Decoder) throws -> Double {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            return value
        }
        if let value = try? container.decode(Int.self) {
            return Double(value)
        }
        if let value = try? container.decode(String.self), let double = Double(value) {
            return double
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected a numeric Home Assistant history value."
        )
    }

    static func statisticString(from value: Double) -> String {
        guard value.isFinite else {
            return String(value)
        }
        if value.rounded(.towardZero) == value,
           value >= Double(Int64.min),
           value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return HANumberFormatting.format(value, maximumFractionDigits: 12, useGrouping: false)
    }
}

extension KeyedDecodingContainer {
    func decodeHistoryDouble(forKey key: Key) throws -> Double {
        try HistoryModelCoding.decodeDouble(from: superDecoder(forKey: key))
    }

    func decodeHistoryDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        return try HistoryModelCoding.decodeDouble(from: superDecoder(forKey: key))
    }
}
