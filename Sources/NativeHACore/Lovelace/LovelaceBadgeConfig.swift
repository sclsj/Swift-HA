import Foundation

public enum LovelaceBadgeConfig: Decodable, Equatable {
    case entity(LovelaceEntityBadgeConfig)
    case unknown(UnknownBadgeConfig)

    public var type: String {
        switch self {
        case let .entity(config):
            return config.type
        case let .unknown(config):
            return config.type
        }
    }

    public var raw: HAJSONValue {
        switch self {
        case let .entity(config):
            return config.raw
        case let .unknown(config):
            return config.raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)

        if case let .string(entity) = raw {
            self = .entity(LovelaceEntityBadgeConfig(entity: entity, showName: true, raw: raw))
            return
        }

        guard let object = raw.objectValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a Lovelace badge object or entity string.")
            )
        }

        let type = object["type"]?.stringValue ?? "entity"
        if type == "entity" {
            self = .entity(try LovelaceEntityBadgeConfig(from: decoder))
        } else {
            self = .unknown(UnknownBadgeConfig(type: type, raw: raw))
        }
    }
}

public struct LovelaceEntityBadgeConfig: Decodable, Equatable {
    public var type: String
    public var entity: EntityID?
    public var name: String?
    public var icon: String?
    public var showName: Bool?
    public var showState: Bool?
    public var showIcon: Bool?
    public var color: String?
    public var stateColor: Bool?
    public var tapAction: LovelaceActionConfig?
    public var holdAction: LovelaceActionConfig?
    public var doubleTapAction: LovelaceActionConfig?
    public var visibility: [HAJSONValue]?
    public var disabled: Bool?
    public var raw: HAJSONValue

    public init(
        type: String = "entity",
        entity: EntityID? = nil,
        name: String? = nil,
        icon: String? = nil,
        showName: Bool? = nil,
        showState: Bool? = nil,
        showIcon: Bool? = nil,
        color: String? = nil,
        stateColor: Bool? = nil,
        tapAction: LovelaceActionConfig? = nil,
        holdAction: LovelaceActionConfig? = nil,
        doubleTapAction: LovelaceActionConfig? = nil,
        visibility: [HAJSONValue]? = nil,
        disabled: Bool? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.type = type
        self.entity = entity
        self.name = name
        self.icon = icon
        self.showName = showName
        self.showState = showState
        self.showIcon = showIcon
        self.color = color
        self.stateColor = stateColor
        self.tapAction = tapAction
        self.holdAction = holdAction
        self.doubleTapAction = doubleTapAction
        self.visibility = visibility
        self.disabled = disabled
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case type
        case entity
        case name
        case icon
        case showName = "show_name"
        case showState = "show_state"
        case showIcon = "show_icon"
        case color
        case stateColor = "state_color"
        case tapAction = "tap_action"
        case holdAction = "hold_action"
        case doubleTapAction = "double_tap_action"
        case visibility
        case disabled
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? "entity"
        entity = try container.decodeLovelaceStringIfPresent(forKey: .entity)
        name = try container.decodeLovelaceStringIfPresent(forKey: .name)
        icon = try container.decodeLovelaceStringIfPresent(forKey: .icon)
        showName = try container.decodeLovelaceBoolIfPresent(forKey: .showName)
        showState = try container.decodeLovelaceBoolIfPresent(forKey: .showState)
        showIcon = try container.decodeLovelaceBoolIfPresent(forKey: .showIcon)
        color = try container.decodeLovelaceStringIfPresent(forKey: .color)
        stateColor = try container.decodeLovelaceBoolIfPresent(forKey: .stateColor)
        tapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .tapAction)
        holdAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .holdAction)
        doubleTapAction = try container.decodeIfPresent(LovelaceActionConfig.self, forKey: .doubleTapAction)
        visibility = try container.decodeLovelaceArrayIfPresent(forKey: .visibility)
        disabled = try container.decodeLovelaceBoolIfPresent(forKey: .disabled)
    }
}

public struct UnknownBadgeConfig: Decodable, Equatable {
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
