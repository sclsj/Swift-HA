import Foundation

public struct HAWebSocketRequest: Codable, Equatable {
    public var type: String
    public var payload: [String: HAJSONValue]

    public init(type: String, payload: [String: HAJSONValue] = [:]) {
        self.type = type
        self.payload = payload
    }

    public subscript(key: String) -> HAJSONValue? {
        get { payload[key] }
        set { payload[key] = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        type = try container.decode(String.self, forKey: DynamicCodingKey("type"))
        var payload: [String: HAJSONValue] = [:]
        for key in container.allKeys where key.stringValue != "type" {
            payload[key.stringValue] = try container.decode(HAJSONValue.self, forKey: key)
        }
        self.payload = payload
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(type, forKey: DynamicCodingKey("type"))
        for (key, value) in payload {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public struct HAEmptyResponse: Decodable, Equatable {
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        _ = try? container.decode([String: HAJSONValue].self)
    }
}

public struct HAWebSocketErrorPayload: Codable, Equatable, Error {
    public var code: String
    public var message: String
    public var translationDomain: String?
    public var translationKey: String?
    public var translationPlaceholders: [String: HAJSONValue]?

    public init(
        code: String,
        message: String,
        translationDomain: String? = nil,
        translationKey: String? = nil,
        translationPlaceholders: [String: HAJSONValue]? = nil
    ) {
        self.code = code
        self.message = message
        self.translationDomain = translationDomain
        self.translationKey = translationKey
        self.translationPlaceholders = translationPlaceholders
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case translationDomain = "translation_domain"
        case translationKey = "translation_key"
        case translationPlaceholders = "translation_placeholders"
    }
}

public enum HAWebSocketClientError: Error, Equatable {
    case invalidOutboundMessage
    case invalidInboundMessage
    case missingRequestID
    case authRequiredExpected
    case invalidAuth(String)
    case requestFailed(HAWebSocketErrorPayload)
    case disconnected
    case timedOut
    case unsupportedTransportMessage
}

struct HAIncomingMessage: Decodable {
    var id: Int?
    var type: String
    var success: Bool?
    var result: HAJSONValue?
    var error: HAWebSocketErrorPayload?
    var event: HAJSONValue?
    var haVersion: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case success
        case result
        case error
        case event
        case haVersion = "ha_version"
        case message
    }
}

public final class HASubscription {
    public let id: Int
    private let cancellationHandler: () -> Void
    private var isCancelled = false
    private let lock = NSLock()

    init(id: Int, cancellationHandler: @escaping () -> Void) {
        self.id = id
        self.cancellationHandler = cancellationHandler
    }

    public func cancel() {
        lock.lock()
        let shouldCancel = !isCancelled
        isCancelled = true
        lock.unlock()

        if shouldCancel {
            cancellationHandler()
        }
    }

    deinit {
        cancel()
    }
}

public struct HAServiceCallResponse<Response: Decodable>: Decodable {
    public var context: HAContext
    public var response: Response?
}
