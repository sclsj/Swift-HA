import Foundation

public struct MarkdownTemplateRequest: Equatable {
    public var template: String
    public var entityIDs: [EntityID]?
    public var variables: [String: HAJSONValue]
    public var strict: Bool
    public var reportErrors: Bool

    public init(
        template: String,
        entityIDs: [EntityID]? = nil,
        variables: [String: HAJSONValue] = [:],
        strict: Bool = true,
        reportErrors: Bool = false
    ) {
        self.template = template
        self.entityIDs = entityIDs
        self.variables = variables
        self.strict = strict
        self.reportErrors = reportErrors
    }

    var payload: [String: HAJSONValue] {
        var payload: [String: HAJSONValue] = [
            "template": .string(template),
            "variables": .object(variables),
            "strict": .bool(strict),
            "report_errors": .bool(reportErrors)
        ]

        if let entityIDs = entityIDs, !entityIDs.isEmpty {
            payload["entity_ids"] = .array(entityIDs.map(HAJSONValue.string))
        }

        return payload
    }
}

public enum MarkdownTemplateEvent: Decodable, Equatable {
    case rendered(MarkdownTemplateResult)
    case error(MarkdownTemplateError)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if container.contains(DynamicCodingKey("error")) {
            self = .error(try MarkdownTemplateError(from: decoder))
        } else {
            self = .rendered(try MarkdownTemplateResult(from: decoder))
        }
    }
}

public struct MarkdownTemplateResult: Decodable, Equatable {
    public var result: String
    public var listeners: HAJSONValue?

    public init(result: String, listeners: HAJSONValue? = nil) {
        self.result = result
        self.listeners = listeners
    }

    enum CodingKeys: String, CodingKey {
        case result
        case listeners
    }
}

public struct MarkdownTemplateError: Decodable, Equatable {
    public var error: String
    public var level: String?

    public init(error: String, level: String? = nil) {
        self.error = error
        self.level = level
    }

    enum CodingKeys: String, CodingKey {
        case error
        case level
    }
}

public protocol MarkdownTemplateSubscription: AnyObject {
    func cancel()
}

extension HASubscription: MarkdownTemplateSubscription {}

public protocol MarkdownTemplateSubscribing {
    func subscribeRenderTemplate(
        _ request: MarkdownTemplateRequest,
        onEvent: @escaping (MarkdownTemplateEvent) -> Void
    ) async throws -> MarkdownTemplateSubscription
}

public struct MarkdownTemplateClient: MarkdownTemplateSubscribing {
    private let client: HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.client = client
    }

    public func subscribeRenderTemplate(
        _ request: MarkdownTemplateRequest,
        onEvent: @escaping (MarkdownTemplateEvent) -> Void
    ) async throws -> MarkdownTemplateSubscription {
        try await client.subscribe(
            HAWebSocketRequest(type: "render_template", payload: request.payload),
            onEvent: onEvent
        )
    }
}
