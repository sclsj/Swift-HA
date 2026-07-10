import Foundation

public enum HAClimateFeature: Int {
    case targetTemperature = 1
    case targetTemperatureRange = 2
    case targetHumidity = 4
    case fanMode = 8
    case presetMode = 16
    case swingMode = 32
    case auxHeat = 64
    case turnOff = 128
    case turnOn = 256
    case swingHorizontalMode = 512
}

public struct ClimateControlModel: Equatable {
    public var entityID: EntityID
    public var state: String
    public var stateDisplay: String
    public var isUnavailable: Bool
    public var currentTemperatureDisplay: String?
    public var targetTemperatureDisplay: String?
    public var currentHumidityDisplay: String?
    public var hvacMode: String
    public var hvacModes: [String]
    public var presetMode: String?
    public var presetModes: [String]
    public var fanMode: String?
    public var fanModes: [String]
    public var swingMode: String?
    public var swingModes: [String]
    public var targetTemperature: Double?
    public var minTemperature: Double?
    public var maxTemperature: Double?
    public var targetTemperatureStep: Double
    public var supportsTargetTemperature: Bool

    public init?(
        stateObj: HassEntity,
        registryEntry: HAEntityRegistryDisplayEntry? = nil,
        config: HAConfig? = nil
    ) {
        guard EntityIDParser.domain(from: stateObj.entityID) == "climate" else {
            return nil
        }

        entityID = stateObj.entityID
        state = stateObj.state
        stateDisplay = HAEntityFormatting.stateDisplay(
            for: stateObj,
            registryEntry: registryEntry,
            config: config
        )
        isUnavailable = stateObj.state == HAStateValue.unavailable
        currentTemperatureDisplay = Self.displayIfPresent(
            stateObj,
            attribute: "current_temperature",
            config: config
        )
        targetTemperatureDisplay = Self.displayIfPresent(
            stateObj,
            attribute: "temperature",
            config: config
        )
        currentHumidityDisplay = Self.displayIfPresent(
            stateObj,
            attribute: "current_humidity",
            config: config
        )
        hvacMode = stateObj.state
        hvacModes = Self.sortedHvacModes(Self.stringArray(stateObj.attributes["hvac_modes"]))
        presetMode = stateObj.attributes["preset_mode"]?.haScalarStringValue
        presetModes = Self.optionArray(
            stateObj.attributes["preset_modes"],
            stateObj: stateObj,
            feature: .presetMode
        )
        fanMode = stateObj.attributes["fan_mode"]?.haScalarStringValue
        fanModes = Self.optionArray(
            stateObj.attributes["fan_modes"],
            stateObj: stateObj,
            feature: .fanMode
        )
        swingMode = stateObj.attributes["swing_mode"]?.haScalarStringValue
        swingModes = Self.optionArray(
            stateObj.attributes["swing_modes"],
            stateObj: stateObj,
            feature: .swingMode
        )
        targetTemperature = stateObj.attributes["temperature"]?.haNumberValue
        minTemperature = stateObj.attributes["min_temp"]?.haNumberValue
        maxTemperature = stateObj.attributes["max_temp"]?.haNumberValue
        targetTemperatureStep = Self.temperatureStep(stateObj: stateObj, config: config)
        supportsTargetTemperature = Self.supports(.targetTemperature, stateObj: stateObj)
            || targetTemperature != nil
    }

    public var tileStateSummary: String {
        var parts = [stateDisplay]
        if let currentTemperatureDisplay = currentTemperatureDisplay {
            parts.append("Current \(currentTemperatureDisplay)")
        }
        if let targetTemperatureDisplay = targetTemperatureDisplay {
            parts.append("Target \(targetTemperatureDisplay)")
        }
        return parts.joined(separator: " · ")
    }

    public func nextTemperature(delta: Double) -> Double? {
        guard let targetTemperature = targetTemperature else {
            return nil
        }
        return steppedTemperature(targetTemperature + delta)
    }

    public func steppedTemperature(_ value: Double) -> Double {
        let min = minTemperature ?? value
        let max = maxTemperature ?? value
        let clamped = Swift.max(min, Swift.min(max, value))
        let step = targetTemperatureStep > 0 ? targetTemperatureStep : 0.5
        let stepped = ((clamped - min) / step).rounded() * step + min
        return Swift.max(min, Swift.min(max, stepped))
    }

    public func setTemperatureCall(_ temperature: Double) -> HAServiceCall? {
        guard !isUnavailable else {
            return nil
        }

        return HAServiceCall(
            domain: "climate",
            service: "set_temperature",
            serviceData: [
                "entity_id": .string(entityID),
                "temperature": .double(steppedTemperature(temperature))
            ]
        )
    }

    public func setHVACModeCall(_ mode: String) -> HAServiceCall? {
        modeCall(
            current: hvacMode,
            selected: mode,
            options: hvacModes,
            service: "set_hvac_mode",
            field: "hvac_mode"
        )
    }

    public func setPresetModeCall(_ mode: String) -> HAServiceCall? {
        modeCall(
            current: presetMode,
            selected: mode,
            options: presetModes,
            service: "set_preset_mode",
            field: "preset_mode"
        )
    }

    public func setFanModeCall(_ mode: String) -> HAServiceCall? {
        modeCall(
            current: fanMode,
            selected: mode,
            options: fanModes,
            service: "set_fan_mode",
            field: "fan_mode"
        )
    }

    public func setSwingModeCall(_ mode: String) -> HAServiceCall? {
        modeCall(
            current: swingMode,
            selected: mode,
            options: swingModes,
            service: "set_swing_mode",
            field: "swing_mode"
        )
    }

    private func modeCall(
        current: String?,
        selected: String,
        options: [String],
        service: String,
        field: String
    ) -> HAServiceCall? {
        guard !isUnavailable, current != selected else {
            return nil
        }
        guard options.isEmpty || options.contains(selected) else {
            return nil
        }

        return HAServiceCall(
            domain: "climate",
            service: service,
            serviceData: [
                "entity_id": .string(entityID),
                field: .string(selected)
            ]
        )
    }

    private static func displayIfPresent(
        _ stateObj: HassEntity,
        attribute: String,
        config: HAConfig?
    ) -> String? {
        guard stateObj.attributes[attribute] != nil else {
            return nil
        }
        return HAEntityFormatting.attributeDisplay(
            for: stateObj,
            attribute: attribute,
            config: config
        )
    }

    private static func optionArray(
        _ value: HAJSONValue?,
        stateObj: HassEntity,
        feature: HAClimateFeature
    ) -> [String] {
        let values = stringArray(value)
        guard !values.isEmpty else {
            return []
        }

        if stateObj.attributes["supported_features"] == nil {
            return values
        }

        return supports(feature, stateObj: stateObj) ? values : []
    }

    private static func stringArray(_ value: HAJSONValue?) -> [String] {
        guard case let .array(values) = value else {
            return []
        }
        return values.compactMap(\.haScalarStringValue)
    }

    private static func sortedHvacModes(_ modes: [String]) -> [String] {
        modes.sorted {
            let lhs = hvacModeOrder[$0, default: Int.max]
            let rhs = hvacModeOrder[$1, default: Int.max]
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
    }

    private static func supports(_ feature: HAClimateFeature, stateObj: HassEntity) -> Bool {
        guard let value = stateObj.attributes["supported_features"]?.haNumberValue else {
            return false
        }
        return Int(value) & feature.rawValue != 0
    }

    private static func temperatureStep(stateObj: HassEntity, config: HAConfig?) -> Double {
        if let step = stateObj.attributes["target_temp_step"]?.haNumberValue, step > 0 {
            return step
        }

        let unit = config?.unitSystem["temperature"]
            ?? stateObj.attributes["temperature_unit"]?.stringValue
        return unit == "°F" || unit == "F" ? 1 : 0.5
    }

    private static let hvacModeOrder: [String: Int] = [
        "auto": 0,
        "heat_cool": 1,
        "heat": 2,
        "cool": 3,
        "dry": 4,
        "fan_only": 5,
        "off": 6
    ]
}
