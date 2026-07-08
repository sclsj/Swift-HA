import Foundation

public struct LovelaceActionConfig: Decodable, Equatable {
    public var action: String
    public var confirmation: LovelaceConfirmationRestrictionConfig?
    public var navigationPath: String?
    public var navigationReplace: Bool?
    public var urlPath: String?
    public var entity: String?
    public var service: String?
    public var performAction: String?
    public var target: HAJSONValue?
    public var serviceData: [String: HAJSONValue]?
    public var data: [String: HAJSONValue]?
    public var pipelineID: String?
    public var startListening: Bool?
    public var raw: HAJSONValue

    public init(
        action: String,
        confirmation: LovelaceConfirmationRestrictionConfig? = nil,
        navigationPath: String? = nil,
        navigationReplace: Bool? = nil,
        urlPath: String? = nil,
        entity: String? = nil,
        service: String? = nil,
        performAction: String? = nil,
        target: HAJSONValue? = nil,
        serviceData: [String: HAJSONValue]? = nil,
        data: [String: HAJSONValue]? = nil,
        pipelineID: String? = nil,
        startListening: Bool? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.action = action
        self.confirmation = confirmation
        self.navigationPath = navigationPath
        self.navigationReplace = navigationReplace
        self.urlPath = urlPath
        self.entity = entity
        self.service = service
        self.performAction = performAction
        self.target = target
        self.serviceData = serviceData
        self.data = data
        self.pipelineID = pipelineID
        self.startListening = startListening
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case action
        case confirmation
        case navigationPath = "navigation_path"
        case navigationReplace = "navigation_replace"
        case urlPath = "url_path"
        case entity
        case service
        case performAction = "perform_action"
        case target
        case serviceData = "service_data"
        case data
        case pipelineID = "pipeline_id"
        case startListening = "start_listening"
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decodeLovelaceStringIfPresent(forKey: .action) ?? ""
        confirmation = try container.decodeIfPresent(LovelaceConfirmationRestrictionConfig.self, forKey: .confirmation)
        navigationPath = try container.decodeLovelaceStringIfPresent(forKey: .navigationPath)
        navigationReplace = try container.decodeLovelaceBoolIfPresent(forKey: .navigationReplace)
        urlPath = try container.decodeLovelaceStringIfPresent(forKey: .urlPath)
        entity = try container.decodeLovelaceStringIfPresent(forKey: .entity)
        service = try container.decodeLovelaceStringIfPresent(forKey: .service)
        performAction = try container.decodeLovelaceStringIfPresent(forKey: .performAction)
        target = try container.decodeLovelaceJSONIfPresent(forKey: .target)
        serviceData = try container.decodeLovelaceObjectIfPresent(forKey: .serviceData)
        data = try container.decodeLovelaceObjectIfPresent(forKey: .data)
        pipelineID = try container.decodeLovelaceStringIfPresent(forKey: .pipelineID)
        startListening = try container.decodeLovelaceBoolIfPresent(forKey: .startListening)
    }
}

public struct LovelaceConfirmationRestrictionConfig: Decodable, Equatable {
    public var text: String?
    public var title: String?
    public var confirmText: String?
    public var dismissText: String?
    public var exemptions: [LovelaceRestrictionConfig]?
    public var raw: HAJSONValue

    public init(
        text: String? = nil,
        title: String? = nil,
        confirmText: String? = nil,
        dismissText: String? = nil,
        exemptions: [LovelaceRestrictionConfig]? = nil,
        raw: HAJSONValue = .object([:])
    ) {
        self.text = text
        self.title = title
        self.confirmText = confirmText
        self.dismissText = dismissText
        self.exemptions = exemptions
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case text
        case title
        case confirmText = "confirm_text"
        case dismissText = "dismiss_text"
        case exemptions
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeLovelaceStringIfPresent(forKey: .text)
        title = try container.decodeLovelaceStringIfPresent(forKey: .title)
        confirmText = try container.decodeLovelaceStringIfPresent(forKey: .confirmText)
        dismissText = try container.decodeLovelaceStringIfPresent(forKey: .dismissText)
        exemptions = try container.decodeIfPresent([LovelaceRestrictionConfig].self, forKey: .exemptions)
    }
}

public struct LovelaceRestrictionConfig: Decodable, Equatable {
    public var user: String
    public var raw: HAJSONValue

    public init(user: String, raw: HAJSONValue = .object([:])) {
        self.user = user
        self.raw = raw
    }

    enum CodingKeys: String, CodingKey {
        case user
    }

    public init(from decoder: Decoder) throws {
        raw = try HAJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeLovelaceStringIfPresent(forKey: .user) ?? ""
    }
}
