import CoreGraphics
import Foundation
import NativeHACore

struct ChartVisibleRange: Equatable, Hashable {
    static let defaultMinimumSpan: Double = 1

    var lowerBound: Double
    var upperBound: Double

    init(
        _ lowerBound: Double,
        _ upperBound: Double,
        minimumSpan: Double = ChartVisibleRange.defaultMinimumSpan
    ) {
        let resolvedMinimumSpan = minimumSpan.isFinite && minimumSpan > 0
            ? minimumSpan
            : ChartVisibleRange.defaultMinimumSpan

        guard lowerBound.isFinite, upperBound.isFinite else {
            self.lowerBound = 0
            self.upperBound = resolvedMinimumSpan
            return
        }

        let lower = min(lowerBound, upperBound)
        let upper = max(lowerBound, upperBound)
        if upper - lower >= resolvedMinimumSpan {
            self.lowerBound = lower
            self.upperBound = upper
        } else {
            let center = (lower + upper) / 2
            self.lowerBound = center - resolvedMinimumSpan / 2
            self.upperBound = center + resolvedMinimumSpan / 2
        }
    }

    var span: Double {
        upperBound - lowerBound
    }

    var midpoint: Double {
        lowerBound + span / 2
    }

    func contains(_ value: Double) -> Bool {
        value >= lowerBound && value <= upperBound
    }

    func shifted(by delta: Double, clampedTo bounds: ChartVisibleRange? = nil) -> ChartVisibleRange {
        let shifted = ChartVisibleRange(lowerBound + delta, upperBound + delta, minimumSpan: span)
        guard let bounds = bounds else {
            return shifted
        }
        return shifted.clamped(to: bounds)
    }

    func zoomed(
        magnification: Double,
        anchor: Double? = nil,
        minimumSpan: Double = ChartVisibleRange.defaultMinimumSpan,
        clampedTo bounds: ChartVisibleRange? = nil
    ) -> ChartVisibleRange {
        guard magnification.isFinite, magnification > 0 else {
            return self
        }

        let resolvedAnchor = anchor.map { min(max($0, lowerBound), upperBound) } ?? midpoint
        let nextSpan = max(span / magnification, minimumSpan)
        let anchorRatio = span > 0 ? (resolvedAnchor - lowerBound) / span : 0.5
        let nextLower = resolvedAnchor - nextSpan * anchorRatio
        let nextUpper = nextLower + nextSpan
        let next = ChartVisibleRange(nextLower, nextUpper, minimumSpan: minimumSpan)
        guard let bounds = bounds else {
            return next
        }
        return next.clamped(to: bounds)
    }

    func clamped(to bounds: ChartVisibleRange) -> ChartVisibleRange {
        if span >= bounds.span {
            return bounds
        }

        var lower = lowerBound
        var upper = upperBound
        if lower < bounds.lowerBound {
            upper += bounds.lowerBound - lower
            lower = bounds.lowerBound
        }
        if upper > bounds.upperBound {
            lower -= upper - bounds.upperBound
            upper = bounds.upperBound
        }
        return ChartVisibleRange(lower, upper, minimumSpan: span)
    }
}

struct ChartValueRange: Equatable, Hashable {
    var lowerBound: Double
    var upperBound: Double

    init(_ lowerBound: Double, _ upperBound: Double) {
        guard lowerBound.isFinite, upperBound.isFinite else {
            self.lowerBound = 0
            self.upperBound = 1
            return
        }

        self.lowerBound = min(lowerBound, upperBound)
        self.upperBound = max(lowerBound, upperBound)
    }

    var span: Double {
        upperBound - lowerBound
    }

    func expandedIfFlat() -> ChartValueRange {
        guard span > 0 else {
            let padding = max(abs(lowerBound) * 0.05, 1)
            return ChartValueRange(lowerBound - padding, upperBound + padding)
        }
        return self
    }

    static func finiteOrDefault(minimum: Double?, maximum: Double?) -> ChartValueRange {
        guard let minimum = minimum,
              let maximum = maximum,
              minimum.isFinite,
              maximum.isFinite else {
            return ChartValueRange(0, 1)
        }
        return ChartValueRange(minimum, maximum).expandedIfFlat()
    }
}

struct AxisScale: Equatable {
    var domain: ChartValueRange
    var pixelLowerBound: CGFloat
    var pixelUpperBound: CGFloat

    init(domain: ChartValueRange, pixels: ClosedRange<CGFloat>) {
        self.init(
            domain: domain,
            pixelLowerBound: pixels.lowerBound,
            pixelUpperBound: pixels.upperBound
        )
    }

    init(domain: ChartValueRange, pixelLowerBound: CGFloat, pixelUpperBound: CGFloat) {
        self.domain = domain.expandedIfFlat()
        self.pixelLowerBound = pixelLowerBound
        self.pixelUpperBound = pixelUpperBound
    }

    func pixel(for value: Double) -> CGFloat {
        guard value.isFinite, domain.span > 0 else {
            return pixelLowerBound
        }

        let ratio = (value - domain.lowerBound) / domain.span
        return pixelLowerBound + CGFloat(ratio) * (pixelUpperBound - pixelLowerBound)
    }

    func value(for pixel: CGFloat) -> Double {
        let pixelSpan = pixelUpperBound - pixelLowerBound
        guard pixelSpan != 0, pixel.isFinite else {
            return domain.lowerBound
        }

        let ratio = Double((pixel - pixelLowerBound) / pixelSpan)
        return domain.lowerBound + ratio * domain.span
    }

    static func xScale(visibleRange: ChartVisibleRange, plotRect: CGRect) -> AxisScale {
        AxisScale(
            domain: ChartValueRange(visibleRange.lowerBound, visibleRange.upperBound),
            pixels: plotRect.minX...plotRect.maxX
        )
    }

    static func yScale(domain: ChartValueRange, plotRect: CGRect) -> AxisScale {
        AxisScale(
            domain: domain,
            pixelLowerBound: plotRect.maxY,
            pixelUpperBound: plotRect.minY
        )
    }

    static func lineYDomain(
        in series: [LineSeries],
        visibleRange: ChartVisibleRange,
        fixedMinimum: Double? = nil,
        fixedMaximum: Double? = nil
    ) -> ChartValueRange {
        var observedMinimum: Double?
        var observedMaximum: Double?

        func observe(_ value: Double?) {
            guard let value = value, value.isFinite else {
                return
            }
            observedMinimum = observedMinimum.map { min($0, value) } ?? value
            observedMaximum = observedMaximum.map { max($0, value) } ?? value
        }

        for item in series {
            observeVisibleStepValues(
                item.points,
                visibleRange: visibleRange,
                observe: observe
            )
        }

        let minimum = fixedMinimum.flatMap { $0.isFinite ? $0 : nil } ?? observedMinimum
        let maximum = fixedMaximum.flatMap { $0.isFinite ? $0 : nil } ?? observedMaximum
        return ChartValueRange.finiteOrDefault(minimum: minimum, maximum: maximum)
    }

    private static func observeVisibleStepValues(
        _ points: [LinePoint],
        visibleRange: ChartVisibleRange,
        observe: (Double?) -> Void
    ) {
        var previousFinite: LinePoint?

        for point in points where point.x.isFinite {
            if let previous = previousFinite,
               intervalsOverlap(
                   previous.x,
                   point.x,
                   visibleRange.lowerBound,
                   visibleRange.upperBound
               ) {
                observe(previous.y)
            }

            if visibleRange.contains(point.x) {
                observe(point.y)
            }

            if let value = point.y, value.isFinite {
                previousFinite = point
            } else {
                previousFinite = nil
            }
        }

        if let previousFinite = previousFinite,
           previousFinite.x <= visibleRange.upperBound {
            observe(previousFinite.y)
        }
    }

    private static func intervalsOverlap(
        _ firstLower: Double,
        _ firstUpper: Double,
        _ secondLower: Double,
        _ secondUpper: Double
    ) -> Bool {
        min(firstUpper, secondUpper) >= max(firstLower, secondLower)
    }
}
