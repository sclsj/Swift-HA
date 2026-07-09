import Foundation

public typealias EntityID = String
public typealias HAServices = [String: [String: HAService]]
public typealias HAPanels = [String: HAPanelInfo]

public enum HAJSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case array([HAJSONValue])
    case object([String: HAJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HAJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: HAJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var objectValue: [String: HAJSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [HAJSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }
}

public extension HAJSONValue {
    init(_ value: String) {
        self = .string(value)
    }

    init(_ value: Bool) {
        self = .bool(value)
    }

    init(_ value: Int) {
        self = .integer(value)
    }

    init(_ value: Double) {
        self = .double(value)
    }
}

public struct HAUser: Decodable, Equatable {
    public var id: String
    public var name: String
    public var isAdmin: Bool
    public var isOwner: Bool

    public init(id: String, name: String, isAdmin: Bool = false, isOwner: Bool = false) {
        self.id = id
        self.name = name
        self.isAdmin = isAdmin
        self.isOwner = isOwner
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isAdmin = "is_admin"
        case isOwner = "is_owner"
    }
}

enum HADateCoding {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO-8601 Home Assistant timestamp."
        )
    }
}

public struct HAContext: Codable, Equatable {
    public var id: String
    public var parentID: String?
    public var userID: String?

    public init(id: String, parentID: String? = nil, userID: String? = nil) {
        self.id = id
        self.parentID = parentID
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case userID = "user_id"
    }
}

public struct HassEntity: Decodable, Equatable {
    public var entityID: EntityID
    public var state: String
    public var attributes: [String: HAJSONValue]
    public var lastChanged: Date
    public var lastUpdated: Date
    public var lastReported: Date?
    public var context: HAContext

    public init(
        entityID: EntityID,
        state: String,
        attributes: [String: HAJSONValue],
        lastChanged: Date,
        lastUpdated: Date,
        lastReported: Date? = nil,
        context: HAContext
    ) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
        self.lastReported = lastReported
        self.context = context
    }

    public var domain: String {
        entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityID
    }

    public var friendlyName: String? {
        attributes["friendly_name"]?.stringValue
    }

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
        case lastReported = "last_reported"
        case context
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(EntityID.self, forKey: .entityID)
        state = try container.decode(String.self, forKey: .state)
        attributes = try container.decode([String: HAJSONValue].self, forKey: .attributes)
        lastChanged = try container.decodeHADate(forKey: .lastChanged)
        lastUpdated = try container.decodeHADate(forKey: .lastUpdated)
        lastReported = try container.decodeOptionalHADate(forKey: .lastReported)
        context = try container.decode(HAContext.self, forKey: .context)
    }
}

private extension KeyedDecodingContainer {
    func decodeHADate(forKey key: Key) throws -> Date {
        let value = try decode(String.self, forKey: key)
        if let date = ISO8601DateFormatter.haDate(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected an ISO-8601 Home Assistant timestamp."
        )
    }

    func decodeOptionalHADate(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        return try decodeHADate(forKey: key)
    }
}

private extension ISO8601DateFormatter {
    static func haDate(from value: String) -> Date? {
        HADateFormatterCache.fractional.date(from: value) ?? HADateFormatterCache.standard.date(from: value)
    }
}

private enum HADateFormatterCache {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public struct HAConfig: Decodable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double
    public var locationName: String
    public var timeZone: String
    public var unitSystem: [String: String]
    public var version: String
    public var components: [String]
    public var configDir: String?
    public var configSource: String?
    public var country: String?
    public var currency: String?
    public var language: String?
    public var internalURL: String?
    public var externalURL: String?
    public var safeMode: Bool
    public var recoveryMode: Bool?
    public var state: String?

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case elevation
        case locationName = "location_name"
        case timeZone = "time_zone"
        case unitSystem = "unit_system"
        case version
        case components
        case configDir = "config_dir"
        case configSource = "config_source"
        case country
        case currency
        case language
        case internalURL = "internal_url"
        case externalURL = "external_url"
        case safeMode = "safe_mode"
        case recoveryMode = "recovery_mode"
        case state
    }
}

public struct HAService: Decodable, Equatable {
    public var name: String?
    public var description: String?
    public var fields: [String: HAServiceField] = [:]
    public var target: HAJSONValue?
    public var response: HAJSONValue?

    public init(
        name: String? = nil,
        description: String? = nil,
        fields: [String: HAServiceField] = [:],
        target: HAJSONValue? = nil,
        response: HAJSONValue? = nil
    ) {
        self.name = name
        self.description = description
        self.fields = fields
        self.target = target
        self.response = response
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case fields
        case target
        case response
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        fields = try container.decodeIfPresent([String: HAServiceField].self, forKey: .fields) ?? [:]
        target = try container.decodeIfPresent(HAJSONValue.self, forKey: .target)
        response = try container.decodeIfPresent(HAJSONValue.self, forKey: .response)
    }
}

public struct HAServiceField: Decodable, Equatable {
    public var name: String?
    public var description: String?
    public var required: Bool?
    public var example: HAJSONValue?
    public var defaultValue: HAJSONValue?
    public var selector: HAJSONValue?
    public var advanced: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case required
        case example
        case defaultValue = "default"
        case selector
        case advanced
    }
}

public struct HAPanelInfo: Decodable, Equatable {
    public var componentName: String
    public var config: HAJSONValue?
    public var icon: String?
    public var title: String?
    public var urlPath: String
    public var configPanelDomain: String?
    public var defaultVisible: Bool?
    public var requireAdmin: Bool?
    public var showInSidebar: Bool?

    enum CodingKeys: String, CodingKey {
        case componentName = "component_name"
        case config
        case icon
        case title
        case urlPath = "url_path"
        case configPanelDomain = "config_panel_domain"
        case defaultVisible = "default_visible"
        case requireAdmin = "require_admin"
        case showInSidebar = "show_in_sidebar"
    }
}

public enum HAEntityCategory: String, Codable, Equatable {
    case config
    case diagnostic
}

public struct HAEntityRegistryDisplayResponse: Decodable, Equatable {
    public var entities: [CompressedEntityRegistryDisplayEntry]
    public var entityCategories: [String: HAEntityCategory]

    public init(entities: [CompressedEntityRegistryDisplayEntry], entityCategories: [String: HAEntityCategory]) {
        self.entities = entities
        self.entityCategories = entityCategories
    }

    enum CodingKeys: String, CodingKey {
        case entities
        case entityCategories = "entity_categories"
    }

    public var expandedEntities: [EntityID: HAEntityRegistryDisplayEntry] {
        Dictionary(
            uniqueKeysWithValues: entities.map { entry in
                let category = entry.entityCategoryIndex.flatMap { entityCategories[String($0)] }
                let expanded = HAEntityRegistryDisplayEntry(
                    entityID: entry.entityID,
                    name: entry.name,
                    icon: entry.icon,
                    deviceID: entry.deviceID,
                    areaID: entry.areaID,
                    labels: entry.labels,
                    hidden: entry.hidden,
                    entityCategory: category,
                    translationKey: entry.translationKey,
                    platform: entry.platform,
                    displayPrecision: entry.displayPrecision,
                    hasEntityName: entry.hasEntityName
                )
                return (entry.entityID, expanded)
            }
        )
    }
}

public struct CompressedEntityRegistryDisplayEntry: Decodable, Equatable {
    public var entityID: EntityID
    public var deviceID: String?
    public var areaID: String?
    public var labels: [String]
    public var entityCategoryIndex: Int?
    public var name: String?
    public var icon: String?
    public var platform: String?
    public var translationKey: String?
    public var hidden: Bool?
    public var displayPrecision: Int?
    public var hasEntityName: Bool?

    enum CodingKeys: String, CodingKey {
        case entityID = "ei"
        case deviceID = "di"
        case areaID = "ai"
        case labels = "lb"
        case entityCategoryIndex = "ec"
        case name = "en"
        case icon = "ic"
        case platform = "pl"
        case translationKey = "tk"
        case hidden = "hb"
        case displayPrecision = "dp"
        case hasEntityName = "hn"
    }
}

public struct HAEntityRegistryDisplayEntry: Equatable {
    public var entityID: EntityID
    public var name: String?
    public var icon: String?
    public var deviceID: String?
    public var areaID: String?
    public var labels: [String]
    public var hidden: Bool?
    public var entityCategory: HAEntityCategory?
    public var translationKey: String?
    public var platform: String?
    public var displayPrecision: Int?
    public var hasEntityName: Bool?
}

public struct HAEntityRegistryEntry: Decodable, Equatable {
    public var id: String
    public var entityID: EntityID
    public var name: String?
    public var icon: String?
    public var platform: String
    public var configEntryID: String?
    public var configSubentryID: String?
    public var deviceID: String?
    public var areaID: String?
    public var labels: [String]
    public var disabledBy: String?
    public var hiddenBy: String?
    public var entityCategory: HAEntityCategory?
    public var hasEntityName: Bool
    public var originalName: String?
    public var uniqueID: String
    public var translationKey: String?
    public var options: [String: HAJSONValue]?
    public var categories: [String: String]
    public var createdAt: Double?
    public var modifiedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case entityID = "entity_id"
        case name
        case icon
        case platform
        case configEntryID = "config_entry_id"
        case configSubentryID = "config_subentry_id"
        case deviceID = "device_id"
        case areaID = "area_id"
        case labels
        case disabledBy = "disabled_by"
        case hiddenBy = "hidden_by"
        case entityCategory = "entity_category"
        case hasEntityName = "has_entity_name"
        case originalName = "original_name"
        case uniqueID = "unique_id"
        case translationKey = "translation_key"
        case options
        case categories
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

public struct HADeviceRegistryEntry: Decodable, Equatable {
    public var id: String
    public var configEntries: [String]
    public var configEntriesSubentries: [String: [String?]]
    public var connections: [[String]]
    public var identifiers: [[String]]
    public var manufacturer: String?
    public var model: String?
    public var modelID: String?
    public var name: String?
    public var labels: [String]
    public var softwareVersion: String?
    public var hardwareVersion: String?
    public var serialNumber: String?
    public var viaDeviceID: String?
    public var areaID: String?
    public var nameByUser: String?
    public var entryType: String?
    public var disabledBy: String?
    public var configurationURL: String?
    public var primaryConfigEntry: String?
    public var createdAt: Double?
    public var modifiedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case configEntries = "config_entries"
        case configEntriesSubentries = "config_entries_subentries"
        case connections
        case identifiers
        case manufacturer
        case model
        case modelID = "model_id"
        case name
        case labels
        case softwareVersion = "sw_version"
        case hardwareVersion = "hw_version"
        case serialNumber = "serial_number"
        case viaDeviceID = "via_device_id"
        case areaID = "area_id"
        case nameByUser = "name_by_user"
        case entryType = "entry_type"
        case disabledBy = "disabled_by"
        case configurationURL = "configuration_url"
        case primaryConfigEntry = "primary_config_entry"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

public struct HAAreaRegistryEntry: Decodable, Equatable {
    public var aliases: [String]
    public var areaID: String
    public var floorID: String?
    public var humidityEntityID: EntityID?
    public var icon: String?
    public var labels: [String]
    public var name: String
    public var picture: String?
    public var temperatureEntityID: EntityID?
    public var createdAt: Double?
    public var modifiedAt: Double?

    enum CodingKeys: String, CodingKey {
        case aliases
        case areaID = "area_id"
        case floorID = "floor_id"
        case humidityEntityID = "humidity_entity_id"
        case icon
        case labels
        case name
        case picture
        case temperatureEntityID = "temperature_entity_id"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

public struct HAFloorRegistryEntry: Decodable, Equatable {
    public var floorID: String
    public var name: String
    public var level: Int?
    public var icon: String?
    public var aliases: [String]
    public var createdAt: Double?
    public var modifiedAt: Double?

    enum CodingKeys: String, CodingKey {
        case floorID = "floor_id"
        case name
        case level
        case icon
        case aliases
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

public struct HAFrontendDataResponse: Decodable, Equatable {
    public var value: [String: HAJSONValue]?
}

public struct HAEvent<EventData: Decodable>: Decodable {
    public var eventType: String
    public var data: EventData
    public var origin: String?
    public var timeFired: Date?
    public var context: HAContext?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case data
        case origin
        case timeFired = "time_fired"
        case context
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try container.decode(String.self, forKey: .eventType)
        data = try container.decode(EventData.self, forKey: .data)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        if container.contains(.timeFired), try !container.decodeNil(forKey: .timeFired) {
            timeFired = try container.decodeHADate(forKey: .timeFired)
        } else {
            timeFired = nil
        }
        context = try container.decodeIfPresent(HAContext.self, forKey: .context)
    }
}

public struct HAStateChangedEventData: Decodable {
    public var entityID: EntityID
    public var oldState: HassEntity?
    public var newState: HassEntity?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case oldState = "old_state"
        case newState = "new_state"
    }
}
