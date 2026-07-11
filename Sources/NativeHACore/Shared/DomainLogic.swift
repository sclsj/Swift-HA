import Foundation

public enum HAStateValue {
    public static let unavailable = "unavailable"
    public static let unknown = "unknown"
    public static let on = "on"
    public static let off = "off"

    public static let inactiveStates: Set<String> = [unavailable, unknown, off]
    public static let toggleOffStates: Set<String> = ["closed", "locked", off]

    public static func isUnknownOrUnavailable(_ state: String) -> Bool {
        state == unknown || state == unavailable
    }

    public static func isOffForToggle(_ state: String) -> Bool {
        toggleOffStates.contains(state)
    }
}

public enum HADomainLogic {
    public static let timestampStateDomains: Set<String> = [
        "ai_task",
        "button",
        "conversation",
        "datetime",
        "event",
        "image",
        "infrared",
        "input_button",
        "notify",
        "radio_frequency",
        "scene",
        "stt",
        "tag",
        "tts",
        "wake_word"
    ]

    public static let dateTimeDomains: Set<String> = [
        "date",
        "input_datetime",
        "time"
    ]

    public static let numericDomains: Set<String> = [
        "counter",
        "input_number",
        "number"
    ]

    public static let numericSensorDeviceClasses: Set<String> = [
        "absolute_humidity",
        "apparent_power",
        "aqi",
        "area",
        "atmospheric_pressure",
        "battery",
        "blood_glucose_concentration",
        "carbon_dioxide",
        "carbon_monoxide",
        "conductivity",
        "current",
        "data_rate",
        "data_size",
        "distance",
        "duration",
        "energy",
        "energy_distance",
        "energy_storage",
        "frequency",
        "gas",
        "humidity",
        "illuminance",
        "irradiance",
        "moisture",
        "monetary",
        "nitrogen_dioxide",
        "nitrogen_monoxide",
        "nitrous_oxide",
        "ozone",
        "ph",
        "pm1",
        "pm10",
        "pm25",
        "pm4",
        "power",
        "power_factor",
        "precipitation",
        "precipitation_intensity",
        "pressure",
        "radon",
        "reactive_energy",
        "reactive_power",
        "signal_strength",
        "sound_pressure",
        "speed",
        "sulphur_dioxide",
        "temperature",
        "temperature_delta",
        "volatile_organic_compounds",
        "volatile_organic_compounds_parts",
        "voltage",
        "volume",
        "volume_flow_rate",
        "volume_storage",
        "water",
        "weight",
        "wind_direction",
        "wind_speed"
    ]

    public static let sensorTimestampDeviceClasses: Set<String> = [
        "timestamp",
        "uptime"
    ]

    public static let stateColoredDomains: Set<String> = [
        "alarm_control_panel",
        "alert",
        "automation",
        "binary_sensor",
        "calendar",
        "camera",
        "climate",
        "cover",
        "device_tracker",
        "fan",
        "group",
        "humidifier",
        "input_boolean",
        "lawn_mower",
        "light",
        "lock",
        "media_player",
        "person",
        "plant",
        "remote",
        "schedule",
        "script",
        "siren",
        "sun",
        "switch",
        "timer",
        "update",
        "vacuum",
        "valve",
        "water_heater",
        "weather"
    ]

    public static func isNumericEntity(
        entityID: EntityID,
        attributes: [String: HAJSONValue]
    ) -> Bool {
        let domain = EntityIDParser.domain(from: entityID)
        if numericDomains.contains(domain) {
            return true
        }

        if attributes["unit_of_measurement"] != nil || attributes["state_class"] != nil {
            return true
        }

        if domain == "sensor",
           let deviceClass = attributes["device_class"]?.stringValue,
           numericSensorDeviceClasses.contains(deviceClass) {
            return true
        }

        return false
    }

    public static func isTimestampEntity(
        entityID: EntityID,
        attributes: [String: HAJSONValue]
    ) -> Bool {
        let domain = EntityIDParser.domain(from: entityID)
        if timestampStateDomains.contains(domain) {
            return true
        }

        return domain == "sensor"
            && attributes["device_class"]?.stringValue.map(sensorTimestampDeviceClasses.contains) == true
    }

    public static func isActive(_ stateObj: HassEntity, state overrideState: String? = nil) -> Bool {
        let domain = EntityIDParser.domain(from: stateObj.entityID)
        let state = overrideState ?? stateObj.state

        if timestampStateDomains.contains(domain) {
            return state != HAStateValue.unavailable
        }

        if HAStateValue.isUnknownOrUnavailable(state) {
            return false
        }

        if state == HAStateValue.off && domain != "alert" {
            return false
        }

        switch domain {
        case "alarm_control_panel":
            return state != "disarmed"
        case "alert":
            return state != "idle"
        case "cover":
            return state != "closed"
        case "device_tracker", "person":
            return state != "not_home"
        case "lawn_mower":
            return !["docked", "paused"].contains(state)
        case "lock":
            return state != "locked"
        case "media_player":
            return state != "standby"
        case "vacuum":
            return !["idle", "docked", "paused"].contains(state)
        case "valve":
            return state != "closed"
        case "plant":
            return state == "problem"
        case "group":
            return ["on", "home", "open", "locked", "problem"].contains(state)
        case "timer":
            return state == "active"
        case "camera":
            return state == "streaming"
        default:
            return true
        }
    }

    public static func turnOnOffServiceCall(
        entityID: EntityID,
        turnOn: Bool
    ) -> HAServiceCall {
        let domain = EntityIDParser.domain(from: entityID)
        let serviceDomain = domain == "group" ? "homeassistant" : domain
        let service: String

        switch domain {
        case "lock":
            service = turnOn ? "unlock" : "lock"
        case "cover":
            service = turnOn ? "open_cover" : "close_cover"
        case "button", "input_button":
            service = "press"
        case "scene":
            service = "turn_on"
        case "valve":
            service = turnOn ? "open_valve" : "close_valve"
        default:
            service = turnOn ? "turn_on" : "turn_off"
        }

        return HAServiceCall(
            domain: serviceDomain,
            service: service,
            serviceData: ["entity_id": .string(entityID)]
        )
    }

    public static func toggleServiceCall(
        entityID: EntityID,
        currentState: String
    ) -> HAServiceCall {
        turnOnOffServiceCall(
            entityID: entityID,
            turnOn: HAStateValue.isOffForToggle(currentState)
        )
    }
}

extension HAJSONValue {
    var haBoolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    public var haNumberValue: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }

    public var haScalarStringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return HANumberFormatting.format(value, maximumFractionDigits: 12)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return nil
        case .array, .object:
            return nil
        }
    }
}
