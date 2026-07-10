import CoreGraphics
import Foundation

struct ChartInteractionState: Equatable {
    var dataBounds: ChartVisibleRange
    var visibleRange: ChartVisibleRange
    var minimumSpan: Double

    init(
        dataBounds: ChartVisibleRange,
        visibleRange: ChartVisibleRange? = nil,
        minimumSpan: Double = ChartVisibleRange.defaultMinimumSpan
    ) {
        self.dataBounds = dataBounds
        self.minimumSpan = minimumSpan.isFinite && minimumSpan > 0
            ? minimumSpan
            : ChartVisibleRange.defaultMinimumSpan
        self.visibleRange = (visibleRange ?? dataBounds).clamped(to: dataBounds)
    }

    var isZoomed: Bool {
        abs(visibleRange.lowerBound - dataBounds.lowerBound) > 0.001 ||
            abs(visibleRange.upperBound - dataBounds.upperBound) > 0.001
    }

    var percentageRange: (start: Double, end: Double) {
        guard dataBounds.span > 0 else {
            return (0, 100)
        }

        let start = ((visibleRange.lowerBound - dataBounds.lowerBound) / dataBounds.span) * 100
        let end = ((visibleRange.upperBound - dataBounds.lowerBound) / dataBounds.span) * 100
        return (
            min(max(start, 0), 100),
            min(max(end, 0), 100)
        )
    }

    mutating func setPercentageRange(start: Double, end: Double) {
        guard dataBounds.span > 0, start.isFinite, end.isFinite else {
            reset()
            return
        }

        let lowerPercent = min(start, end) / 100
        let upperPercent = max(start, end) / 100
        visibleRange = ChartVisibleRange(
            dataBounds.lowerBound + dataBounds.span * lowerPercent,
            dataBounds.lowerBound + dataBounds.span * upperPercent,
            minimumSpan: minimumSpan
        ).clamped(to: dataBounds)
    }

    mutating func pan(pixelDelta: CGFloat, plotWidth: CGFloat) {
        guard plotWidth > 0, pixelDelta.isFinite else {
            return
        }

        let timeDelta = -Double(pixelDelta / plotWidth) * visibleRange.span
        visibleRange = visibleRange.shifted(by: timeDelta, clampedTo: dataBounds)
    }

    mutating func zoom(magnification: Double, anchorTimestamp: Double? = nil) {
        visibleRange = visibleRange.zoomed(
            magnification: magnification,
            anchor: anchorTimestamp,
            minimumSpan: minimumSpan,
            clampedTo: dataBounds
        )
    }

    mutating func toggleThirtyPercentZoom(anchorTimestamp: Double? = nil) {
        if isZoomed {
            reset()
            return
        }

        let targetSpan = max(dataBounds.span * 0.30, minimumSpan)
        let anchor = anchorTimestamp.map {
            min(max($0, dataBounds.lowerBound), dataBounds.upperBound)
        } ?? dataBounds.midpoint
        visibleRange = ChartVisibleRange(
            anchor - targetSpan / 2,
            anchor + targetSpan / 2,
            minimumSpan: minimumSpan
        ).clamped(to: dataBounds)
    }

    mutating func reset() {
        visibleRange = dataBounds
    }
}
