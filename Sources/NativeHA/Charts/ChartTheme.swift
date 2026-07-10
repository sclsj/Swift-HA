import CoreGraphics
import SwiftUI

struct ChartTheme {
    var plotInsets = ChartEdgeInsets(top: 14, leading: 44, bottom: 28, trailing: 12)
    var timelineInsets = ChartEdgeInsets(top: 10, leading: 110, bottom: 26, trailing: 8)
    var compactTimelineInsets = ChartEdgeInsets(top: 10, leading: 0, bottom: 26, trailing: 8)

    var lineWidth: CGFloat = 1.5
    var gridLineWidth: CGFloat = 1
    var pointRadius: CGFloat = 2
    var timelineRowHeight: CGFloat = 20
    var timelineRowSpacing: CGFloat = 10
    var timelineLabelPadding: CGFloat = 4
    var minimumTimelineSegmentWidth: CGFloat = 1
    var tooltipGap: CGFloat = 12

    var gridColor = Color.primary.opacity(0.12)
    var axisColor = Color.primary.opacity(0.18)
    var labelColor = Color.secondary
    var tooltipBackground = HAStyleTokens.cardBackgroundColor
    var tooltipBorder = HAStyleTokens.cardBorderColor

    static let `default` = ChartTheme()

    func color(hex: String?, fallback: Color = .accentColor) -> Color {
        guard let hex = hex, let color = Color(haHex: hex) else {
            return fallback
        }
        return color
    }

    static func contrastingTextHex(for backgroundHex: String) -> String {
        guard let rgb = rgbComponents(backgroundHex) else {
            return "#ffffff"
        }

        let luminance =
            0.2126 * linearComponent(rgb.red) +
            0.7152 * linearComponent(rgb.green) +
            0.0722 * linearComponent(rgb.blue)
        return luminance > 0.5 ? "#000000" : "#ffffff"
    }

    private static func rgbComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        return (
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }

    private static func linearComponent(_ value: Double) -> Double {
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}
