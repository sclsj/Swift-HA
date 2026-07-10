import CoreGraphics
import Foundation
import NativeHACore
import SwiftUI

struct ChartTooltipModel: Equatable, Identifiable {
    struct LineItem: Equatable {
        var seriesID: String
        var entityID: EntityID
        var seriesName: String
        var value: Double
        var formattedValue: String
        var unit: String?
        var source: LinePointSource
    }

    struct TimelineItem: Equatable {
        var entityID: EntityID
        var rowName: String
        var state: String
        var stateLocalized: String
        var start: Double
        var end: Double
        var durationMilliseconds: Double
    }

    enum Item: Equatable {
        case line(LineItem)
        case timeline(TimelineItem)
    }

    var timestamp: Double
    var screenPosition: CGPoint
    var item: Item

    var id: String {
        switch item {
        case let .line(line):
            return "line:\(line.seriesID):\(timestamp)"
        case let .timeline(timeline):
            return "timeline:\(timeline.entityID):\(timeline.start):\(timeline.end)"
        }
    }
}

struct ChartTooltipView: View {
    var tooltip: ChartTooltipModel
    var theme: ChartTheme = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            switch tooltip.item {
            case let .line(item):
                Text(item.seriesName)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.formattedValue)
                    .font(.caption.weight(.semibold))
            case let .timeline(item):
                Text(item.rowName)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.stateLocalized)
                    .font(.caption.weight(.semibold))
                Text(durationText(item.durationMilliseconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.tooltipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.tooltipBorder, lineWidth: 1)
        )
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        HADateTimeFormatting.formatDateTime(Date(timeIntervalSince1970: tooltip.timestamp / 1_000))
    }

    private func durationText(_ milliseconds: Double) -> String {
        let seconds = max(0, Int((milliseconds / 1_000).rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        if minutes > 0 {
            return "\(minutes) min \(remainingSeconds) s"
        }
        return "\(remainingSeconds) s"
    }
}
