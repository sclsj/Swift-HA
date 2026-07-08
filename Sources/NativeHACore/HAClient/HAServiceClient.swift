import Foundation

public struct HAServiceTarget: Codable, Equatable {
    public var entityIDs: [EntityID]?
    public var deviceIDs: [String]?
    public var areaIDs: [String]?
    public var floorIDs: [String]?
    public var labelIDs: [String]?

    public init(
        entityIDs: [EntityID]? = nil,
        deviceIDs: [String]? = nil,
        areaIDs: [String]? = nil,
        floorIDs: [String]? = nil,
        labelIDs: [String]? = nil
    ) {
        self.entityIDs = entityIDs
        self.deviceIDs = deviceIDs
        self.areaIDs = areaIDs
        self.floorIDs = floorIDs
        self.labelIDs = labelIDs
    }

    enum CodingKeys: String, CodingKey {
        case entityIDs = "entity_id"
        case deviceIDs = "device_id"
        case areaIDs = "area_id"
        case floorIDs = "floor_id"
        case labelIDs = "label_id"
    }
}

public struct HAServiceCall: Equatable {
    public var domain: String
    public var service: String
    public var serviceData: [String: HAJSONValue]
    public var target: HAJSONValue?

    public init(
        domain: String,
        service: String,
        serviceData: [String: HAJSONValue] = [:],
        target: HAJSONValue? = nil
    ) {
        self.domain = domain
        self.service = service
        self.serviceData = serviceData
        self.target = target
    }
}

public struct HAServiceClient {
    private let client: HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.client = client
    }

    public func callService(
        domain: String,
        service: String,
        serviceData: [String: HAJSONValue] = [:],
        target: HAServiceTarget? = nil,
        returnResponse: Bool = false
    ) async throws -> HAServiceCallResponse<HAJSONValue> {
        var payload: [String: HAJSONValue] = [
            "domain": .string(domain),
            "service": .string(service),
            "service_data": .object(serviceData),
            "return_response": .bool(returnResponse)
        ]

        if let target = target {
            payload["target"] = try HAJSONValue.object(Self.encodeTarget(target))
        }

        return try await client.callWS(HAWebSocketRequest(type: "call_service", payload: payload))
    }

    public func callService(
        _ call: HAServiceCall,
        returnResponse: Bool = false
    ) async throws -> HAServiceCallResponse<HAJSONValue> {
        var payload: [String: HAJSONValue] = [
            "domain": .string(call.domain),
            "service": .string(call.service),
            "service_data": .object(call.serviceData),
            "return_response": .bool(returnResponse)
        ]

        if let target = call.target {
            payload["target"] = target
        }

        return try await client.callWS(HAWebSocketRequest(type: "call_service", payload: payload))
    }

    private static func encodeTarget(_ target: HAServiceTarget) throws -> [String: HAJSONValue] {
        let data = try JSONEncoder().encode(target)
        return try JSONDecoder().decode([String: HAJSONValue].self, from: data)
    }
}
