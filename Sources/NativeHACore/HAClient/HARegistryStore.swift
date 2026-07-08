import Combine
import Foundation

public final class HARegistryStore: ObservableObject {
    @Published public private(set) var entities: [EntityID: HAEntityRegistryDisplayEntry]
    @Published public private(set) var entityRegistry: [EntityID: HAEntityRegistryEntry]
    @Published public private(set) var devices: [String: HADeviceRegistryEntry]
    @Published public private(set) var areas: [String: HAAreaRegistryEntry]
    @Published public private(set) var floors: [String: HAFloorRegistryEntry]

    public init(
        entities: [EntityID: HAEntityRegistryDisplayEntry] = [:],
        entityRegistry: [EntityID: HAEntityRegistryEntry] = [:],
        devices: [String: HADeviceRegistryEntry] = [:],
        areas: [String: HAAreaRegistryEntry] = [:],
        floors: [String: HAFloorRegistryEntry] = [:]
    ) {
        self.entities = entities
        self.entityRegistry = entityRegistry
        self.devices = devices
        self.areas = areas
        self.floors = floors
    }

    public func refresh(using client: HAWebSocketClientProtocol) async throws {
        async let displayResponse: HAEntityRegistryDisplayResponse = client.callWS(
            HAWebSocketRequest(type: "config/entity_registry/list_for_display")
        )
        async let entityRegistry: [HAEntityRegistryEntry] = client.callWS(
            HAWebSocketRequest(type: "config/entity_registry/list")
        )
        async let devices: [HADeviceRegistryEntry] = client.callWS(
            HAWebSocketRequest(type: "config/device_registry/list")
        )
        async let areas: [HAAreaRegistryEntry] = client.callWS(
            HAWebSocketRequest(type: "config/area_registry/list")
        )
        async let floors: [HAFloorRegistryEntry] = client.callWS(
            HAWebSocketRequest(type: "config/floor_registry/list")
        )

        let resolved = try await (displayResponse, entityRegistry, devices, areas, floors)
        apply(
            displayResponse: resolved.0,
            entityRegistry: resolved.1,
            devices: resolved.2,
            areas: resolved.3,
            floors: resolved.4
        )
    }

    public func refreshEntityDisplay(using client: HAWebSocketClientProtocol) async throws {
        let response: HAEntityRegistryDisplayResponse = try await client.callWS(
            HAWebSocketRequest(type: "config/entity_registry/list_for_display")
        )
        entities = response.expandedEntities
    }

    public func refreshEntityRegistry(using client: HAWebSocketClientProtocol) async throws {
        let entries: [HAEntityRegistryEntry] = try await client.callWS(
            HAWebSocketRequest(type: "config/entity_registry/list")
        )
        entityRegistry = Dictionary(uniqueKeysWithValues: entries.map { ($0.entityID, $0) })
    }

    public func refreshDevices(using client: HAWebSocketClientProtocol) async throws {
        let entries: [HADeviceRegistryEntry] = try await client.callWS(
            HAWebSocketRequest(type: "config/device_registry/list")
        )
        devices = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    public func refreshAreas(using client: HAWebSocketClientProtocol) async throws {
        let entries: [HAAreaRegistryEntry] = try await client.callWS(
            HAWebSocketRequest(type: "config/area_registry/list")
        )
        areas = Dictionary(uniqueKeysWithValues: entries.map { ($0.areaID, $0) })
    }

    public func refreshFloors(using client: HAWebSocketClientProtocol) async throws {
        let entries: [HAFloorRegistryEntry] = try await client.callWS(
            HAWebSocketRequest(type: "config/floor_registry/list")
        )
        floors = Dictionary(uniqueKeysWithValues: entries.map { ($0.floorID, $0) })
    }

    public func apply(
        displayResponse: HAEntityRegistryDisplayResponse? = nil,
        entityRegistry entityRegistryList: [HAEntityRegistryEntry]? = nil,
        devices deviceList: [HADeviceRegistryEntry]? = nil,
        areas areaList: [HAAreaRegistryEntry]? = nil,
        floors floorList: [HAFloorRegistryEntry]? = nil
    ) {
        if let displayResponse = displayResponse {
            entities = displayResponse.expandedEntities
        }
        if let entityRegistryList = entityRegistryList {
            entityRegistry = Dictionary(uniqueKeysWithValues: entityRegistryList.map { ($0.entityID, $0) })
        }
        if let deviceList = deviceList {
            devices = Dictionary(uniqueKeysWithValues: deviceList.map { ($0.id, $0) })
        }
        if let areaList = areaList {
            areas = Dictionary(uniqueKeysWithValues: areaList.map { ($0.areaID, $0) })
        }
        if let floorList = floorList {
            floors = Dictionary(uniqueKeysWithValues: floorList.map { ($0.floorID, $0) })
        }
    }

    public var summary: HomeAssistantStores {
        HomeAssistantStores(
            entitiesCount: entities.count,
            devicesCount: devices.count,
            areasCount: areas.count,
            floorsCount: floors.count
        )
    }
}
