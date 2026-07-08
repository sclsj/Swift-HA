import Foundation

public enum HAEntityFormatting {
    public static func displayName(
        for stateObj: HassEntity,
        overrideName: String? = nil
    ) -> String {
        if let overrideName = overrideName {
            return overrideName
        }

        if let friendlyNameValue = stateObj.attributes["friendly_name"] {
            return friendlyNameValue.haScalarStringValue ?? ""
        }

        return EntityIDParser.displayObjectID(from: stateObj.entityID)
    }

    public static func stateDisplay(
        for stateObj: HassEntity,
        registryEntry: HAEntityRegistryDisplayEntry? = nil,
        config: HAConfig? = nil,
        locale: Locale = HANumberFormatting.defaultLocale,
        state overrideState: String? = nil
    ) -> String {
        stateDisplay(
            entityID: stateObj.entityID,
            state: overrideState ?? stateObj.state,
            attributes: stateObj.attributes,
            registryEntry: registryEntry,
            config: config,
            locale: locale
        )
    }

    public static func stateDisplay(
        entityID: EntityID,
        state: String,
        attributes: [String: HAJSONValue],
        registryEntry: HAEntityRegistryDisplayEntry? = nil,
        config: HAConfig? = nil,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> String {
        if state == HAStateValue.unknown {
            return "unknown"
        }

        if state == HAStateValue.unavailable {
            return "unavailable"
        }

        let domain = EntityIDParser.domain(from: entityID)
        let timeZone = resolvedTimeZone(config)

        if HADomainLogic.dateTimeDomains.contains(domain),
           let display = HADateTimeFormatting.formatLocalDateTimeState(state, locale: locale, timeZone: timeZone) {
            return display
        }

        if HADomainLogic.isTimestampEntity(entityID: entityID, attributes: attributes),
           let display = HADateTimeFormatting.formatTimestampState(state, locale: locale, timeZone: timeZone) {
            return display
        }

        if HADomainLogic.isNumericEntity(entityID: entityID, attributes: attributes) {
            let precision = displayPrecision(registryEntry: registryEntry, attributes: attributes)
            if attributes["device_class"]?.stringValue == "duration",
               let unit = attributes["unit_of_measurement"]?.stringValue,
               let value = Double(state),
               let duration = HADateTimeFormatting.formatDuration(value, unit: unit, displayPrecision: precision) {
                return duration
            }

            let formatted = HANumberFormatting.format(
                numericString: state,
                locale: locale,
                displayPrecision: precision
            )
            return HANumberFormatting.append(
                unit: attributes["unit_of_measurement"]?.stringValue,
                to: formatted,
                locale: locale
            )
        }

        return state
    }

    public static func attributeDisplay(
        for stateObj: HassEntity,
        attribute: String,
        config: HAConfig? = nil,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> String {
        guard let value = stateObj.attributes[attribute], value != .null else {
            return "unknown"
        }

        return attributeValueDisplay(
            value,
            stateObj: stateObj,
            attribute: attribute,
            config: config,
            locale: locale
        )
    }

    public static func attributeNameDisplay(_ attribute: String) -> String {
        let words = attribute
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word -> String in
                let lower = word.lowercased()
                switch lower {
                case "id":
                    return "ID"
                case "ip":
                    return "IP"
                case "mac":
                    return "MAC"
                case "gps":
                    return "GPS"
                default:
                    return String(word)
                }
            }

        guard let first = words.first else {
            return attribute
        }

        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    public static func defaultStateContent(for stateObj: HassEntity) -> [String] {
        switch EntityIDParser.domain(from: stateObj.entityID) {
        case "fan":
            return ["percentage"]
        case "climate":
            return ["state", "current_temperature"]
        default:
            return ["state"]
        }
    }

    public static func stateContentDisplay(
        _ content: String,
        for stateObj: HassEntity,
        registryEntry: HAEntityRegistryDisplayEntry? = nil,
        config: HAConfig? = nil,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> String? {
        switch content {
        case "state":
            return stateDisplay(for: stateObj, registryEntry: registryEntry, config: config, locale: locale)
        case "name":
            return displayName(for: stateObj)
        case "last_changed":
            return HADateTimeFormatting.formatDateTime(
                stateObj.lastChanged,
                locale: locale,
                timeZone: resolvedTimeZone(config)
            )
        case "last_updated":
            return HADateTimeFormatting.formatDateTime(
                stateObj.lastUpdated,
                locale: locale,
                timeZone: resolvedTimeZone(config)
            )
        default:
            guard stateObj.attributes[content] != nil else {
                return nil
            }
            return attributeDisplay(for: stateObj, attribute: content, config: config, locale: locale)
        }
    }

    public static func defaultStateContentDisplay(
        for stateObj: HassEntity,
        registryEntry: HAEntityRegistryDisplayEntry? = nil,
        config: HAConfig? = nil,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> String {
        defaultStateContent(for: stateObj)
            .compactMap {
                stateContentDisplay(
                    $0,
                    for: stateObj,
                    registryEntry: registryEntry,
                    config: config,
                    locale: locale
                )
            }
            .joined(separator: " · ")
    }

    private static func attributeValueDisplay(
        _ value: HAJSONValue,
        stateObj: HassEntity,
        attribute: String,
        config: HAConfig?,
        locale: Locale
    ) -> String {
        switch value {
        case .null:
            return "unknown"
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return formatAttributeNumber(
                Double(value),
                stateObj: stateObj,
                attribute: attribute,
                config: config,
                locale: locale
            )
        case let .double(value):
            return formatAttributeNumber(
                value,
                stateObj: stateObj,
                attribute: attribute,
                config: config,
                locale: locale
            )
        case let .string(value):
            if let dateDisplay = HADateTimeFormatting.formatTimestampState(
                value,
                locale: locale,
                timeZone: resolvedTimeZone(config)
            ) ?? HADateTimeFormatting.formatLocalDateTimeState(
                value,
                locale: locale,
                timeZone: resolvedTimeZone(config)
            ) {
                return dateDisplay
            }
            return value
        case let .array(values):
            return values
                .map {
                    attributeValueDisplay(
                        $0,
                        stateObj: stateObj,
                        attribute: attribute,
                        config: config,
                        locale: locale
                    )
                }
                .joined(separator: ", ")
        case let .object(object):
            return jsonString(from: .object(object))
        }
    }

    private static func formatAttributeNumber(
        _ value: Double,
        stateObj: HassEntity,
        attribute: String,
        config: HAConfig?,
        locale: Locale
    ) -> String {
        HANumberFormatting.formatWithUnit(
            value,
            unit: unitForAttribute(attribute, stateObj: stateObj, config: config),
            locale: locale
        )
    }

    private static func unitForAttribute(
        _ attribute: String,
        stateObj: HassEntity,
        config: HAConfig?
    ) -> String? {
        let domain = EntityIDParser.domain(from: stateObj.entityID)

        if domain == "fan", attribute == "percentage" {
            return "%"
        }

        if domain == "weather" {
            switch attribute {
            case "temperature", "dew_point":
                return stateObj.attributes["temperature_unit"]?.stringValue
            case "humidity", "cloud_coverage":
                return "%"
            case "pressure":
                return stateObj.attributes["pressure_unit"]?.stringValue
            case "wind_speed":
                return stateObj.attributes["wind_speed_unit"]?.stringValue
            case "visibility":
                return stateObj.attributes["visibility_unit"]?.stringValue
            case "precipitation":
                return stateObj.attributes["precipitation_unit"]?.stringValue
            case "wind_bearing":
                return "°"
            default:
                break
            }
        }

        if [
            "current_temperature",
            "temperature",
            "target_temp_low",
            "target_temp_high",
            "min_temp",
            "max_temp"
        ].contains(attribute) {
            return config?.unitSystem["temperature"] ?? stateObj.attributes["temperature_unit"]?.stringValue ?? "°C"
        }

        return nil
    }

    private static func displayPrecision(
        registryEntry: HAEntityRegistryDisplayEntry?,
        attributes: [String: HAJSONValue]
    ) -> Int? {
        if let precision = registryEntry?.displayPrecision {
            return precision
        }

        if let precision = attributes["display_precision"]?.haNumberValue {
            return Int(precision)
        }

        return nil
    }

    private static func resolvedTimeZone(_ config: HAConfig?) -> TimeZone {
        if let timeZone = config?.timeZone,
           let resolved = TimeZone(identifier: timeZone) {
            return resolved
        }
        return .current
    }

    private static func jsonString(from value: HAJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
