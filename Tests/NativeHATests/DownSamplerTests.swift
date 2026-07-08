import XCTest
@testable import NativeHACore

final class DownSamplerTests: XCTestCase {
    func testReturnsEmptyArrayForNilData() {
        XCTAssertEqual(DownSampler.downSample(nil, maxDetails: 100), [])
    }

    func testReturnsOriginalDataWhenBelowMaxDetails() {
        let points = generatePoints(seed: 1, count: 50)
        XCTAssertEqual(DownSampler.downSample(points, maxDetails: 100), points)
    }

    func testMinMaxModeBucketsByXAxisAndPreservesChronologicalExtremes() {
        let points = [
            DownSamplePoint(x: 0, y: 5),
            DownSamplePoint(x: 1, y: 2),
            DownSamplePoint(x: 2, y: 8),
            DownSamplePoint(x: 3, y: 1),
            DownSamplePoint(x: 4, y: 7),
            DownSamplePoint(x: 5, y: 4),
            DownSamplePoint(x: 6, y: 6),
            DownSamplePoint(x: 7, y: 3),
            DownSamplePoint(x: 8, y: 9),
            DownSamplePoint(x: 9, y: 0)
        ]

        XCTAssertEqual(
            DownSampler.downSample(points, maxDetails: 3),
            [
                DownSamplePoint(x: 1, y: 2),
                DownSamplePoint(x: 2, y: 8),
                DownSamplePoint(x: 3, y: 1),
                DownSamplePoint(x: 4, y: 7),
                DownSamplePoint(x: 7, y: 3),
                DownSamplePoint(x: 8, y: 9),
                DownSamplePoint(x: 9, y: 0)
            ]
        )
    }

    func testMinMaxModeKeepsFirstOccurrenceOnTies() {
        let points = [
            DownSamplePoint(x: 0, y: 5),
            DownSamplePoint(x: 1, y: 5),
            DownSamplePoint(x: 2, y: 4),
            DownSamplePoint(x: 3, y: 4),
            DownSamplePoint(x: 4, y: 6),
            DownSamplePoint(x: 5, y: 6)
        ]

        XCTAssertEqual(
            DownSampler.downSample(points, maxDetails: 2),
            [
                DownSamplePoint(x: 0, y: 5),
                DownSamplePoint(x: 2, y: 4),
                DownSamplePoint(x: 3, y: 4),
                DownSamplePoint(x: 4, y: 6)
            ]
        )
    }

    func testSkipsNonFiniteCoordinatesWhenSampling() {
        let points = [
            DownSamplePoint(x: 0, y: 1),
            DownSamplePoint(x: 1, y: .nan),
            DownSamplePoint(x: .nan, y: 2),
            DownSamplePoint(x: 3, y: 4),
            DownSamplePoint(x: 4, y: 3)
        ]

        XCTAssertEqual(
            DownSampler.downSample(points, maxDetails: 2),
            [
                DownSamplePoint(x: 0, y: 1),
                DownSamplePoint(x: 3, y: 4),
                DownSamplePoint(x: 4, y: 3)
            ]
        )
    }

    func testMeanModeAveragesEachBucket() {
        let points = [
            DownSamplePoint(x: 0, y: 2),
            DownSamplePoint(x: 1, y: 4),
            DownSamplePoint(x: 2, y: 6),
            DownSamplePoint(x: 3, y: 8),
            DownSamplePoint(x: 4, y: 10)
        ]

        XCTAssertEqual(
            DownSampler.downSample(points, maxDetails: 2, maxX: 5, mode: .mean),
            [
                DownSamplePoint(x: 1, y: 4),
                DownSamplePoint(x: 3.5, y: 9)
            ]
        )
    }

    func testLinePointDownsamplingPreservesNullBreaksBetweenFiniteRuns() {
        let points = [
            LinePoint(x: 0, y: 1),
            LinePoint(x: 1, y: 5),
            LinePoint(x: 2, y: 2),
            LinePoint(x: 3, y: 6),
            LinePoint(x: 4, y: 3),
            LinePoint(x: 5, y: 7),
            LinePoint(x: 5.001, y: nil),
            LinePoint(x: 6, y: 10),
            LinePoint(x: 7, y: 8),
            LinePoint(x: 8, y: 12),
            LinePoint(x: 9, y: 7),
            LinePoint(x: 10, y: 13),
            LinePoint(x: 11, y: 9)
        ]

        XCTAssertEqual(
            DownSampler.downSample(points, maxDetails: 2),
            [
                LinePoint(x: 0, y: 1),
                LinePoint(x: 1, y: 5),
                LinePoint(x: 4, y: 3),
                LinePoint(x: 5, y: 7),
                LinePoint(x: 5.001, y: nil),
                LinePoint(x: 7, y: 8),
                LinePoint(x: 8, y: 12),
                LinePoint(x: 9, y: 7),
                LinePoint(x: 10, y: 13)
            ]
        )
    }

    func testLargeScaleDigestMatchesTypeScriptCharacterization() {
        let result = DownSampler.downSample(
            generatePoints(seed: 9, count: 100_000),
            maxDetails: 500
        )
        let digest = digest(result)

        XCTAssertEqual(result.count, 1_001)
        XCTAssertEqual(result.first, DownSamplePoint(x: 1_704_067_260_000, y: 96.917))
        XCTAssertEqual(result.last, DownSamplePoint(x: 1_707_067_170_000, y: 203.318))
        XCTAssertEqual(digest.numberCount, 2_002)
        XCTAssertEqual(digest.numberSum, 1.70727426119e15, accuracy: 10_000)
    }

    func testLargeScaleMeanDigestMatchesTypeScriptCharacterization() {
        let result = DownSampler.downSample(
            generatePoints(seed: 10, count: 100_000),
            maxDetails: 500,
            mode: .mean
        )
        let digest = digest(result)

        XCTAssertEqual(result.count, 501)
        XCTAssertEqual(result.first?.x ?? 0, 1_704_070_185_000, accuracy: 0.001)
        XCTAssertEqual(result.first?.y ?? 0, 90.42827000000005, accuracy: 0.000001)
        XCTAssertEqual(result.last, DownSamplePoint(x: 1_707_067_170_000, y: 1_661.635))
        XCTAssertEqual(digest.numberCount, 1_002)
        XCTAssertEqual(digest.numberSum, 8.54490660106e14, accuracy: 10_000)
    }

    func testDownsamplesHundredThousandPointsPerformanceStyle() {
        let points = generatePoints(seed: 11, count: 100_000)
        let result = DownSampler.downSample(points, maxDetails: 500)
        XCTAssertLessThanOrEqual(result.count, 1_002)

        measure {
            _ = DownSampler.downSample(points, maxDetails: 500)
        }
    }
}

private func generatePoints(
    seed: UInt32,
    count: Int,
    intervalMilliseconds: Double = 30_000
) -> [DownSamplePoint] {
    var random = SeededRandom(seed: seed)
    var points: [DownSamplePoint] = []
    points.reserveCapacity(count)

    var y = 100.0
    for index in 0..<count {
        y = max(0, y + (random.next() - 0.5) * 10)
        points.append(DownSamplePoint(
            x: 1_704_067_200_000 + Double(index) * intervalMilliseconds,
            y: (y * 1_000).rounded() / 1_000
        ))
    }
    return points
}

private func digest(_ points: [DownSamplePoint]) -> (numberCount: Int, numberSum: Double) {
    var sum = 0.0
    for point in points {
        sum += point.x
        sum += point.y
    }
    return (points.count * 2, sum)
}

private struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func next() -> Double {
        state &+= 0x6d2b79f5
        var value = state
        value = (value ^ (value >> 15)) &* (value | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296
    }
}
