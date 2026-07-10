import CoreGraphics
import Foundation
import NativeHACore
import SwiftUI

struct PreparedTimelineSegment: Equatable {
    var rowIndex: Int
    var entityID: EntityID
    var rowName: String
    var state: String
    var stateLocalized: String
    var colorHex: String
    var textColorHex: String
    var originalStart: Double
    var originalEnd: Double
    var clippedStart: Double
    var clippedEnd: Double
    var rect: CGRect
    var labelVisible: Bool
}

struct PreparedTimelineRow: Equatable {
    var index: Int
    var entityID: EntityID
    var name: String
    var rect: CGRect
    var segments: [PreparedTimelineSegment]
}

struct PreparedTimelineChart: Equatable {
    var geometry: ChartGeometry
    var visibleRange: ChartVisibleRange
    var rows: [PreparedTimelineRow]

    var segments: [PreparedTimelineSegment] {
        rows.flatMap(\.segments)
    }

    var drawableSegmentCount: Int {
        rows.reduce(0) { $0 + $1.segments.count }
    }
}

enum TimelineChartRenderer {
    static func dataRange(in rows: [TimelineRow]) -> ChartVisibleRange {
        var minimum: Double?
        var maximum: Double?

        for row in rows {
            for segment in row.segments {
                if segment.start.isFinite {
                    minimum = minimum.map { min($0, segment.start) } ?? segment.start
                    maximum = maximum.map { max($0, segment.start) } ?? segment.start
                }
                if segment.end.isFinite {
                    minimum = minimum.map { min($0, segment.end) } ?? segment.end
                    maximum = maximum.map { max($0, segment.end) } ?? segment.end
                }
            }
        }

        return ChartVisibleRange(
            minimum ?? 0,
            maximum ?? ChartVisibleRange.defaultMinimumSpan
        )
    }

    static func prepare(
        rows: [TimelineRow],
        visibleRange: ChartVisibleRange,
        size: CGSize,
        showRowLabels: Bool = true,
        showSegmentLabels: Bool = true,
        theme: ChartTheme = .default
    ) -> PreparedTimelineChart {
        let geometry = ChartGeometry.timeline(
            size: size,
            visibleRange: visibleRange,
            insets: showRowLabels ? theme.timelineInsets : theme.compactTimelineInsets
        )

        let preparedRows: [PreparedTimelineRow] = rows.enumerated().map { rowIndex, row -> PreparedTimelineRow in
            let rowRect = ChartGeometryCalculator.timelineRowRect(
                plotRect: geometry.plotRect,
                rowIndex: rowIndex,
                rowCount: rows.count,
                rowHeight: theme.timelineRowHeight,
                rowSpacing: theme.timelineRowSpacing
            )
            let segments = row.segments.compactMap { segment in
                prepareSegment(
                    segment,
                    row: row,
                    rowIndex: rowIndex,
                    rowRect: rowRect,
                    geometry: geometry,
                    visibleRange: visibleRange,
                    showLabels: showSegmentLabels,
                    theme: theme
                )
            }
            return PreparedTimelineRow(
                index: rowIndex,
                entityID: row.entityID,
                name: row.name,
                rect: rowRect,
                segments: segments
            )
        }

        return PreparedTimelineChart(
            geometry: geometry,
            visibleRange: visibleRange,
            rows: preparedRows
        )
    }

    static func hitTest(
        _ chart: PreparedTimelineChart,
        point: CGPoint
    ) -> ChartTooltipModel? {
        for segment in chart.segments where segment.rect.contains(point) {
            let timestamp = min(
                max(chart.geometry.xScale.value(for: point.x), segment.clippedStart),
                segment.clippedEnd
            )
            return ChartTooltipModel(
                timestamp: timestamp,
                screenPosition: CGPoint(x: point.x, y: segment.rect.midY),
                item: .timeline(ChartTooltipModel.TimelineItem(
                    entityID: segment.entityID,
                    rowName: segment.rowName,
                    state: segment.state,
                    stateLocalized: segment.stateLocalized,
                    start: segment.originalStart,
                    end: segment.originalEnd,
                    durationMilliseconds: max(0, segment.originalEnd - segment.originalStart)
                ))
            )
        }
        return nil
    }

    private static func prepareSegment(
        _ segment: TimelineSegment,
        row: TimelineRow,
        rowIndex: Int,
        rowRect: CGRect,
        geometry: ChartGeometry,
        visibleRange: ChartVisibleRange,
        showLabels: Bool,
        theme: ChartTheme
    ) -> PreparedTimelineSegment? {
        guard segment.start.isFinite,
              segment.end.isFinite,
              segment.end >= visibleRange.lowerBound,
              segment.start <= visibleRange.upperBound else {
            return nil
        }

        let clippedStart = min(max(segment.start, visibleRange.lowerBound), visibleRange.upperBound)
        let clippedEnd = min(max(segment.end, visibleRange.lowerBound), visibleRange.upperBound)
        guard clippedEnd >= clippedStart else {
            return nil
        }

        var x = geometry.xScale.pixel(for: clippedStart)
        var width = geometry.xScale.pixel(for: clippedEnd) - x
        if width <= 0 {
            guard visibleRange.contains(clippedStart) else {
                return nil
            }
            width = theme.minimumTimelineSegmentWidth
        } else if width < theme.minimumTimelineSegmentWidth {
            width = theme.minimumTimelineSegmentWidth
        }

        if x + width > geometry.plotRect.maxX {
            width = max(0, geometry.plotRect.maxX - x)
        }
        if x < geometry.plotRect.minX {
            width -= geometry.plotRect.minX - x
            x = geometry.plotRect.minX
        }
        guard width >= 0 else {
            return nil
        }

        let rect = CGRect(x: x, y: rowRect.minY, width: width, height: rowRect.height)
        let labelWidth = estimatedTextWidth(segment.stateLocalized, fontSize: 12)
        let labelVisible = showLabels &&
            !segment.stateLocalized.isEmpty &&
            labelWidth + theme.timelineLabelPadding * 2 <= rect.width

        return PreparedTimelineSegment(
            rowIndex: rowIndex,
            entityID: row.entityID,
            rowName: row.name,
            state: segment.state,
            stateLocalized: segment.stateLocalized,
            colorHex: segment.colorHex,
            textColorHex: ChartTheme.contrastingTextHex(for: segment.colorHex),
            originalStart: segment.start,
            originalEnd: segment.end,
            clippedStart: clippedStart,
            clippedEnd: clippedEnd,
            rect: rect,
            labelVisible: labelVisible
        )
    }

    private static func estimatedTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        CGFloat(text.count) * fontSize * 0.56
    }
}

struct TimelineHistoryChartView: View {
    var rows: [TimelineRow]
    var initialVisibleRange: ChartVisibleRange?
    var showRowLabels: Bool
    var showSegmentLabels: Bool
    var theme: ChartTheme
    var minimumHeight: CGFloat

    @State private var interaction: ChartInteractionState?
    @State private var dragStartRange: ChartVisibleRange?
    @State private var zoomStartRange: ChartVisibleRange?
    @State private var tooltip: ChartTooltipModel?

    init(
        rows: [TimelineRow],
        initialVisibleRange: ChartVisibleRange? = nil,
        showRowLabels: Bool = true,
        showSegmentLabels: Bool = true,
        theme: ChartTheme = .default,
        minimumHeight: CGFloat? = nil
    ) {
        self.rows = rows
        self.initialVisibleRange = initialVisibleRange
        self.showRowLabels = showRowLabels
        self.showSegmentLabels = showSegmentLabels
        self.theme = theme
        self.minimumHeight = minimumHeight ?? max(60, CGFloat(rows.count) * 30 + 30)
    }

    var body: some View {
        GeometryReader { proxy in
            let dataBounds = TimelineChartRenderer.dataRange(in: rows)
            let currentInteraction = interaction ?? ChartInteractionState(
                dataBounds: dataBounds,
                visibleRange: initialVisibleRange
            )
            let prepared = TimelineChartRenderer.prepare(
                rows: rows,
                visibleRange: currentInteraction.visibleRange,
                size: proxy.size,
                showRowLabels: showRowLabels,
                showSegmentLabels: showSegmentLabels,
                theme: theme
            )

            ChartCanvasView(minimumHeight: minimumHeight) { context, _ in
                draw(prepared, in: &context)
            } overlay: {
                if let tooltip = tooltip {
                    ChartTooltipView(tooltip: tooltip, theme: theme)
                        .position(tooltipPosition(for: tooltip, in: proxy.size))
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(prepared: prepared, dataBounds: dataBounds))
            .simultaneousGesture(zoomGesture(dataBounds: dataBounds))
            .onTapGesture(count: 2) {
                var state = interaction ?? currentInteraction
                state.toggleThirtyPercentZoom()
                interaction = state
                tooltip = nil
            }
        }
        .frame(minHeight: minimumHeight)
    }

    private func dragGesture(
        prepared: PreparedTimelineChart,
        dataBounds: ChartVisibleRange
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                var state = interaction ?? ChartInteractionState(
                    dataBounds: dataBounds,
                    visibleRange: initialVisibleRange
                )
                if dragStartRange == nil {
                    dragStartRange = state.visibleRange
                }
                if let dragStartRange = dragStartRange {
                    state.visibleRange = dragStartRange
                    state.pan(
                        pixelDelta: value.translation.width,
                        plotWidth: prepared.geometry.plotRect.width
                    )
                    interaction = state
                }
                tooltip = TimelineChartRenderer.hitTest(prepared, point: value.location)
            }
            .onEnded { _ in
                dragStartRange = nil
            }
    }

    private func zoomGesture(dataBounds: ChartVisibleRange) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                var state = interaction ?? ChartInteractionState(
                    dataBounds: dataBounds,
                    visibleRange: initialVisibleRange
                )
                if zoomStartRange == nil {
                    zoomStartRange = state.visibleRange
                }
                if let zoomStartRange = zoomStartRange {
                    state.visibleRange = zoomStartRange
                    state.zoom(magnification: Double(value), anchorTimestamp: zoomStartRange.midpoint)
                    interaction = state
                }
            }
            .onEnded { _ in
                zoomStartRange = nil
            }
    }

    private func draw(_ chart: PreparedTimelineChart, in context: inout GraphicsContext) {
        drawAxes(chart, in: &context)

        for row in chart.rows {
            if showRowLabels {
                context.draw(
                    Text(row.name).font(.caption).foregroundColor(theme.labelColor),
                    at: CGPoint(x: chart.geometry.plotRect.minX - 6, y: row.rect.midY),
                    anchor: .trailing
                )
            }

            for segment in row.segments {
                let color = theme.color(hex: segment.colorHex)
                let rectPath = Path(roundedRect: segment.rect, cornerRadius: 2)
                context.fill(rectPath, with: .color(color))

                if segment.labelVisible {
                    context.draw(
                        Text(segment.stateLocalized)
                            .font(.caption2)
                            .foregroundColor(theme.color(hex: segment.textColorHex, fallback: .white)),
                        at: CGPoint(
                            x: segment.rect.minX + theme.timelineLabelPadding,
                            y: segment.rect.midY
                        ),
                        anchor: .leading
                    )
                }
            }
        }
    }

    private func drawAxes(_ chart: PreparedTimelineChart, in context: inout GraphicsContext) {
        let plotRect = chart.geometry.plotRect
        let tickCount = 4
        let gridPath = Path { path in
            for index in 0...tickCount {
                let ratio = CGFloat(index) / CGFloat(tickCount)
                let x = plotRect.minX + plotRect.width * ratio
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            }
            path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        }
        context.stroke(gridPath, with: .color(theme.gridColor), lineWidth: theme.gridLineWidth)

        for index in 0...tickCount {
            let ratio = Double(index) / Double(tickCount)
            let timestamp = chart.visibleRange.lowerBound + chart.visibleRange.span * ratio
            let x = chart.geometry.xScale.pixel(for: timestamp)
            let label = HADateTimeFormatting.formatTime(
                Date(timeIntervalSince1970: timestamp / 1_000)
            )
            context.draw(
                Text(label).font(.caption2).foregroundColor(theme.labelColor),
                at: CGPoint(x: x, y: plotRect.maxY + 14),
                anchor: .center
            )
        }
    }

    private func tooltipPosition(for tooltip: ChartTooltipModel, in size: CGSize) -> CGPoint {
        let x = min(max(tooltip.screenPosition.x + theme.tooltipGap, 60), max(60, size.width - 80))
        let y = min(max(tooltip.screenPosition.y - theme.tooltipGap, 24), max(24, size.height - 24))
        return CGPoint(x: x, y: y)
    }
}
