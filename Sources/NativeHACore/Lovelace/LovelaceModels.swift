import Foundation

public struct LovelaceDashboard: Decodable, Equatable {
    public var id: String
    public var urlPath: String
    public var requireAdmin: Bool
    public var showInSidebar: Bool
    public var icon: String?
    public var title: String
    public var mode: String
    public var filename: String?

    public init(
        id: String,
        urlPath: String,
        requireAdmin: Bool,
        showInSidebar: Bool,
        icon: String? = nil,
        title: String,
        mode: String,
        filename: String? = nil
    ) {
        self.id = id
        self.urlPath = urlPath
        self.requireAdmin = requireAdmin
        self.showInSidebar = showInSidebar
        self.icon = icon
        self.title = title
        self.mode = mode
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case id
        case urlPath = "url_path"
        case requireAdmin = "require_admin"
        case showInSidebar = "show_in_sidebar"
        case icon
        case title
        case mode
        case filename
    }
}

public enum LovelaceRawConfig: Decodable, Equatable {
    case config(LovelaceConfig)
    case strategy(LovelaceDashboardStrategyConfig)

    public var raw: HAJSONValue {
        switch self {
        case let .config(config):
            return config.raw
        case let .strategy(config):
            return config.raw
        }
    }

    public var views: [LovelaceViewConfig] {
        switch self {
        case let .config(config):
            return config.views
        case .strategy:
            return []
        }
    }

    public var strategy: LovelaceStrategyConfig? {
        switch self {
        case .config:
            return nil
        case let .strategy(config):
            return config.strategy
        }
    }

    public var isStrategyDashboard: Bool {
        strategy != nil
    }

    public init(from decoder: Decoder) throws {
        let raw = try HAJSONValue(from: decoder)
        guard let object = raw.objectValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a Lovelace config object.")
            )
        }

        if object["strategy"] != nil {
            self = .strategy(try LovelaceDashboardStrategyConfig(from: decoder))
        } else {
            self = .config(try LovelaceConfig(from: decoder))
        }
    }
}

public struct LovelaceConfig: Decodable, Equatable {
    public var background: HAJSONValue?
    public var views: [LovelaceViewConfig]
    public var resources: [LovelaceResource]?
    public var raw: HAJSONValue

    public init(
        background: HAJSONValue? = nil,
        views: [LovelaceViewConfig],
        resources: [LovelaceResource]? = nil,
        raw: HAJSONValue
    ) {
        self.background = background
        self.views = views
        self.resources = resources
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case background
        case views
        case resources
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decodeLovelaceJSONIfPresent(forKey: .background)
        views = try container.decodeIfPresent([LovelaceViewConfig].self, forKey: .views) ?? []
        resources = try container.decodeIfPresent([LovelaceResource].self, forKey: .resources)
    }
}

public struct LovelaceDashboardStrategyConfig: Decodable, Equatable {
    public var strategy: LovelaceStrategyConfig
    public var raw: HAJSONValue

    public init(strategy: LovelaceStrategyConfig, raw: HAJSONValue) {
        self.strategy = strategy
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case strategy
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strategy = try container.decode(LovelaceStrategyConfig.self, forKey: .strategy)
    }
}

public struct LovelaceStrategyConfig: Decodable, Equatable {
    public var type: String
    public var raw: HAJSONValue

    public init(type: String, raw: HAJSONValue = .object([:])) {
        self.type = type
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? ""
    }
}

public struct LovelaceResource: Decodable, Equatable {
    public var id: String
    public var type: String
    public var url: String
    public var raw: HAJSONValue

    public init(id: String, type: String, url: String, raw: HAJSONValue = .object([:])) {
        self.id = id
        self.type = type
        self.url = url
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLovelaceStringIfPresent(forKey: .id) ?? ""
        type = try container.decodeLovelaceStringIfPresent(forKey: .type) ?? ""
        url = try container.decodeLovelaceStringIfPresent(forKey: .url) ?? ""
    }
}

public struct LovelaceInfo: Decodable, Equatable {
    public var resourceMode: String
    public var raw: HAJSONValue

    public init(resourceMode: String, raw: HAJSONValue = .object([:])) {
        self.resourceMode = resourceMode
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case resourceMode = "resource_mode"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceMode = try container.decodeLovelaceStringIfPresent(forKey: .resourceMode) ?? ""
    }
}

extension HAJSONValue {
    var lovelaceBoolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    var lovelaceIntValue: Int? {
        switch self {
        case let .integer(value):
            return value
        case let .double(value):
            return Int(value)
        default:
            return nil
        }
    }

    var lovelaceDoubleValue: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        default:
            return nil
        }
    }
}

extension KeyedDecodingContainer {
    func decodeLovelaceJSONIfPresent(forKey key: Key) throws -> HAJSONValue? {
        try decodeIfPresent(HAJSONValue.self, forKey: key)
    }

    func decodeLovelaceStringIfPresent(forKey key: Key) throws -> String? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.stringValue
    }

    func decodeLovelaceBoolIfPresent(forKey key: Key) throws -> Bool? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.lovelaceBoolValue
    }

    func decodeLovelaceIntIfPresent(forKey key: Key) throws -> Int? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.lovelaceIntValue
    }

    func decodeLovelaceDoubleIfPresent(forKey key: Key) throws -> Double? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.lovelaceDoubleValue
    }

    func decodeLovelaceStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        guard let value = try decodeLovelaceJSONIfPresent(forKey: key) else {
            return nil
        }

        switch value {
        case let .string(value):
            return [value]
        case let .array(values):
            return values.compactMap(\.stringValue)
        default:
            return nil
        }
    }

    func decodeLovelaceObjectIfPresent(forKey key: Key) throws -> [String: HAJSONValue]? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.objectValue
    }

    func decodeLovelaceArrayIfPresent(forKey key: Key) throws -> [HAJSONValue]? {
        let value = try decodeLovelaceJSONIfPresent(forKey: key)
        return value?.arrayValue
    }
}
