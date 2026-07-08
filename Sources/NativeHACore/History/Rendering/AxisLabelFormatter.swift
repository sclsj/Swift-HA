import Foundation

public enum AxisLabelFormatter {
    public static func fractionDigits(minimum: Double?, maximum: Double?) -> Int {
        guard let minimum = minimum,
              let maximum = maximum,
              minimum.isFinite,
              maximum.isFinite else {
            return 1
        }
        return computeYAxisFractionDigits(minimum: minimum, maximum: maximum)
    }

    public static func computeYAxisFractionDigits(minimum: Double, maximum: Double) -> Int {
        let range = maximum - minimum
        guard range.isFinite, range > 0 else {
            return 1
        }
        return max(0, Int(ceil(-log10(range / 10))))
    }

    public static func metadata(
        unit: String?,
        deviceClass: String?,
        minimum: Double?,
        maximum: Double?
    ) -> YAxisMetadata {
        YAxisMetadata(
            unit: unit,
            deviceClass: deviceClass,
            minimum: minimum,
            maximum: maximum,
            fractionDigits: fractionDigits(minimum: minimum, maximum: maximum)
        )
    }

    public static func format(
        _ value: Double,
        metadata: YAxisMetadata,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> String {
        HANumberFormatting.formatWithUnit(
            value,
            unit: normalizedUnit(metadata.unit),
            locale: locale,
            maximumFractionDigits: metadata.fractionDigits
        )
    }

    private static func normalizedUnit(_ unit: String?) -> String? {
        guard let unit = unit, unit != HistoryProcessor.blankUnit else {
            return nil
        }
        return unit
    }
}
