import CoreGraphics
import NativeHACore
import SwiftUI

struct LovelaceCardGridSize: Equatable {
    var rows: LovelaceGridDimension
    var columns: LovelaceGridDimension

    static let `default` = LovelaceCardGridSize(rows: .auto, columns: .count(12))
}

enum LovelaceGridDimension: Equatable {
    case auto
    case full
    case count(Int)
}

enum CardGridSizing {
    static let defaultSectionsMaxColumns = 4
    static let gridColumnMultiplier = 3

    static func masonryColumnCount(for width: CGFloat) -> Int {
        let thresholds: [CGFloat] = [300, 600, 900, 1_200]
        let matched = thresholds.filter { width >= $0 }.count
        return max(1, matched)
    }

    static func sectionsColumnCount(
        for width: CGFloat,
        maxColumns: Int? = nil,
        minColumnWidth: CGFloat = 320,
        horizontalPadding: CGFloat = 16,
        columnGap: CGFloat = 12
    ) -> Int {
        let maxColumns = max(1, maxColumns ?? defaultSectionsMaxColumns)
        let availableWidth = max(0, width - horizontalPadding)
        let columns = Int((availableWidth + columnGap) / (minColumnWidth + columnGap))
        return min(max(1, columns), maxColumns)
    }

    static func masonryColumnAssignments(
        cardSizes: [Int],
        columnCount requestedColumnCount: Int
    ) -> [[Int]] {
        guard !cardSizes.isEmpty else {
            return []
        }

        let columnCount = min(max(1, requestedColumnCount), cardSizes.count)
        var columnSizes = Array(repeating: 0, count: columnCount)
        var columns = Array(repeating: [Int](), count: columnCount)

        for (index, size) in cardSizes.enumerated() {
            let columnIndex = nextMasonryColumnIndex(columnSizes: columnSizes)
            columns[columnIndex].append(index)
            columnSizes[columnIndex] += max(1, size)
        }

        return columns.filter { !$0.isEmpty }
    }

    static func cardSize(for card: LovelaceCardConfig) -> Int {
        switch card {
        case let .entities(config):
            return max(1, 1 + Int(ceil(Double(config.entities.count) / 3.0)))
        case .historyGraph:
            return 3
        case .statisticsGraph:
            return 3
        case let .weatherForecast(config):
            return config.showForecast == true ? 3 : 2
        case let .markdown(config):
            if let cardSize = config.cardSize {
                return max(1, cardSize)
            }
            let lineCount = config.content?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 1
            return max(1, min(4, Int(ceil(Double(lineCount) / 3.0))))
        case let .verticalStack(config):
            return max(1, config.cards.map(cardSize(for:)).reduce(0, +))
        case .heading:
            return 1
        case .tile:
            return 1
        case .unknown:
            return 1
        }
    }

    static func gridSize(for card: LovelaceCardConfig) -> LovelaceCardGridSize {
        if case .heading = card {
            return LovelaceCardGridSize(rows: .count(1), columns: .full)
        }

        let metadata = LovelaceElementFactory.metadata(for: card)
        if let options = metadata.gridOptions?.objectValue {
            return computeGridSize(options: options)
        }
        if let options = metadata.layoutOptions?.objectValue {
            return computeGridSize(options: migrateLayoutOptions(options))
        }
        if case .tile = card {
            return LovelaceCardGridSize(rows: .count(1), columns: .count(6))
        }
        return .default
    }

    static func prefersCompactGrid(_ card: LovelaceCardConfig) -> Bool {
        if case .tile = card {
            return true
        }

        let size = gridSize(for: card)
        if case let .count(columns) = size.columns {
            return columns <= 6
        }
        return false
    }

    private static func nextMasonryColumnIndex(columnSizes: [Int]) -> Int {
        var minIndex = 0
        for index in columnSizes.indices {
            if columnSizes[index] < 5 {
                minIndex = index
                break
            }
            if columnSizes[index] < columnSizes[minIndex] {
                minIndex = index
            }
        }
        return minIndex
    }

    private static func computeGridSize(options: [String: HAJSONValue]) -> LovelaceCardGridSize {
        let rows = dimension(
            value: options["rows"],
            min: options["min_rows"],
            max: options["max_rows"],
            defaultValue: .auto
        )
        let columns = dimension(
            value: options["columns"],
            min: options["min_columns"],
            max: options["max_columns"],
            defaultValue: .count(12)
        )
        return LovelaceCardGridSize(rows: rows, columns: columns)
    }

    private static func migrateLayoutOptions(_ options: [String: HAJSONValue]) -> [String: HAJSONValue] {
        var gridOptions: [String: HAJSONValue] = [:]
        copyMultiplied("grid_columns", to: "columns", from: options, into: &gridOptions)
        copyMultiplied("grid_max_columns", to: "max_columns", from: options, into: &gridOptions)
        copyMultiplied("grid_min_columns", to: "min_columns", from: options, into: &gridOptions)
        copy("grid_rows", to: "rows", from: options, into: &gridOptions)
        copy("grid_max_rows", to: "max_rows", from: options, into: &gridOptions)
        copy("grid_min_rows", to: "min_rows", from: options, into: &gridOptions)
        return gridOptions
    }

    private static func copy(
        _ sourceKey: String,
        to destinationKey: String,
        from source: [String: HAJSONValue],
        into destination: inout [String: HAJSONValue]
    ) {
        if let value = source[sourceKey] {
            destination[destinationKey] = value
        }
    }

    private static func copyMultiplied(
        _ sourceKey: String,
        to destinationKey: String,
        from source: [String: HAJSONValue],
        into destination: inout [String: HAJSONValue]
    ) {
        guard let value = source[sourceKey] else {
            return
        }
        if let intValue = int(from: value) {
            destination[destinationKey] = .integer(intValue * gridColumnMultiplier)
        } else {
            destination[destinationKey] = value
        }
    }

    private static func dimension(
        value: HAJSONValue?,
        min: HAJSONValue?,
        max: HAJSONValue?,
        defaultValue: LovelaceGridDimension
    ) -> LovelaceGridDimension {
        guard let value = value else {
            return defaultValue
        }

        if let stringValue = value.stringValue {
            switch stringValue {
            case "auto":
                return .auto
            case "full":
                return .full
            default:
                if let intValue = Int(stringValue) {
                    return .count(clamp(intValue, min: int(from: min), max: int(from: max)))
                }
                return defaultValue
            }
        }

        guard let intValue = int(from: value) else {
            return defaultValue
        }
        return .count(clamp(intValue, min: int(from: min), max: int(from: max)))
    }

    private static func clamp(_ value: Int, min: Int?, max: Int?) -> Int {
        var result = value
        if let min = min {
            result = Swift.max(result, min)
        }
        if let max = max {
            result = Swift.min(result, max)
        }
        return result
    }

    private static func int(from value: HAJSONValue?) -> Int? {
        guard let value = value else {
            return nil
        }
        switch value {
        case let .integer(intValue):
            return intValue
        case let .double(doubleValue):
            return Int(doubleValue)
        case let .string(stringValue):
            return Int(stringValue)
        default:
            return nil
        }
    }
}

struct LayoutWidthReader<Content: View>: View {
    @State private var width: CGFloat = 0

    let content: (CGFloat) -> Content

    init(@ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.content = content
    }

    var body: some View {
        content(width)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: LayoutWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(LayoutWidthPreferenceKey.self) { newValue in
                width = newValue
            }
    }
}

private struct LayoutWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
