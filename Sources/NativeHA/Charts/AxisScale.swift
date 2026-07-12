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
        lowerBound + (upperBound - lowerBound) / 2
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
    static let logarithmicMinimum = Double.ulpOfOne

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

    func clampedForLogarithmicScale() -> ChartValueRange {
        let lower = max(lowerBound, Self.logarithmicMinimum)
        let upper = max(upperBound, lower * 10)
        return ChartValueRange(lower, upper).expandedIfFlat()
    }

    static func finiteOrDefault(minimum: Double?, maximum: Double?) -> ChartValueRange {
        let finiteMinimum = minimum.flatMap { $0.isFinite ? $0 : nil }
        let finiteMaximum = maximum.flatMap { $0.isFinite ? $0 : nil }

        switch (finiteMinimum, finiteMaximum) {
        case let (.some(minimum), .some(maximum)):
            return ChartValueRange(minimum, maximum).expandedIfFlat()
        case let (.some(minimum), .none):
            return ChartValueRange(minimum, minimum + 1).expandedIfFlat()
        case let (.none, .some(maximum)):
            return ChartValueRange(maximum - 1, maximum).expandedIfFlat()
        case (.none, .none):
            return ChartValueRange(0, 1)
        }
    }
}

enum AxisScaleKind: Equatable {
    case linear
    case logarithmic
}

struct AxisScale: Equatable {
    var domain: ChartValueRange
    var pixelLowerBound: CGFloat
    var pixelUpperBound: CGFloat
    var kind: AxisScaleKind

    init(domain: ChartValueRange, pixels: ClosedRange<CGFloat>) {
        self.init(
            domain: domain,
            pixelLowerBound: pixels.lowerBound,
            pixelUpperBound: pixels.upperBound
        )
    }

    init(
        domain: ChartValueRange,
        pixelLowerBound: CGFloat,
        pixelUpperBound: CGFloat,
        kind: AxisScaleKind = .linear
    ) {
        self.kind = kind
        self.domain = kind == .logarithmic
            ? domain.clampedForLogarithmicScale()
            : domain.expandedIfFlat()
        self.pixelLowerBound = pixelLowerBound.isFinite ? pixelLowerBound : 0
        self.pixelUpperBound = pixelUpperBound.isFinite ? pixelUpperBound : self.pixelLowerBound
    }

    func pixel(for value: Double) -> CGFloat {
        pixelIfValid(for: value) ?? pixelLowerBound
    }

    func pixelIfValid(for value: Double) -> CGFloat? {
        guard value.isFinite, domain.span > 0 else {
            return nil
        }

        let ratio: Double
        switch kind {
        case .linear:
            ratio = (value - domain.lowerBound) / domain.span
        case .logarithmic:
            guard value > 0 else {
                return nil
            }
            let lower = log10(domain.lowerBound)
            let upper = log10(domain.upperBound)
            guard upper > lower else {
                return nil
            }
            ratio = (log10(value) - lower) / (upper - lower)
        }

        guard ratio.isFinite else {
            return nil
        }
        return pixelLowerBound + CGFloat(ratio) * (pixelUpperBound - pixelLowerBound)
    }

    func value(for pixel: CGFloat) -> Double {
        let pixelSpan = pixelUpperBound - pixelLowerBound
        guard pixelSpan != 0, pixel.isFinite else {
            return domain.lowerBound
        }

        let ratio = Double((pixel - pixelLowerBound) / pixelSpan)
        switch kind {
        case .linear:
            return domain.lowerBound + ratio * domain.span
        case .logarithmic:
            let lower = log10(domain.lowerBound)
            let upper = log10(domain.upperBound)
            guard upper > lower else {
                return domain.lowerBound
            }
            return pow(10, lower + ratio * (upper - lower))
        }
    }

    static func xScale(visibleRange: ChartVisibleRange, plotRect: CGRect) -> AxisScale {
        AxisScale(
            domain: ChartValueRange(visibleRange.lowerBound, visibleRange.upperBound),
            pixels: plotRect.minX...plotRect.maxX
        )
    }

    static func yScale(
        domain: ChartValueRange,
        plotRect: CGRect,
        kind: AxisScaleKind = .linear
    ) -> AxisScale {
        AxisScale(
            domain: domain,
            pixelLowerBound: plotRect.maxY,
            pixelUpperBound: plotRect.minY,
            kind: kind
        )
    }

    static func lineYDomain(
        in series: [LineSeries],
        visibleRange: ChartVisibleRange,
        fixedMinimum: Double? = nil,
        fixedMaximum: Double? = nil,
        fitYData: Bool = false,
        scaleKind: AxisScaleKind = .linear
    ) -> ChartValueRange {
        var observedMinimum: Double?
        var observedMaximum: Double?

        func observe(_ value: Double?) {
            guard let value = value, value.isFinite else {
                return
            }
            if scaleKind == .logarithmic, value <= 0 {
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

        let minimum = resolvedMinimum(
            fixed: fixedMinimum,
            observed: observedMinimum,
            fitYData: fitYData
        )
        let maximum = resolvedMaximum(
            fixed: fixedMaximum,
            observed: observedMaximum,
            fitYData: fitYData
        )
        let range = ChartValueRange.finiteOrDefault(minimum: minimum, maximum: maximum)
        return scaleKind == .logarithmic ? range.clampedForLogarithmicScale() : range
    }

    private static func resolvedMinimum(
        fixed: Double?,
        observed: Double?,
        fitYData: Bool
    ) -> Double? {
        guard let fixed = fixed, fixed.isFinite else {
            return observed
        }
        guard fitYData, let observed = observed, observed.isFinite else {
            return fixed
        }
        return min(roundedYAxis(observed, rounding: floor), fixed)
    }

    private static func resolvedMaximum(
        fixed: Double?,
        observed: Double?,
        fitYData: Bool
    ) -> Double? {
        guard let fixed = fixed, fixed.isFinite else {
            return observed
        }
        guard fitYData, let observed = observed, observed.isFinite else {
            return fixed
        }
        return max(roundedYAxis(observed, rounding: ceil), fixed)
    }

    private static func roundedYAxis(
        _ value: Double,
        rounding: (Double) -> Double
    ) -> Double {
        abs(value) < 1 ? value : rounding(value)
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
