import Foundation

public struct DownSamplePoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum DownSamplingMode: Equatable {
    case minMax
    case mean
}

public enum DownSampler {
    public static func downSample(
        _ data: [DownSamplePoint]?,
        maxDetails: Double,
        minX: Double? = nil,
        maxX: Double? = nil,
        mode: DownSamplingMode = .minMax
    ) -> [DownSamplePoint] {
        guard let data = data else {
            return []
        }
        return downSampleValues(
            data,
            maxDetails: maxDetails,
            minX: minX,
            maxX: maxX,
            mode: mode,
            read: { point in
                guard point.x.isFinite, point.y.isFinite else {
                    return nil
                }
                return (point.x, point.y)
            },
            makeMean: { x, y in
                DownSamplePoint(x: x, y: y)
            }
        )
    }

    public static func downSample(
        _ data: [LinePoint],
        maxDetails: Double,
        minX: Double? = nil,
        maxX: Double? = nil,
        mode: DownSamplingMode = .minMax
    ) -> [LinePoint] {
        if Double(data.count) <= maxDetails {
            return data
        }

        var result: [LinePoint] = []
        var finiteRun: [LinePoint] = []

        func flushFiniteRun() {
            guard !finiteRun.isEmpty else {
                return
            }

            result.append(contentsOf: downSampleValues(
                finiteRun,
                maxDetails: maxDetails,
                minX: minX,
                maxX: maxX,
                mode: mode,
                read: { point in
                    guard point.x.isFinite, let y = point.y, y.isFinite else {
                        return nil
                    }
                    return (point.x, y)
                },
                makeMean: { x, y in
                    LinePoint(x: x, y: y, source: .generated)
                }
            ))
            finiteRun.removeAll(keepingCapacity: true)
        }

        for point in data {
            if point.x.isFinite, let y = point.y, y.isFinite {
                finiteRun.append(point)
            } else {
                flushFiniteRun()
                result.append(point)
            }
        }

        flushFiniteRun()
        return result
    }

    public static func downSample(
        _ series: LineSeries,
        maxDetails: Double,
        minX: Double? = nil,
        maxX: Double? = nil,
        mode: DownSamplingMode = .minMax
    ) -> LineSeries {
        var sampled = series
        sampled.points = downSample(
            series.points,
            maxDetails: maxDetails,
            minX: minX,
            maxX: maxX,
            mode: mode
        )
        return sampled
    }

    private static func downSampleValues<T>(
        _ data: [T],
        maxDetails: Double,
        minX: Double?,
        maxX: Double?,
        mode: DownSamplingMode,
        read: (T) -> (x: Double, y: Double)?,
        makeMean: (Double, Double) -> T
    ) -> [T] {
        if Double(data.count) <= maxDetails {
            return data
        }

        let detailCount = floor(maxDetails)
        guard detailCount > 0, detailCount.isFinite else {
            return []
        }

        let firstX = firstFiniteX(in: data, read: read)
        let lastX = lastFiniteX(in: data, read: read)
        guard let resolvedMin = minX ?? firstX,
              let resolvedMax = maxX ?? lastX,
              resolvedMin.isFinite,
              resolvedMax.isFinite else {
            return []
        }

        var step = ceil((resolvedMax - resolvedMin) / detailCount)
        if !step.isFinite || step <= 0 {
            step = 1
        }

        switch mode {
        case .mean:
            return downSampleMean(
                data,
                minX: resolvedMin,
                step: step,
                read: read,
                makeMean: makeMean
            )
        case .minMax:
            return downSampleMinMax(
                data,
                minX: resolvedMin,
                step: step,
                read: read
            )
        }
    }

    private static func firstFiniteX<T>(
        in data: [T],
        read: (T) -> (x: Double, y: Double)?
    ) -> Double? {
        for point in data {
            if let x = read(point)?.x, x.isFinite {
                return x
            }
        }
        return nil
    }

    private static func lastFiniteX<T>(
        in data: [T],
        read: (T) -> (x: Double, y: Double)?
    ) -> Double? {
        for point in data.reversed() {
            if let x = read(point)?.x, x.isFinite {
                return x
            }
        }
        return nil
    }

    private static func frameIndex(x: Double, minX: Double, step: Double) -> Int? {
        let rawIndex = floor((x - minX) / step)
        guard rawIndex.isFinite else {
            return nil
        }
        return Int(rawIndex)
    }

    private static func downSampleMean<T>(
        _ data: [T],
        minX: Double,
        step: Double,
        read: (T) -> (x: Double, y: Double)?,
        makeMean: (Double, Double) -> T
    ) -> [T] {
        var frames: [Int: MeanFrame] = [:]
        var order: [Int] = []

        for point in data {
            guard let value = read(point),
                  let index = frameIndex(x: value.x, minX: minX, step: step) else {
                continue
            }

            if var frame = frames[index] {
                frame.sumX += value.x
                frame.sumY += value.y
                frame.count += 1
                frames[index] = frame
            } else {
                frames[index] = MeanFrame(sumX: value.x, sumY: value.y, count: 1)
                order.append(index)
            }
        }

        var result: [T] = []
        result.reserveCapacity(order.count)
        for index in order {
            guard let frame = frames[index], frame.count > 0 else {
                continue
            }
            let count = Double(frame.count)
            result.append(makeMean(frame.sumX / count, frame.sumY / count))
        }
        return result
    }

    private static func downSampleMinMax<T>(
        _ data: [T],
        minX: Double,
        step: Double,
        read: (T) -> (x: Double, y: Double)?
    ) -> [T] {
        var frames: [Int: MinMaxFrame<T>] = [:]
        var order: [Int] = []

        for point in data {
            guard let value = read(point),
                  let index = frameIndex(x: value.x, minX: minX, step: step) else {
                continue
            }

            if var frame = frames[index] {
                if value.y < frame.minY {
                    frame.minPoint = point
                    frame.minX = value.x
                    frame.minY = value.y
                }
                if value.y > frame.maxY {
                    frame.maxPoint = point
                    frame.maxX = value.x
                    frame.maxY = value.y
                }
                frames[index] = frame
            } else {
                frames[index] = MinMaxFrame(
                    minPoint: point,
                    minX: value.x,
                    minY: value.y,
                    maxPoint: point,
                    maxX: value.x,
                    maxY: value.y
                )
                order.append(index)
            }
        }

        var result: [T] = []
        result.reserveCapacity(order.count * 2)
        for index in order {
            guard let frame = frames[index] else {
                continue
            }
            if frame.minX > frame.maxX {
                result.append(frame.maxPoint)
            }
            result.append(frame.minPoint)
            if frame.minX < frame.maxX {
                result.append(frame.maxPoint)
            }
        }
        return result
    }
}

private struct MeanFrame {
    var sumX: Double
    var sumY: Double
    var count: Int
}

private struct MinMaxFrame<T> {
    var minPoint: T
    var minX: Double
    var minY: Double
    var maxPoint: T
    var maxX: Double
    var maxY: Double
}
