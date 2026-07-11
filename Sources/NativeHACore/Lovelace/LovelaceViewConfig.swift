import Foundation

public enum LovelaceViewLayout: Equatable {
    case masonry
    case sections
    case panel
    case sidebar
    case custom(String)
}

public struct LovelaceViewConfig: Decodable, Equatable {
    public var index: Int?
    public var title: String?
    public var path: String?
    public var icon: String?
    public var showIconAndTitle: Bool?
    public var theme: String?
    public var panel: Bool?
    public var background: HAJSONValue?
    public var visible: HAJSONValue?
    public var subview: Bool?
    public var backPath: String?
    public var maxColumns: Int?
    public var denseSectionPlacement: Bool?
    public var topMargin: Bool?
    public var type: String?
    public var badges: [LovelaceBadgeConfig]
    public var cards: [LovelaceCardConfig]
    public var sections: [LovelaceSectionConfig]
    public var header: LovelaceViewHeaderConfig?
    public var footer: LovelaceViewFooterConfig?
    public var sidebar: LovelaceViewSidebarConfig?
    public var strategy: LovelaceStrategyConfig?
    public var raw: HAJSONValue

    public var layout: LovelaceViewLayout {
        if let type = type {
            switch type {
            case "masonry": return .masonry
            case "sections": return .sections
            case "sidebar": return .sidebar
            case "panel": return .panel
            default: return .custom(type)
            }
        }

        if panel == true {
            return .panel
        }

        if !sections.isEmpty {
            return .sections
        }

        if cards.isEmpty && badges.isEmpty {
            return .sections
        }

        return .masonry
    }

    public init(
        index: Int? = nil,
        title: String? = nil,
        path: String? = nil,
        icon: String? = nil,
        showIconAndTitle: Bool? = nil,
        theme: String? = nil,
        panel: Bool? = nil,
        background: HAJSONValue? = nil,
        visible: HAJSONValue? = nil,
        subview: Bool? = nil,
        backPath: String? = nil,
        maxColumns: Int? = nil,
        denseSectionPlacement: Bool? = nil,
        topMargin: Bool? = nil,
        type: String? = nil,
        badges: [LovelaceBadgeConfig] = [],
        cards: [LovelaceCardConfig] = [],
        sections: [LovelaceSectionConfig] = [],
        header: LovelaceViewHeaderConfig? = nil,
        footer: LovelaceViewFooterConfig? = nil,
        sidebar: LovelaceViewSidebarConfig? = nil,
        strategy: LovelaceStrategyConfig? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.index = index
        self.title = title
        self.path = path
        self.icon = icon
        self.showIconAndTitle = showIconAndTitle
        self.theme = theme
        self.panel = panel
        self.background = background
        self.visible = visible
        self.subview = subview
        self.backPath = backPath
        self.maxColumns = maxColumns
        self.denseSectionPlacement = denseSectionPlacement
        self.topMargin = topMargin
        self.type = type
        self.badges = badges
        self.cards = cards
        self.sections = sections
        self.header = header
        self.footer = footer
        self.sidebar = sidebar
        self.strategy = strategy
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case index
        case title
        case path
        case icon
        case showIconAndTitle = "show_icon_and_title"
        case theme
        case panel
        case background
        case visible
        case subview
        case backPath = "back_path"
        case maxColumns = "max_columns"
        case denseSectionPlacement = "dense_section_placement"
        case topMargin = "top_margin"
        case type
        case badges
        case cards
        case sections
        case header
        case footer
        case sidebar
        case strategy
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeLovelaceIntIfPresent(forKey: .index)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        path = try container.decodeLovelaceStringIfPresent(forKey: .path)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        showIconAndTitle = try container.decodeLovelaceBoolIfPresent(forKey: .showIconAndTitle)
        theme = try container.decodeLovelaceStringIfPresent(forKey: .theme)
        panel = try container.decodeLovelaceBoolIfPresent(forKey: .panel)
        background = try container.decodeLovelaceJSONIfPresent(forKey: .background)
        visible = try container.decodeLovelaceJSONIfPresent(forKey: .visible)
        subview = try container.decodeLovelaceBoolIfPresent(forKey: .subview)
        backPath = try container.decodeLovelaceStringIfPresent(forKey: .backPath)
        maxColumns = try container.decodeLovelaceIntIfPresent(forKey: .maxColumns)
        denseSectionPlacement = try container.decodeLovelaceBoolIfPresent(forKey: .denseSectionPlacement)
        topMargin = try container.decodeLovelaceBoolIfPresent(forKey: .topMargin)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type)
        badges = try container.decodeIfPresent([LovelaceBadgeConfig].self, forKey: .badges) ?? []
        cards = try container.decodeIfPresent([LovelaceCardConfig].self, forKey: .cards) ?? []
        sections = try container.decodeIfPresent([LovelaceSectionConfig].self, forKey: .sections) ?? []
        header = try container.decodeIfPresent(LovelaceViewHeaderConfig.self, forKey: .header)
        footer = try container.decodeIfPresent(LovelaceViewFooterConfig.self, forKey: .footer)
        sidebar = try container.decodeIfPresent(LovelaceViewSidebarConfig.self, forKey: .sidebar)
        strategy = try container.decodeIfPresent(LovelaceStrategyConfig.self, forKey: .strategy)
    }
}

public struct LovelaceViewHeaderConfig: Decodable, Equatable {
    public var card: LovelaceCardConfig?
    public var layout: String?
    public var badgesPosition: String?
    public var badgesWrap: String?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case card
        case layout
        case badgesPosition = "badges_position"
        case badgesWrap = "badges_wrap"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decodeIfPresent(LovelaceCardConfig.self, forKey: .card)
        layout = try container.decodeLovelaceStringIfPresent(forKey: .layout)
        badgesPosition = try container.decodeLovelaceStringIfPresent(forKey: .badgesPosition)
        badgesWrap = try container.decodeLovelaceStringIfPresent(forKey: .badgesWrap)
    }
}

public struct LovelaceViewFooterConfig: Decodable, Equatable {
    public var card: LovelaceCardConfig?
    public var maxWidth: Int?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case card
        case maxWidth = "max_width"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decodeIfPresent(LovelaceCardConfig.self, forKey: .card)
        maxWidth = try container.decodeLovelaceIntIfPresent(forKey: .maxWidth)
    }
}

public struct LovelaceViewSidebarConfig: Decodable, Equatable {
    public var sections: [LovelaceSectionConfig]
    public var contentLabel: String?
    public var sidebarLabel: String?
    public var visibility: [HAJSONValue]?
    public var raw: HAJSONValue

    enum CodingKeys: String, CodingKey {
        case sections
        case contentLabel = "content_label"
        case sidebarLabel = "sidebar_label"
        case visibility
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([LovelaceSectionConfig].self, forKey: .sections) ?? []
        contentLabel = try container.decodeLovelaceStringIfPresent(forKey: .contentLabel)
        sidebarLabel = try container.decodeLovelaceStringIfPresent(forKey: .sidebarLabel)
        visibility = try container.decodeLovelaceArrayIfPresent(forKey: .visibility)
    }
}
