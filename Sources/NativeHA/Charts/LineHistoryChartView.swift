import CoreGraphics
import Foundation
import NativeHACore
import SwiftUI

struct PreparedLinePoint: Equatable {
    var timestamp: Double
    var value: Double
    var source: LinePointSource
    var position: CGPoint
}

struct PreparedLineSegment: Equatable {
    var source: LinePointSource
    var alpha: Double
    var points: [PreparedLinePoint]
}

struct PreparedLineSeries: Equatable {
    var id: String
    var entityID: EntityID
    var name: String
    var unit: String?
    var deviceClass: String?
    var colorHex: String?
    var isFilled: Bool
    var sourceRanges: [LineSeriesSourceRange]
    var sourceSeries: LineSeries
    var segments: [PreparedLineSegment]
    var singlePoints: [PreparedLinePoint]
    var hitPoints: [PreparedLinePoint]
}

struct PreparedLineChart: Equatable {
    var geometry: ChartGeometry
    var visibleRange: ChartVisibleRange
    var yDomain: ChartValueRange
    var yAxisMetadata: YAxisMetadata
    var series: [PreparedLineSeries]

    var drawableVertexCount: Int {
        series.reduce(0) { count, item in
            count +
                item.segments.reduce(0) { $0 + $1.points.count } +
                item.singlePoints.count
        }
    }
}

enum LineChartRenderer {
    static func dataRange(in series: [LineSeries]) -> ChartVisibleRange {
        var minimum: Double?
        var maximum: Double?

        for item in series {
            for point in item.points where point.x.isFinite {
                minimum = minimum.map { min($0, point.x) } ?? point.x
                maximum = maximum.map { max($0, point.x) } ?? point.x
            }
        }

        return ChartVisibleRange(
            minimum ?? 0,
            maximum ?? ChartVisibleRange.defaultMinimumSpan
        )
    }

    static func prepare(
        series: [LineSeries],
        visibleRange: ChartVisibleRange,
        size: CGSize,
        yAxisMetadata: YAxisMetadata = YAxisMetadata(),
        fixedMinimumY: Double? = nil,
        fixedMaximumY: Double? = nil,
        fitYData: Bool = false,
        logarithmicScale: Bool = false,
        theme: ChartTheme = .default,
        maximumDetail: Double? = nil
    ) -> PreparedLineChart {
        let yScaleKind: AxisScaleKind = logarithmicScale ? .logarithmic : .linear
        let yDomain = AxisScale.lineYDomain(
            in: series,
            visibleRange: visibleRange,
            fixedMinimum: fixedMinimumY,
            fixedMaximum: fixedMaximumY,
            fitYData: fitYData,
            scaleKind: yScaleKind
        )
        let geometry = ChartGeometry.line(
            size: size,
            visibleRange: visibleRange,
            yDomain: yDomain,
            insets: theme.plotInsets,
            yScaleKind: yScaleKind
        )
        let resolvedMetadata = YAxisMetadata(
            unit: yAxisMetadata.unit,
            deviceClass: yAxisMetadata.deviceClass,
            minimum: yDomain.lowerBound,
            maximum: yDomain.upperBound,
            fractionDigits: AxisLabelFormatter.fractionDigits(
                minimum: yDomain.lowerBound,
                maximum: yDomain.upperBound
            )
        )

        let preparedSeries = series.map { item -> PreparedLineSeries in
            let sampled = sampleIfNeeded(
                item,
                maximumDetail: maximumDetail,
                visibleRange: visibleRange
            )
            return prepareSeries(
                sampled,
                original: item,
                geometry: geometry,
                visibleRange: visibleRange
            )
        }

        return PreparedLineChart(
            geometry: geometry,
            visibleRange: visibleRange,
            yDomain: yDomain,
            yAxisMetadata: resolvedMetadata,
            series: preparedSeries
        )
    }

    static func lineValue(
        at timestamp: Double,
        in series: LineSeries,
        visibleRange: ChartVisibleRange
    ) -> LinePoint? {
        guard timestamp.isFinite, visibleRange.contains(timestamp) else {
            return nil
        }

        var current: LinePoint?
        for point in series.points where point.x.isFinite {
            if point.x > timestamp {
                break
            }
            if let y = point.y, y.isFinite {
                current = point
            } else {
                current = nil
            }
        }
        return current
    }

    static func nearestTooltip(
        in chart: PreparedLineChart,
        timestamp: Double,
        screenLocation: CGPoint? = nil,
        locale: Locale = HANumberFormatting.defaultLocale
    ) -> ChartTooltipModel? {
        guard timestamp.isFinite, chart.visibleRange.contains(timestamp),
              let yScale = chart.geometry.yScale else {
            return nil
        }

        var best: (tooltip: ChartTooltipModel, distance: CGFloat)?
        for item in chart.series {
            guard let point = lineValue(
                at: timestamp,
                in: item.sourceSeries,
                visibleRange: chart.visibleRange
            ), let value = point.y, value.isFinite else {
                continue
            }

            guard let y = yScale.pixelIfValid(for: value) else {
                continue
            }
            let position = CGPoint(
                x: chart.geometry.xScale.pixel(for: timestamp),
                y: y
            )
            let distance: CGFloat
            if let screenLocation = screenLocation {
                distance = hypot(position.x - screenLocation.x, position.y - screenLocation.y)
            } else {
                distance = abs(CGFloat(point.x - timestamp))
            }

            let metadata = YAxisMetadata(
                unit: item.unit ?? chart.yAxisMetadata.unit,
                deviceClass: item.deviceClass ?? chart.yAxisMetadata.deviceClass,
                minimum: chart.yDomain.lowerBound,
                maximum: chart.yDomain.upperBound,
                fractionDigits: chart.yAxisMetadata.fractionDigits
            )
            let tooltip = ChartTooltipModel(
                timestamp: timestamp,
                screenPosition: position,
                item: .line(ChartTooltipModel.LineItem(
                    seriesID: item.id,
                    entityID: item.entityID,
                    seriesName: item.name,
                    value: value,
                    formattedValue: AxisLabelFormatter.format(value, metadata: metadata, locale: locale),
                    unit: metadata.unit,
                    source: point.source
                ))
            )

            if best == nil || distance < best!.distance {
                best = (tooltip, distance)
            }
        }

        return best?.tooltip
    }

    private static func sampleIfNeeded(
        _ series: LineSeries,
        maximumDetail: Double?,
        visibleRange: ChartVisibleRange
    ) -> LineSeries {
        var visibleSeries = series
        visibleSeries.points = visibleStepWindowPoints(
            series.points,
            visibleRange: visibleRange
        )

        guard let maximumDetail = maximumDetail,
              maximumDetail.isFinite,
              maximumDetail > 0,
              Double(visibleSeries.points.count) > maximumDetail else {
            return visibleSeries
        }

        let downsampled = DownSampler.downSample(
            visibleSeries.points,
            maxDetails: maximumDetail,
            minX: visibleRange.lowerBound,
            maxX: visibleRange.upperBound
        )
        visibleSeries.points = mergeRequiredStepPoints(
            source: visibleSeries.points,
            sampled: downsampled,
            requiredIndexes: requiredStepPointIndexes(
                in: visibleSeries.points,
                visibleRange: visibleRange
            )
        )
        return visibleSeries
    }

    private static func visibleStepWindowPoints(
        _ points: [LinePoint],
        visibleRange: ChartVisibleRange
    ) -> [LinePoint] {
        var result: [LinePoint] = []
        var lastFiniteBeforeLower: LinePoint?
        var hasFinitePointAtOrBeforeUpper = false

        for point in points where point.x.isFinite {
            if point.x < visibleRange.lowerBound {
                if let value = point.y, value.isFinite {
                    lastFiniteBeforeLower = point
                } else {
                    lastFiniteBeforeLower = nil
                }
                continue
            }

            if point.x <= visibleRange.upperBound {
                if result.isEmpty, let lastFiniteBeforeLower = lastFiniteBeforeLower {
                    result.append(lastFiniteBeforeLower)
                    hasFinitePointAtOrBeforeUpper = true
                }
                result.append(point)
                if let value = point.y, value.isFinite {
                    hasFinitePointAtOrBeforeUpper = true
                } else {
                    lastFiniteBeforeLower = nil
                }
                continue
            }

            if result.isEmpty, let lastFiniteBeforeLower = lastFiniteBeforeLower {
                result.append(lastFiniteBeforeLower)
                hasFinitePointAtOrBeforeUpper = true
            }

            if hasFinitePointAtOrBeforeUpper,
               let value = point.y,
               value.isFinite {
                result.append(point)
            }
            break
        }

        return result
    }

    private static func requiredStepPointIndexes(
        in points: [LinePoint],
        visibleRange: ChartVisibleRange
    ) -> Set<Int> {
        var required: Set<Int> = []
        var currentRun: [Int] = []

        func flushRun() {
            guard !currentRun.isEmpty else {
                return
            }
            required.insert(currentRun[0])
            required.insert(currentRun[currentRun.count - 1])
            currentRun.removeAll(keepingCapacity: true)
        }

        for index in points.indices {
            let point = points[index]
            if point.x.isFinite, let value = point.y, value.isFinite {
                currentRun.append(index)
            } else {
                flushRun()
                if point.x.isFinite, visibleRange.contains(point.x) {
                    required.insert(index)
                }
            }
        }
        flushRun()

        return required
    }

    private static func mergeRequiredStepPoints(
        source: [LinePoint],
        sampled: [LinePoint],
        requiredIndexes: Set<Int>
    ) -> [LinePoint] {
        var sampledCounts: [LinePointKey: Int] = [:]
        for point in sampled {
            sampledCounts[LinePointKey(point)] = (sampledCounts[LinePointKey(point)] ?? 0) + 1
        }

        var result: [LinePoint] = []
        result.reserveCapacity(sampled.count + requiredIndexes.count)
        for index in source.indices {
            let point = source[index]
            let key = LinePointKey(point)
            let sampledCount = sampledCounts[key] ?? 0
            if requiredIndexes.contains(index) || sampledCount > 0 {
                result.append(point)
                if sampledCount > 0 {
                    sampledCounts[key] = sampledCount - 1
                }
            }
        }
        return result
    }

    private static func prepareSeries(
        _ sampled: LineSeries,
        original: LineSeries,
        geometry: ChartGeometry,
        visibleRange: ChartVisibleRange
    ) -> PreparedLineSeries {
        guard let yScale = geometry.yScale else {
            return PreparedLineSeries(
                id: sampled.id,
                entityID: sampled.entityID,
                name: sampled.name,
                unit: sampled.unit,
                deviceClass: sampled.deviceClass,
                colorHex: sampled.colorHex,
                isFilled: sampled.isFilled,
                sourceRanges: sampled.sourceRanges,
                sourceSeries: original,
                segments: [],
                singlePoints: [],
                hitPoints: []
            )
        }

        var segments: [PreparedLineSegment] = []
        var singlePoints: [PreparedLinePoint] = []
        var currentRun: [LinePoint] = []

        func flushRun() {
            guard !currentRun.isEmpty else {
                return
            }

            if currentRun.count == 1 {
                let point = currentRun[0]
                if let prepared = preparedPoint(
                    timestamp: point.x,
                    value: point.y,
                    source: point.source,
                    geometry: geometry,
                    yScale: yScale,
                    visibleRange: visibleRange
                ) {
                    singlePoints.append(prepared)
                }
            } else {
                let vertices = stepVertices(
                    for: currentRun,
                    geometry: geometry,
                    yScale: yScale,
                    visibleRange: visibleRange
                )
                segments.append(contentsOf: styledSegments(
                    vertices,
                    sourceRanges: sampled.sourceRanges
                ))
            }
            currentRun.removeAll(keepingCapacity: true)
        }

        for point in sampled.points {
            if point.x.isFinite, let y = point.y, y.isFinite {
                currentRun.append(point)
            } else {
                flushRun()
            }
        }
        flushRun()

        let hitPoints = sampled.points.compactMap { point in
            preparedPoint(
                timestamp: point.x,
                value: point.y,
                source: point.source,
                geometry: geometry,
                yScale: yScale,
                visibleRange: visibleRange
            )
        }

        return PreparedLineSeries(
            id: sampled.id,
            entityID: sampled.entityID,
            name: sampled.name,
            unit: sampled.unit,
            deviceClass: sampled.deviceClass,
            colorHex: sampled.colorHex,
            isFilled: sampled.isFilled,
            sourceRanges: sampled.sourceRanges,
            sourceSeries: original,
            segments: segments,
            singlePoints: singlePoints,
            hitPoints: hitPoints
        )
    }

    private static func stepVertices(
        for run: [LinePoint],
        geometry: ChartGeometry,
        yScale: AxisScale,
        visibleRange: ChartVisibleRange
    ) -> [PreparedLinePoint] {
        var vertices: [PreparedLinePoint] = []

        func append(timestamp: Double, value: Double?, source: LinePointSource) {
            guard let point = preparedPoint(
                timestamp: timestamp,
                value: value,
                source: source,
                geometry: geometry,
                yScale: yScale,
                visibleRange: visibleRange
            ) else {
                return
            }

            if vertices.last == point {
                return
            }
            vertices.append(point)
        }

        for index in 0..<(run.count - 1) {
            let current = run[index]
            let next = run[index + 1]
            guard let currentY = current.y,
                  let nextY = next.y,
                  currentY.isFinite,
                  nextY.isFinite else {
                continue
            }

            let horizontalStart = max(current.x, visibleRange.lowerBound)
            let horizontalEnd = min(next.x, visibleRange.upperBound)
            if horizontalEnd >= horizontalStart,
               current.x <= visibleRange.upperBound,
               next.x >= visibleRange.lowerBound {
                append(timestamp: horizontalStart, value: currentY, source: current.source)
                append(timestamp: horizontalEnd, value: currentY, source: current.source)
            }

            if visibleRange.contains(next.x) {
                append(timestamp: next.x, value: nextY, source: next.source)
            }
        }

        return vertices
    }

    private static func preparedPoint(
        timestamp: Double,
        value: Double?,
        source: LinePointSource,
        geometry: ChartGeometry,
        yScale: AxisScale,
        visibleRange: ChartVisibleRange
    ) -> PreparedLinePoint? {
        guard timestamp.isFinite,
              visibleRange.contains(timestamp),
              let value = value,
              value.isFinite,
              let y = yScale.pixelIfValid(for: value) else {
            return nil
        }

        return PreparedLinePoint(
            timestamp: timestamp,
            value: value,
            source: source,
            position: CGPoint(
                x: geometry.xScale.pixel(for: timestamp),
                y: y
            )
        )
    }

    private static func styledSegments(
        _ vertices: [PreparedLinePoint],
        sourceRanges: [LineSeriesSourceRange]
    ) -> [PreparedLineSegment] {
        var result: [PreparedLineSegment] = []
        var currentStyle: LineSegmentStyle?
        var currentPoints: [PreparedLinePoint] = []

        func flush() {
            guard currentPoints.count >= 2, let currentStyle = currentStyle else {
                currentPoints.removeAll(keepingCapacity: true)
                return
            }
            result.append(PreparedLineSegment(
                source: currentStyle.source,
                alpha: currentStyle.alpha,
                points: currentPoints
            ))
            currentPoints.removeAll(keepingCapacity: true)
        }

        for vertex in vertices {
            let style = segmentStyle(
                timestamp: vertex.timestamp,
                source: vertex.source,
                sourceRanges: sourceRanges
            )
            if let existingStyle = currentStyle, existingStyle != style {
                let previous = currentPoints.last
                flush()
                if let previous = previous {
                    currentPoints = [previous, vertex]
                } else {
                    currentPoints = [vertex]
                }
                currentStyle = style
            } else {
                currentStyle = style
                currentPoints.append(vertex)
            }
        }
        flush()

        return result
    }

    private static func segmentStyle(
        timestamp: Double,
        source: LinePointSource,
        sourceRanges: [LineSeriesSourceRange]
    ) -> LineSegmentStyle {
        if let matchingSourceRange = sourceRanges.first(where: { range in
            range.source == source && rangeContains(range, timestamp: timestamp)
        }) {
            return LineSegmentStyle(
                source: matchingSourceRange.source,
                alpha: min(max(matchingSourceRange.alpha, 0), 1)
            )
        }

        if let sourceFallbackRange = sourceRanges.first(where: { $0.source == source }) {
            return LineSegmentStyle(
                source: sourceFallbackRange.source,
                alpha: min(max(sourceFallbackRange.alpha, 0), 1)
            )
        }

        for range in sourceRanges {
            if rangeContains(range, timestamp: timestamp) {
                return LineSegmentStyle(
                    source: range.source,
                    alpha: min(max(range.alpha, 0), 1)
                )
            }
        }

        return LineSegmentStyle(source: source, alpha: source == .statistics ? 0.5 : 1)
    }

    private static func rangeContains(_ range: LineSeriesSourceRange, timestamp: Double) -> Bool {
        let afterStart = range.startX.map { timestamp >= $0 } ?? true
        let beforeEnd = range.endX.map { timestamp <= $0 } ?? true
        return afterStart && beforeEnd
    }
}

private struct LineSegmentStyle: Equatable {
    var source: LinePointSource
    var alpha: Double
}

private struct LinePointKey: Hashable {
    var x: Double
    var y: Double?
    var source: String

    init(_ point: LinePoint) {
        x = point.x
        y = point.y
        source = point.source.rawValue
    }
}

struct LineHistoryChartView: View {
    var series: [LineSeries]
    var yAxisMetadata: YAxisMetadata
    var initialVisibleRange: ChartVisibleRange?
    var fixedMinimumY: Double?
    var fixedMaximumY: Double?
    var fitYData: Bool
    var logarithmicScale: Bool
    var theme: ChartTheme
    var minimumHeight: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var interaction: ChartInteractionState?
    @State private var dragStartRange: ChartVisibleRange?
    @State private var zoomStartRange: ChartVisibleRange?
    @State private var lastTap: ChartInteractionTap?
    @State private var tooltip: ChartTooltipModel?

    init(
        series: [LineSeries],
        yAxisMetadata: YAxisMetadata = YAxisMetadata(),
        initialVisibleRange: ChartVisibleRange? = nil,
        fixedMinimumY: Double? = nil,
        fixedMaximumY: Double? = nil,
        fitYData: Bool = false,
        logarithmicScale: Bool = false,
        theme: ChartTheme = .default,
        minimumHeight: CGFloat = 200
    ) {
        self.series = series
        self.yAxisMetadata = yAxisMetadata
        self.initialVisibleRange = initialVisibleRange
        self.fixedMinimumY = fixedMinimumY
        self.fixedMaximumY = fixedMaximumY
        self.fitYData = fitYData
        self.logarithmicScale = logarithmicScale
        self.theme = theme
        self.minimumHeight = minimumHeight
    }

    var body: some View {
        GeometryReader { proxy in
            let dataBounds = initialVisibleRange ?? LineChartRenderer.dataRange(in: series)
            let currentInteraction = (interaction ?? ChartInteractionState(
                dataBounds: dataBounds,
                visibleRange: initialVisibleRange
            )).replacingDataBounds(dataBounds)
            let prepared = LineChartRenderer.prepare(
                series: series,
                visibleRange: currentInteraction.visibleRange,
                size: proxy.size,
                yAxisMetadata: yAxisMetadata,
                fixedMinimumY: fixedMinimumY,
                fixedMaximumY: fixedMaximumY,
                fitYData: fitYData,
                logarithmicScale: logarithmicScale,
                theme: theme,
                maximumDetail: max(1, Double(proxy.size.width * displayScale))
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
        }
        .frame(minHeight: minimumHeight)
    }

    private func dragGesture(
        prepared: PreparedLineChart,
        dataBounds: ChartVisibleRange
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var state = (interaction ?? ChartInteractionState(
                    dataBounds: dataBounds,
                    visibleRange: initialVisibleRange
                )).replacingDataBounds(dataBounds)

                if dragStartRange == nil, !ChartInteractionTap.isTapMovement(value.translation) {
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
                tooltip = LineChartRenderer.nearestTooltip(
                    in: prepared,
                    timestamp: prepared.geometry.xScale.value(for: value.location.x),
                    screenLocation: value.location
                )
            }
            .onEnded { value in
                if ChartInteractionTap.isTapMovement(value.translation) {
                    handleTap(
                        location: value.location,
                        time: value.time,
                        prepared: prepared,
                        dataBounds: dataBounds
                    )
                }
                dragStartRange = nil
            }
    }

    private func handleTap(
        location: CGPoint,
        time: Date,
        prepared: PreparedLineChart,
        dataBounds: ChartVisibleRange
    ) {
        let tap = ChartInteractionTap(time: time, location: location)
        guard lastTap?.isDoubleTap(with: tap) == true else {
            lastTap = tap
            return
        }

        var state = (interaction ?? ChartInteractionState(
            dataBounds: dataBounds,
            visibleRange: initialVisibleRange
        )).replacingDataBounds(dataBounds)
        let anchor = prepared.geometry.xScale.value(for: location.x)
        state.toggleThirtyPercentZoom(anchorTimestamp: anchor)
        interaction = state
        tooltip = nil
        lastTap = nil
    }

    private func zoomGesture(dataBounds: ChartVisibleRange) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                var state = (interaction ?? ChartInteractionState(
                    dataBounds: dataBounds,
                    visibleRange: initialVisibleRange
                )).replacingDataBounds(dataBounds)
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

    private func draw(_ chart: PreparedLineChart, in context: inout GraphicsContext) {
        drawAxes(chart, in: &context)

        var plotContext = context
        plotContext.clip(to: Path(chart.geometry.plotRect))

        for item in chart.series {
            let color = theme.color(hex: item.colorHex)
            for segment in item.segments {
                var path = Path()
                guard let first = segment.points.first else {
                    continue
                }
                path.move(to: first.position)
                for point in segment.points.dropFirst() {
                    path.addLine(to: point.position)
                }

                if item.isFilled {
                    var fillPath = path
                    fillPath.addLine(to: CGPoint(
                        x: segment.points.last?.position.x ?? first.position.x,
                        y: chart.geometry.plotRect.maxY
                    ))
                    fillPath.addLine(to: CGPoint(x: first.position.x, y: chart.geometry.plotRect.maxY))
                    fillPath.closeSubpath()
                    plotContext.fill(fillPath, with: .color(color.opacity(0.16 * segment.alpha)))
                }

                plotContext.stroke(
                    path,
                    with: .color(color.opacity(segment.alpha)),
                    lineWidth: theme.lineWidth
                )
            }

            for point in item.singlePoints {
                let rect = CGRect(
                    x: point.position.x - theme.pointRadius,
                    y: point.position.y - theme.pointRadius,
                    width: theme.pointRadius * 2,
                    height: theme.pointRadius * 2
                )
                plotContext.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }

    private func drawAxes(_ chart: PreparedLineChart, in context: inout GraphicsContext) {
        let plotRect = chart.geometry.plotRect
        let gridPath = Path { path in
            let tickCount = 4
            for index in 0...tickCount {
                let ratio = CGFloat(index) / CGFloat(tickCount)
                let x = plotRect.minX + plotRect.width * ratio
                path.move(to: CGPoint(x: x, y: plotRect.minY))
                path.addLine(to: CGPoint(x: x, y: plotRect.maxY))

                let y = plotRect.minY + plotRect.height * ratio
                path.move(to: CGPoint(x: plotRect.minX, y: y))
                path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            }
        }
        context.stroke(gridPath, with: .color(theme.gridColor), lineWidth: theme.gridLineWidth)

        let axisPath = Path { path in
            path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
            path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
            path.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        }
        context.stroke(axisPath, with: .color(theme.axisColor), lineWidth: theme.gridLineWidth)

        drawAxisLabels(chart, in: &context)
    }

    private func drawAxisLabels(_ chart: PreparedLineChart, in context: inout GraphicsContext) {
        let plotRect = chart.geometry.plotRect
        let tickCount = 4

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

        guard let yScale = chart.geometry.yScale else {
            return
        }

        for index in 0...tickCount {
            let ratio = Double(index) / Double(tickCount)
            let y = plotRect.maxY - plotRect.height * CGFloat(ratio)
            let value = yScale.value(for: y)
            let label = HANumberFormatting.format(
                value,
                maximumFractionDigits: chart.yAxisMetadata.fractionDigits
            )
            context.draw(
                Text(label).font(.caption2).foregroundColor(theme.labelColor),
                at: CGPoint(x: plotRect.minX - 6, y: y),
                anchor: .trailing
            )
        }
    }

    private func tooltipPosition(for tooltip: ChartTooltipModel, in size: CGSize) -> CGPoint {
        let x = min(max(tooltip.screenPosition.x + theme.tooltipGap, 60), max(60, size.width - 80))
        let y = min(max(tooltip.screenPosition.y - theme.tooltipGap, 24), max(24, size.height - 24))
        return CGPoint(x: x, y: y)
    }
}
