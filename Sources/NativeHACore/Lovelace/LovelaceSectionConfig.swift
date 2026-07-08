import Foundation

public struct LovelaceSectionConfig: Decodable, Equatable {
    public var type: String?
    public var cards: [LovelaceCardConfig]
    public var strategy: LovelaceStrategyConfig?
    public var visibility: [HAJSONValue]?
    public var disabled: Bool?
    public var columnSpan: Int?
    public var rowSpan: Int?
    public var background: HAJSONValue?
    public var title: String?
    public var theme: String?
    public var raw: HAJSONValue

    public init(
        type: String? = nil,
        cards: [LovelaceCardConfig] = [],
        strategy: LovelaceStrategyConfig? = nil,
        visibility: [HAJSONValue]? = nil,
        disabled: Bool? = nil,
        columnSpan: Int? = nil,
        rowSpan: Int? = nil,
        background: HAJSONValue? = nil,
        title: String? = nil,
        theme: String? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.type = type
        self.cards = cards
        self.strategy = strategy
        self.visibility = visibility
        self.disabled = disabled
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.background = background
        self.title = title
        self.theme = theme
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case type
        case cards
        case strategy
        case visibility
        case disabled
        case columnSpan = "column_span"
        case rowSpan = "row_span"
        case background
        case title
        case theme
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type)
        cards = try container.decodeIfPresent([LovelaceCardConfig].self, forKey: .cards) ?? []
        strategy = try container.decodeIfPresent(LovelaceStrategyConfig.self, forKey: .strategy)
        visibility = try container.decodeLovelaceArrayIfPresent(forKey: .visibility)
        disabled = try container.decodeLovelaceBoolIfPresent(forKey: .disabled)
        columnSpan = try container.decodeLovelaceIntIfPresent(forKey: .columnSpan)
        rowSpan = try container.decodeLovelaceIntIfPresent(forKey: .rowSpan)
        background = try container.decodeLovelaceJSONIfPresent(forKey: .background)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        theme = try container.decodeLovelaceStringIfPresent(forKey: .theme)
    }
}
