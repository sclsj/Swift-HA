import Foundation

public enum HADateTimeFormatting {
    public static let defaultLocale = Locale(identifier: "en_US")

    public static func formatDateTime(
        _ date: Date,
        locale: Locale = defaultLocale,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func formatDate(
        _ date: Date,
        locale: Locale = defaultLocale,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public static func formatTime(
        _ date: Date,
        locale: Locale = defaultLocale,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func formatTimestampState(
        _ state: String,
        locale: Locale = defaultLocale,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let date = parseISO8601(state) else {
            return nil
        }

        return formatDateTime(date, locale: locale, timeZone: timeZone)
    }

    public static func formatLocalDateTimeState(
        _ state: String,
        locale: Locale = defaultLocale,
        timeZone: TimeZone = .current
    ) -> String? {
        if state.contains(" "), let date = parseLocal(state, format: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone)
            ?? parseLocal(state, format: "yyyy-MM-dd HH:mm", timeZone: timeZone) {
            return formatDateTime(date, locale: locale, timeZone: timeZone)
        }

        if state.contains("-"), let date = parseLocal(state, format: "yyyy-MM-dd", timeZone: timeZone) {
            return formatDate(date, locale: locale, timeZone: timeZone)
        }

        if state.contains(":"), let date = parseLocal(state, format: "HH:mm:ss", timeZone: timeZone)
            ?? parseLocal(state, format: "HH:mm", timeZone: timeZone) {
            return formatTime(date, locale: locale, timeZone: timeZone)
        }

        return nil
    }

    public static func formatDuration(
        _ value: Double,
        unit: String,
        displayPrecision: Int? = nil
    ) -> String? {
        guard let seconds = seconds(from: value, unit: unit, displayPrecision: displayPrecision) else {
            return nil
        }

        let roundedSeconds = max(0, Int(seconds.rounded()))
        if roundedSeconds == 0 {
            return "0 s"
        }

        let days = roundedSeconds / 86_400
        let hours = (roundedSeconds % 86_400) / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let secondsRemainder = roundedSeconds % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days) d")
        }
        if hours > 0 {
            parts.append("\(hours) h")
        }
        if minutes > 0 {
            parts.append("\(minutes) min")
        }
        if secondsRemainder > 0 || parts.isEmpty {
            parts.append("\(secondsRemainder) s")
        }
        return parts.joined(separator: " ")
    }

    private static func seconds(
        from value: Double,
        unit: String,
        displayPrecision: Int?
    ) -> Double? {
        let roundedValue: Double
        if let displayPrecision = displayPrecision {
            let scale = pow(10.0, Double(displayPrecision))
            roundedValue = (value * scale).rounded() / scale
        } else {
            roundedValue = value
        }

        switch unit {
        case "ms":
            return roundedValue / 1_000
        case "s":
            return roundedValue
        case "min":
            return roundedValue * 60
        case "h":
            return roundedValue * 3_600
        case "d":
            return roundedValue * 86_400
        default:
            return nil
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        DateFormatterCache.iso8601Fractional.date(from: value)
            ?? DateFormatterCache.iso8601Standard.date(from: value)
    }

    private static func parseLocal(
        _ value: String,
        format: String,
        timeZone: TimeZone
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.date(from: value)
    }
}

private enum DateFormatterCache {
    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
