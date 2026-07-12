import CoreGraphics
import Foundation

struct ChartEdgeInsets: Equatable, Hashable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

struct ChartGeometry: Equatable {
    var size: CGSize
    var plotRect: CGRect
    var xScale: AxisScale
    var yScale: AxisScale?

    static func line(
        size: CGSize,
        visibleRange: ChartVisibleRange,
        yDomain: ChartValueRange,
        insets: ChartEdgeInsets,
        yScaleKind: AxisScaleKind = .linear
    ) -> ChartGeometry {
        let plotRect = ChartGeometryCalculator.plotRect(size: size, insets: insets)
        return ChartGeometry(
            size: size,
            plotRect: plotRect,
            xScale: AxisScale.xScale(visibleRange: visibleRange, plotRect: plotRect),
            yScale: AxisScale.yScale(domain: yDomain, plotRect: plotRect, kind: yScaleKind)
        )
    }

    static func timeline(
        size: CGSize,
        visibleRange: ChartVisibleRange,
        insets: ChartEdgeInsets
    ) -> ChartGeometry {
        let plotRect = ChartGeometryCalculator.plotRect(size: size, insets: insets)
        return ChartGeometry(
            size: size,
            plotRect: plotRect,
            xScale: AxisScale.xScale(visibleRange: visibleRange, plotRect: plotRect),
            yScale: nil
        )
    }
}

enum ChartGeometryCalculator {
    static func plotRect(size: CGSize, insets: ChartEdgeInsets) -> CGRect {
        let width = max(1, size.width - insets.leading - insets.trailing)
        let height = max(1, size.height - insets.top - insets.bottom)
        return CGRect(
            x: max(0, insets.leading),
            y: max(0, insets.top),
            width: width,
            height: height
        )
    }

    static func clampedVisibleRange(
        _ visibleRange: ChartVisibleRange,
        to dataRange: ChartVisibleRange
    ) -> ChartVisibleRange {
        visibleRange.clamped(to: dataRange)
    }

    static func timelineRowRect(
        plotRect: CGRect,
        rowIndex: Int,
        rowCount: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> CGRect {
        guard rowCount > 0,
              rowIndex >= 0,
              rowIndex < rowCount,
              plotRect.width > 0,
              plotRect.height > 0 else {
            return .zero
        }

        let desiredTotalHeight =
            CGFloat(rowCount) * rowHeight + CGFloat(max(0, rowCount - 1)) * rowSpacing
        if desiredTotalHeight <= plotRect.height {
            let originY = plotRect.minY + (plotRect.height - desiredTotalHeight) / 2
            return CGRect(
                x: plotRect.minX,
                y: originY + CGFloat(rowIndex) * (rowHeight + rowSpacing),
                width: plotRect.width,
                height: rowHeight
            )
        }

        let slotHeight = plotRect.height / CGFloat(rowCount)
        let resolvedHeight = max(1, min(rowHeight, slotHeight * 0.82))
        return CGRect(
            x: plotRect.minX,
            y: plotRect.minY + CGFloat(rowIndex) * slotHeight + (slotHeight - resolvedHeight) / 2,
            width: plotRect.width,
            height: resolvedHeight
        )
    }
}
