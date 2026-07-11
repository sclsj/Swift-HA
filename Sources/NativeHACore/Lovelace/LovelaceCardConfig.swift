import Foundation

public protocol LovelaceCardConfigProtocol: Decodable, Equatable {
    var type: String { get }
    var raw: HAJSONValue { get }
}

public enum LovelaceCardConfig: Decodable, Equatable {
    case entities(EntitiesCardConfig)
    case historyGraph(HistoryGraphCardConfig)
    case statisticsGraph(StatisticsGraphCardConfig)
    case weatherForecast(WeatherForecastCardConfig)
    case markdown(MarkdownCardConfig)
    case verticalStack(VerticalStackCardConfig)
    case heading(HeadingCardConfig)
    case tile(TileCardConfig)
    case unknown(UnknownCardConfig)

    public var type: String {
        switch self {
        case let .entities(config):
            return config.type
        case let .historyGraph(config):
            return config.type
        case let .statisticsGraph(config):
            return config.type
        case let .weatherForecast(config):
            return config.type
        case let .markdown(config):
            return config.type
        case let .verticalStack(config):
            return config.type
        case let .heading(config):
            return config.type
        case let .tile(config):
            return config.type
        case let .unknown(config):
            return config.type
        }
    }

    public var raw: HAJSONValue {
        switch self {
        case let .entities(config):
            return config.raw
        case let .historyGraph(config):
            return config.raw
        case let .statisticsGraph(config):
            return config.raw
        case let .weatherForecast(config):
            return config.raw
        case let .markdown(config):
            return config.raw
        case let .verticalStack(config):
            return config.raw
        case let .heading(config):
            return config.raw
        case let .tile(config):
            return config.raw
        case let .unknown(config):
            return config.raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)
        guard let object = raw.objectValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a Lovelace card object.")
            )
        }

        let type = object["type"]?.stringValue ?? ""
        do {
            switch type {
            case "entities":
                self = .entities(try EntitiesCardConfig(from: decoder))
            case "history-graph":
                self = .historyGraph(try HistoryGraphCardConfig(from: decoder))
            case "statistics-graph":
                self = .statisticsGraph(try StatisticsGraphCardConfig(from: decoder))
            case "weather-forecast":
                self = .weatherForecast(try WeatherForecastCardConfig(from: decoder))
            case "markdown":
                self = .markdown(try MarkdownCardConfig(from: decoder))
            case "vertical-stack":
                self = .verticalStack(try VerticalStackCardConfig(from: decoder))
            case "heading":
                self = .heading(try HeadingCardConfig(from: decoder))
            case "tile":
                self = .tile(try TileCardConfig(from: decoder))
            default:
                self = .unknown(UnknownCardConfig(type: type, raw: raw))
            }
        } catch {
            self = .unknown(UnknownCardConfig(type: type, raw: raw))
        }
    }
}

public struct LovelaceCardMetadata: Decodable, Equatable {
    public var index: Int?
    public var viewIndex: Int?
    public var viewLayout: HAJSONValue?
    public var layoutOptions: HAJSONValue?
    public var gridOptions: HAJSONValue?
    public var visibility: [HAJSONValue]?
    public var disabled: Bool?

    public init(
        index: Int? = nil,
        viewIndex: Int? = nil,
        viewLayout: HAJSONValue? = nil,
        layoutOptions: HAJSONValue? = nil,
        gridOptions: HAJSONValue? = nil,
        visibility: [HAJSONValue]? = nil,
        disabled: Bool? = nil
    ) {
        self.index = index
        self.viewIndex = viewIndex
        self.viewLayout = viewLayout
        self.layoutOptions = layoutOptions
        self.gridOptions = gridOptions
        self.visibility = visibility
        self.disabled = disabled
    }

    enum CodingKeys: String, CodingKey {
        case index
        case viewIndex = "view_index"
        case viewLayout = "view_layout"
        case layoutOptions = "layout_options"
        case gridOptions = "grid_options"
        case visibility
        case disabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeLovelaceIntIfPresent(forKey: .index)
        viewIndex = try container.decodeLovelaceIntIfPresent(forKey: .viewIndex)
        viewLayout = try container.decodeLovelaceJSONIfPresent(forKey: .viewLayout)
        layoutOptions = try container.decodeLovelaceJSONIfPresent(forKey: .layoutOptions)
        gridOptions = try container.decodeLovelaceJSONIfPresent(forKey: .gridOptions)
        visibility = try container.decodeLovelaceArrayIfPresent(forKey: .visibility)
        disabled = try container.decodeLovelaceBoolIfPresent(forKey: .disabled)
    }
}

public enum LovelaceEntityRowConfig: Decodable, Equatable {
    case entity(EntityID)
    case config(LovelaceEntityConfig)

    public var entity: EntityID? {
        switch self {
        case let .entity(entity):
            return entity
        case let .config(config):
            return config.entity
        }
    }

    public var name: String? {
        guard case let .config(config) = self else {
            return nil
        }
        return config.name
    }

    public var raw: HAJSONValue {
        switch self {
        case let .entity(entity):
            return .string(entity)
        case let .config(config):
            return config.raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)
        if case let .string(entity) = raw {
            self = .entity(entity)
            return
        }

        self = .config(try LovelaceEntityConfig(from: decoder))
    }
}

public struct LovelaceEntityConfig: Decodable, Equatable {
    public var entity: EntityID
    public var name: String?
    public var icon: String?
    public var type: String?
    public var secondaryInfo: String?
    public var stateColor: Bool?
    public var showName: Bool?
    public var showIcon: Bool?
    public var tapAction: LovelaceActionConfig?
    public var holdAction: LovelaceActionConfig?
    public var doubleTapAction: LovelaceActionConfig?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case entity
        case name
        case icon
        case type
        case secondaryInfo = "secondary_info"
        case stateColor = "state_color"
        case showName = "show_name"
        case showIcon = "show_icon"
        case tapAction = "tap_action"
        case holdAction = "hold_action"
        case doubleTapAction = "double_tap_action"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entity = try container.decodeLovelaceStringIfPresent(forKey: .entity) ?? ""
        name = try container.decodeLovelaceStringIfPresent(forKey: .name)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type)
        secondaryInfo = try container.decodeLovelaceStringIfPresent(forKey: .secondaryInfo)
        stateColor = try container.decodeLovelaceBoolIfPresent(forKey: .stateColor)
        showName = try container.decodeLovelaceBoolIfPresent(forKey: .showName)
        showIcon = try container.decodeLovelaceBoolIfPresent(forKey: .showIcon)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        holdAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .holdAction)
        doubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .doubleTapAction)
    }
}

public enum LovelaceGraphEntityConfig: Decodable, Equatable {
    case entity(EntityID)
    case config(LovelaceGraphEntityObjectConfig)

    public var entity: EntityID? {
        switch self {
        case let .entity(entity):
            return entity
        case let .config(config):
            return config.entity
        }
    }

    public var name: String? {
        guard case let .config(config) = self else {
            return nil
        }
        return config.name
    }

    public var raw: HAJSONValue {
        switch self {
        case let .entity(entity):
            return .string(entity)
        case let .config(config):
            return config.raw
        }
    }

    public init(raw: HAJSONValue) {
        switch raw {
        case let .string(entity):
            self = .entity(entity)
        case .object:
            self = .config(LovelaceGraphEntityObjectConfig(raw: raw))
        default:
            self = .config(LovelaceGraphEntityObjectConfig(entity: "", raw: raw))
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)
        self.init(raw: raw)
    }
}

public struct LovelaceGraphEntityObjectConfig: Decodable, Equatable {
    public var entity: EntityID
    public var name: String?
    public var color: String?
    public var raw: HAJSONValue

    public init(
        entity: EntityID,
        name: String? = nil,
        color: String? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.entity = entity
        self.name = name
        self.color = color
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case entity
        case name
        case color
    }

    public init(raw: HAJSONValue) {
        let object = raw.objectValue ?? [:]
        self.init(
            entity: object["entity"]?.stringValue ?? "",
            name: object["name"]?.stringValue,
            color: object["color"]?.stringValue,
            raw: raw
        )
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)
        self.init(raw: raw)
    }
}

public struct EntitiesCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var title: String?
    public var entities: [LovelaceEntityRowConfig]
    public var showHeaderToggle: Bool?
    public var theme: String?
    public var icon: String?
    public var header: HAJSONValue?
    public var footer: HAJSONValue?
    public var stateColor: Bool?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case entities
        case showHeaderToggle = "show_header_toggle"
        case theme
        case icon
        case header
        case footer
        case stateColor = "state_color"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "entities"
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        entities = try container.decodeIfPresent([LovelaceEntityRowConfig].self, forKey: .entities) ?? []
        showHeaderToggle = try container.decodeLovelaceBoolIfPresent(forKey: .showHeaderToggle)
        theme = try container.decodeLovelaceStringIfPresent(forKey: .theme)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        header = try container.decodeLovelaceJSONIfPresent(forKey: .header)
        footer = try container.decodeLovelaceJSONIfPresent(forKey: .footer)
        stateColor = try container.decodeLovelaceBoolIfPresent(forKey: .stateColor)
    }
}

public struct HistoryGraphCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var entities: [LovelaceGraphEntityConfig]
    public var hoursToShow: Double?
    public var title: String?
    public var showNames: Bool?
    public var logarithmicScale: Bool?
    public var minYAxis: Double?
    public var maxYAxis: Double?
    public var fitYData: Bool?
    public var splitDeviceClasses: Bool?
    public var expandLegend: Bool?
    public var refreshInterval: Double?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case entities
        case hoursToShow = "hours_to_show"
        case title
        case showNames = "show_names"
        case logarithmicScale = "logarithmic_scale"
        case minYAxis = "min_y_axis"
        case maxYAxis = "max_y_axis"
        case fitYData = "fit_y_data"
        case splitDeviceClasses = "split_device_classes"
        case expandLegend = "expand_legend"
        case refreshInterval = "refresh_interval"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "history-graph"
        entities = try Self.decodeEntities(from: container)
        hoursToShow = try container.decodeLovelaceDoubleIfPresent(forKey: .hoursToShow)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        showNames = try container.decodeLovelaceBoolIfPresent(forKey: .showNames)
        logarithmicScale = try container.decodeLovelaceBoolIfPresent(forKey: .logarithmicScale)
        minYAxis = try container.decodeLovelaceDoubleIfPresent(forKey: .minYAxis)
        maxYAxis = try container.decodeLovelaceDoubleIfPresent(forKey: .maxYAxis)
        fitYData = try container.decodeLovelaceBoolIfPresent(forKey: .fitYData)
        splitDeviceClasses = try container.decodeLovelaceBoolIfPresent(forKey: .splitDeviceClasses)
        expandLegend = try container.decodeLovelaceBoolIfPresent(forKey: .expandLegend)
        refreshInterval = try container.decodeLovelaceDoubleIfPresent(forKey: .refreshInterval)
    }

    private static func decodeEntities(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [LovelaceGraphEntityConfig] {
        guard let rawEntities = try container.decodeLovelaceJSONIfPresent(forKey: .entities),
              case let .array(values) = rawEntities else {
            return []
        }
        return values.map { LovelaceGraphEntityConfig(raw: $0) }
    }
}

public struct StatisticsGraphCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var entities: [LovelaceGraphEntityConfig]
    public var title: String?
    public var daysToShow: Double?
    public var period: StatisticPeriod?
    public var statTypes: [StatisticType]?
    public var chartType: StatisticsGraphChartType?
    public var logarithmicScale: Bool?
    public var minYAxis: Double?
    public var maxYAxis: Double?
    public var fitYData: Bool?
    public var hideLegend: Bool?
    public var expandLegend: Bool?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case entities
        case title
        case daysToShow = "days_to_show"
        case period
        case statTypes = "stat_types"
        case chartType = "chart_type"
        case logarithmicScale = "logarithmic_scale"
        case minYAxis = "min_y_axis"
        case maxYAxis = "max_y_axis"
        case fitYData = "fit_y_data"
        case hideLegend = "hide_legend"
        case expandLegend = "expand_legend"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "statistics-graph"
        entities = try Self.decodeEntities(from: container)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        daysToShow = try container.decodeLovelaceDoubleIfPresent(forKey: .daysToShow)
        period = try Self.decodePeriod(from: container)
        statTypes = try Self.decodeStatTypes(from: container)
        chartType = try Self.decodeChartType(from: container)
        logarithmicScale = try container.decodeLovelaceBoolIfPresent(forKey: .logarithmicScale)
        minYAxis = try container.decodeLovelaceDoubleIfPresent(forKey: .minYAxis)
        maxYAxis = try container.decodeLovelaceDoubleIfPresent(forKey: .maxYAxis)
        fitYData = try container.decodeLovelaceBoolIfPresent(forKey: .fitYData)
        hideLegend = try container.decodeLovelaceBoolIfPresent(forKey: .hideLegend)
        expandLegend = try container.decodeLovelaceBoolIfPresent(forKey: .expandLegend)
    }

    private static func decodeEntities(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [LovelaceGraphEntityConfig] {
        guard let rawEntities = try container.decodeLovelaceJSONIfPresent(forKey: .entities),
              case let .array(values) = rawEntities else {
            return []
        }
        return values.map { LovelaceGraphEntityConfig(raw: $0) }
    }

    private static func decodePeriod(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> StatisticPeriod? {
        guard let raw = try container.decodeLovelaceStringIfPresent(forKey: .period) else {
            return nil
        }
        return StatisticPeriod(rawValue: raw)
    }

    private static func decodeChartType(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> StatisticsGraphChartType? {
        guard let raw = try container.decodeLovelaceStringIfPresent(forKey: .chartType) else {
            return nil
        }
        return StatisticsGraphChartType(rawValue: raw)
    }

    private static func decodeStatTypes(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [StatisticType]? {
        guard let rawStatTypes = try container.decodeLovelaceJSONIfPresent(forKey: .statTypes) else {
            return nil
        }

        switch rawStatTypes {
        case let .string(type):
            return StatisticType(rawValue: type).map { [$0] }
        case let .array(values):
            let decoded = values.compactMap { value -> StatisticType? in
                guard let raw = value.stringValue else {
                    return nil
                }
                return StatisticType(rawValue: raw)
            }
            return decoded.isEmpty ? nil : decoded
        default:
            return nil
        }
    }
}

public struct WeatherForecastCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var entity: EntityID?
    public var name: String?
    public var showCurrent: Bool?
    public var showForecast: Bool?
    public var forecastType: String?
    public var forecastSlots: Int?
    public var secondaryInfoAttribute: String?
    public var roundTemperature: Bool?
    public var theme: String?
    public var tapAction: LovelaceActionConfig?
    public var holdAction: LovelaceActionConfig?
    public var doubleTapAction: LovelaceActionConfig?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case entity
        case name
        case showCurrent = "show_current"
        case showForecast = "show_forecast"
        case forecastType = "forecast_type"
        case forecastSlots = "forecast_slots"
        case secondaryInfoAttribute = "secondary_info_attribute"
        case roundTemperature = "round_temperature"
        case theme
        case tapAction = "tap_action"
        case holdAction = "hold_action"
        case doubleTapAction = "double_tap_action"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "weather-forecast"
        entity = try container.decodeLovelaceStringIfPresent(forKey: .entity)
        name = try container.decodeLovelaceStringIfPresent(forKey: .name)
        showCurrent = try container.decodeLovelaceBoolIfPresent(forKey: .showCurrent)
        showForecast = try container.decodeLovelaceBoolIfPresent(forKey: .showForecast)
        forecastType = try container.decodeLovelaceStringIfPresent(forKey: .forecastType)
        forecastSlots = try container.decodeLovelaceIntIfPresent(forKey: .forecastSlots)
        secondaryInfoAttribute = try container.decodeLovelaceStringIfPresent(forKey: .secondaryInfoAttribute)
        roundTemperature = try container.decodeLovelaceBoolIfPresent(forKey: .roundTemperature)
        theme = try container.decodeLovelaceStringIfPresent(forKey: .theme)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        holdAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .holdAction)
        doubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .doubleTapAction)
    }
}

public struct MarkdownCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var content: String?
    public var textOnly: Bool?
    public var title: String?
    public var cardSize: Int?
    public var entityIDs: [String]?
    public var theme: String?
    public var showEmpty: Bool?
    public var tapAction: LovelaceActionConfig?
    public var holdAction: LovelaceActionConfig?
    public var doubleTapAction: LovelaceActionConfig?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case textOnly = "text_only"
        case title
        case cardSize = "card_size"
        case entityIDs = "entity_ids"
        case theme
        case showEmpty = "show_empty"
        case tapAction = "tap_action"
        case holdAction = "hold_action"
        case doubleTapAction = "double_tap_action"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "markdown"
        content = try container.decodeLovelaceStringIfPresent(forKey: .content)
        textOnly = try container.decodeLovelaceBoolIfPresent(forKey: .textOnly)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        cardSize = try container.decodeLovelaceIntIfPresent(forKey: .cardSize)
        entityIDs = try container.decodeLovelaceStringArrayIfPresent(forKey: .entityIDs)
        theme = try container.decodeLovelaceStringIfPresent(forKey: .theme)
        showEmpty = try container.decodeLovelaceBoolIfPresent(forKey: .showEmpty)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        holdAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .holdAction)
        doubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .doubleTapAction)
    }
}

public struct VerticalStackCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var cards: [LovelaceCardConfig]
    public var title: String?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case cards
        case title
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "vertical-stack"
        cards = try container.decodeIfPresent([LovelaceCardConfig].self, forKey: .cards) ?? []
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
    }
}

public struct HeadingCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var headingStyle: String?
    public var heading: String?
    public var icon: String?
    public var tapAction: LovelaceActionConfig?
    public var badges: [HAJSONValue]?
    public var entities: [HAJSONValue]?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case headingStyle = "heading_style"
        case heading
        case icon
        case tapAction = "tap_action"
        case badges
        case entities
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "heading"
        headingStyle = try container.decodeLovelaceStringIfPresent(forKey: .headingStyle)
        heading = try container.decodeLovelaceStringIfPresent(forKey: .heading)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        badges = try container.decodeLovelaceArrayIfPresent(forKey: .badges)
        entities = try container.decodeLovelaceArrayIfPresent(forKey: .entities)
    }
}

public struct TileCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var metadata: LovelaceCardMetadata
    public var entity: EntityID?
    public var name: String?
    public var hideState: Bool?
    public var stateContent: [String]?
    public var icon: String?
    public var color: String?
    public var showEntityPicture: Bool?
    public var vertical: Bool?
    public var tapAction: LovelaceActionConfig?
    public var holdAction: LovelaceActionConfig?
    public var doubleTapAction: LovelaceActionConfig?
    public var iconTapAction: LovelaceActionConfig?
    public var iconHoldAction: LovelaceActionConfig?
    public var iconDoubleTapAction: LovelaceActionConfig?
    public var features: [HAJSONValue]?
    public var featuresPosition: String?
    public var timeFormat: String?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case type
        case entity
        case name
        case hideState = "hide_state"
        case stateContent = "state_content"
        case icon
        case color
        case showEntityPicture = "show_entity_picture"
        case vertical
        case tapAction = "tap_action"
        case holdAction = "hold_action"
        case doubleTapAction = "double_tap_action"
        case iconTapAction = "icon_tap_action"
        case iconHoldAction = "icon_hold_action"
        case iconDoubleTapAction = "icon_double_tap_action"
        case features
        case featuresPosition = "features_position"
        case timeFormat = "time_format"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        metadata = try LovelaceCardMetadata(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "tile"
        entity = try container.decodeLovelaceStringIfPresent(forKey: .entity)
        name = try container.decodeLovelaceStringIfPresent(forKey: .name)
        hideState = try container.decodeLovelaceBoolIfPresent(forKey: .hideState)
        stateContent = try container.decodeLovelaceStringArrayIfPresent(forKey: .stateContent)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        color = try container.decodeLovelaceStringIfPresent(forKey: .color)
        showEntityPicture = try container.decodeLovelaceBoolIfPresent(forKey: .showEntityPicture)
        vertical = try container.decodeLovelaceBoolIfPresent(forKey: .vertical)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        holdAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .holdAction)
        doubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .doubleTapAction)
        iconTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .iconTapAction)
        iconHoldAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .iconHoldAction)
        iconDoubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .iconDoubleTapAction)
        features = try container.decodeLovelaceArrayIfPresent(forKey: .features)
        featuresPosition = try container.decodeLovelaceStringIfPresent(forKey: .featuresPosition)
        timeFormat = try container.decodeLovelaceStringIfPresent(forKey: .timeFormat)
    }
}

public struct UnknownCardConfig: LovelaceCardConfigProtocol {
    public var type: String
    public var raw: HAJSONValue

    public init(type: String, raw: HAJSONValue) {
        self.type = type
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        type = raw.objectValue?["type"]?.stringValue ?? ""
    }
}
