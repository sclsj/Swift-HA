import Foundation

public struct HAStateColor: Equatable {
    public var name: String
    public var hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum HAStateColorResolver {
    public static let unavailable = HAStateColor(name: "state-unavailable", hex: "#bdbdbd")
    public static let inactive = HAStateColor(name: "state-inactive", hex: "#44739e")
    public static let active = HAStateColor(name: "state-active", hex: "#fdd663")
    public static let activeBlue = HAStateColor(name: "state-active-blue", hex: "#039be5")
    public static let activeGreen = HAStateColor(name: "state-active-green", hex: "#43a047")
    public static let activeOrange = HAStateColor(name: "state-active-orange", hex: "#ff9800")
    public static let activeRed = HAStateColor(name: "state-active-red", hex: "#db4437")
    public static let cloudy = HAStateColor(name: "state-weather-cloudy", hex: "#90a4ae")

    public static func color(
        for stateObj: HassEntity,
        state overrideState: String? = nil
    ) -> HAStateColor? {
        let state = overrideState ?? stateObj.state
        let domain = EntityIDParser.domain(from: stateObj.entityID)

        if state == HAStateValue.unavailable {
            return unavailable
        }

        if domain == "sensor",
           stateObj.attributes["device_class"]?.stringValue == "battery",
           let value = Double(state) {
            return batteryColor(value)
        }

        guard HADomainLogic.stateColoredDomains.contains(domain) else {
            return nil
        }

        guard HADomainLogic.isActive(stateObj, state: state) else {
            return inactive
        }

        switch domain {
        case "binary_sensor":
            return binarySensorColor(stateObj: stateObj)
        case "climate":
            return climateColor(state: state)
        case "fan", "light", "switch":
            return active
        case "person", "device_tracker":
            return activeBlue
        case "weather":
            return weatherColor(state: state)
        case "alert", "plant", "update":
            return activeRed
        default:
            return active
        }
    }

    private static func binarySensorColor(stateObj: HassEntity) -> HAStateColor {
        switch stateObj.attributes["device_class"]?.stringValue {
        case "problem", "safety", "smoke", "gas", "moisture":
            return activeRed
        case "running", "power", "plug":
            return activeGreen
        default:
            return active
        }
    }

    private static func climateColor(state: String) -> HAStateColor {
        switch state {
        case "cool", "cooling":
            return activeBlue
        case "heat", "heating":
            return activeOrange
        default:
            return active
        }
    }

    private static func weatherColor(state: String) -> HAStateColor {
        switch state {
        case "sunny", "clear-night":
            return active
        case "rainy", "pouring", "lightning-rainy", "snowy-rainy":
            return activeBlue
        case "cloudy", "fog", "partlycloudy":
            return cloudy
        case "hail", "lightning", "snowy", "windy", "windy-variant":
            return activeOrange
        default:
            return active
        }
    }

    private static func batteryColor(_ percentage: Double) -> HAStateColor {
        if percentage <= 10 {
            return activeRed
        }
        if percentage <= 30 {
            return activeOrange
        }
        return activeGreen
    }
}
