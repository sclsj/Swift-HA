import Foundation

public enum LineStepMode: String, Codable, Equatable {
    case end
}

public enum LinePointSource: String, Codable, Equatable {
    case statistics
    case history
    case generated
}

public struct LinePoint: Codable, Equatable {
    public var x: Double
    public var y: Double?
    public var source: LinePointSource

    public init(x: Double, y: Double?, source: LinePointSource = .history) {
        self.x = x
        self.y = y
        self.source = source
    }
}

public struct LineSeriesSourceRange: Codable, Equatable {
    public var source: LinePointSource
    public var startX: Double?
    public var endX: Double?
    public var alpha: Double

    public init(
        source: LinePointSource,
        startX: Double? = nil,
        endX: Double? = nil,
        alpha: Double
    ) {
        self.source = source
        self.startX = startX
        self.endX = endX
        self.alpha = alpha
    }
}

public struct LineSeries: Codable, Equatable {
    public var id: String
    public var entityID: EntityID
    public var name: String
    public var unit: String?
    public var deviceClass: String?
    public var colorHex: String?
    public var points: [LinePoint]
    public var stepMode: LineStepMode
    public var isFilled: Bool
    public var sourceRanges: [LineSeriesSourceRange]

    public init(
        id: String,
        entityID: EntityID,
        name: String,
        unit: String? = nil,
        deviceClass: String? = nil,
        colorHex: String? = nil,
        points: [LinePoint] = [],
        stepMode: LineStepMode = .end,
        isFilled: Bool = false,
        sourceRanges: [LineSeriesSourceRange] = []
    ) {
        self.id = id
        self.entityID = entityID
        self.name = name
        self.unit = unit
        self.deviceClass = deviceClass
        self.colorHex = colorHex
        self.points = points
        self.stepMode = stepMode
        self.isFilled = isFilled
        self.sourceRanges = sourceRanges
    }
}

public struct LegendItem: Codable, Equatable {
    public var id: String
    public var entityID: EntityID
    public var label: String
    public var colorHex: String?
    public var seriesIDs: [String]

    public init(
        id: String,
        entityID: EntityID,
        label: String,
        colorHex: String? = nil,
        seriesIDs: [String]
    ) {
        self.id = id
        self.entityID = entityID
        self.label = label
        self.colorHex = colorHex
        self.seriesIDs = seriesIDs
    }
}

public struct YAxisMetadata: Codable, Equatable {
    public var unit: String?
    public var deviceClass: String?
    public var minimum: Double?
    public var maximum: Double?
    public var fractionDigits: Int

    public init(
        unit: String? = nil,
        deviceClass: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        fractionDigits: Int = 1
    ) {
        self.unit = unit
        self.deviceClass = deviceClass
        self.minimum = minimum
        self.maximum = maximum
        self.fractionDigits = fractionDigits
    }
}

public struct LineSeriesBuildResult: Codable, Equatable {
    public var series: [LineSeries]
    public var legendItems: [LegendItem]
    public var yAxis: YAxisMetadata
    public var entityIDs: [EntityID]
    public var seriesToEntityIndex: [Int]

    public init(
        series: [LineSeries],
        legendItems: [LegendItem],
        yAxis: YAxisMetadata,
        entityIDs: [EntityID],
        seriesToEntityIndex: [Int]
    ) {
        self.series = series
        self.legendItems = legendItems
        self.yAxis = yAxis
        self.entityIDs = entityIDs
        self.seriesToEntityIndex = seriesToEntityIndex
    }
}

public struct TimelineSegment: Codable, Equatable {
    public var start: Double
    public var end: Double
    public var state: String
    public var stateLocalized: String
    public var colorHex: String
    public var colorName: String?

    public init(
        start: Double,
        end: Double,
        state: String,
        stateLocalized: String,
        colorHex: String,
        colorName: String? = nil
    ) {
        self.start = start
        self.end = end
        self.state = state
        self.stateLocalized = stateLocalized
        self.colorHex = colorHex
        self.colorName = colorName
    }
}

public struct TimelineRow: Codable, Equatable {
    public var entityID: EntityID
    public var name: String
    public var segments: [TimelineSegment]

    public init(entityID: EntityID, name: String, segments: [TimelineSegment]) {
        self.entityID = entityID
        self.name = name
        self.segments = segments
    }
}

public struct TimelineSeriesBuildResult: Codable, Equatable {
    public var rows: [TimelineRow]
    public var legendItems: [LegendItem]

    public init(rows: [TimelineRow], legendItems: [LegendItem]) {
        self.rows = rows
        self.legendItems = legendItems
    }
}
