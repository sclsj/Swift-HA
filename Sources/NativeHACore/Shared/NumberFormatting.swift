import Foundation

public enum HANumberFormatting {
    public static let defaultLocale = Locale(identifier: "en_US")

    public static func format(
        _ value: Double,
        locale: Locale = defaultLocale,
        minimumFractionDigits: Int? = nil,
        maximumFractionDigits: Int = 2,
        useGrouping: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = useGrouping
        formatter.maximumFractionDigits = maximumFractionDigits
        if let minimumFractionDigits = minimumFractionDigits {
            formatter.minimumFractionDigits = minimumFractionDigits
        }

        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func format(
        numericString: String,
        locale: Locale = defaultLocale,
        displayPrecision: Int? = nil,
        maximumFractionDigits: Int = 2
    ) -> String {
        guard let value = Double(numericString) else {
            return numericString
        }

        if let displayPrecision = displayPrecision {
            return format(
                value,
                locale: locale,
                minimumFractionDigits: displayPrecision,
                maximumFractionDigits: displayPrecision
            )
        }

        return format(
            value,
            locale: locale,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    public static func unitSpacing(
        before unit: String,
        locale: Locale = defaultLocale
    ) -> String {
        if unit == "°" {
            return ""
        }

        if unit == "%" {
            switch locale.languageCode {
            case "cs", "de", "fi", "fr", "sk", "sv":
                return " "
            default:
                return ""
            }
        }

        return " "
    }

    public static func formatWithUnit(
        _ value: Double,
        unit: String?,
        locale: Locale = defaultLocale,
        displayPrecision: Int? = nil,
        maximumFractionDigits: Int = 2
    ) -> String {
        let formatted: String
        if let displayPrecision = displayPrecision {
            formatted = format(
                value,
                locale: locale,
                minimumFractionDigits: displayPrecision,
                maximumFractionDigits: displayPrecision
            )
        } else {
            formatted = format(
                value,
                locale: locale,
                maximumFractionDigits: maximumFractionDigits
            )
        }

        return append(unit: unit, to: formatted, locale: locale)
    }

    public static func append(
        unit: String?,
        to formattedValue: String,
        locale: Locale = defaultLocale
    ) -> String {
        guard let unit = unit, !unit.isEmpty else {
            return formattedValue
        }

        return formattedValue + unitSpacing(before: unit, locale: locale) + unit
    }
}
