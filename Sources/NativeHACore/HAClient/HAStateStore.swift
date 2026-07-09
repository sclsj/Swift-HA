import Combine
import Foundation

public final class HAStateStore: ObservableObject {
    @Published public private(set) var config: HAConfig?
    @Published public private(set) var states: [EntityID: HassEntity]
    @Published public private(set) var services: HAServices
    @Published public private(set) var panels: HAPanels
    @Published public private(set) var currentUser: HAUser?
    @Published public private(set) var userData: [String: HAJSONValue]
    @Published public private(set) var systemData: [String: HAJSONValue]

    public init(
        config: HAConfig? = nil,
        states: [EntityID: HassEntity] = [:],
        services: HAServices = [:],
        panels: HAPanels = [:],
        currentUser: HAUser? = nil,
        userData: [String: HAJSONValue] = [:],
        systemData: [String: HAJSONValue] = [:]
    ) {
        self.config = config
        self.states = states
        self.services = services
        self.panels = panels
        self.currentUser = currentUser
        self.userData = userData
        self.systemData = systemData
    }

    public func refresh(using client: HAWebSocketClientProtocol) async throws {
        async let config: HAConfig = client.callWS(HAWebSocketRequest(type: "get_config"))
        async let stateList: [HassEntity] = client.callWS(HAWebSocketRequest(type: "get_states"))
        async let services: HAServices = client.callWS(HAWebSocketRequest(type: "get_services"))
        async let panels: HAPanels = client.callWS(HAWebSocketRequest(type: "get_panels"))
        async let currentUser: HAUser = client.callWS(HAWebSocketRequest(type: "auth/current_user"))
        async let userData: HAFrontendDataResponse = client.callWS(
            HAWebSocketRequest(type: "frontend/get_user_data", payload: ["key": .string("core")])
        )
        async let systemData: HAFrontendDataResponse = client.callWS(
            HAWebSocketRequest(type: "frontend/get_system_data", payload: ["key": .string("core")])
        )

        let resolved = try await (
            config,
            stateList,
            services,
            panels,
            currentUser,
            userData,
            systemData
        )

        await apply(
            config: resolved.0,
            states: resolved.1,
            services: resolved.2,
            panels: resolved.3,
            currentUser: resolved.4,
            userData: resolved.5.value ?? [:],
            systemData: resolved.6.value ?? [:]
        )
    }

    @MainActor
    public func apply(
        config: HAConfig? = nil,
        states stateList: [HassEntity]? = nil,
        services: HAServices? = nil,
        panels: HAPanels? = nil,
        currentUser: HAUser? = nil,
        userData: [String: HAJSONValue]? = nil,
        systemData: [String: HAJSONValue]? = nil
    ) {
        if let config = config {
            self.config = config
        }
        if let stateList = stateList {
            states = Dictionary(uniqueKeysWithValues: stateList.map { ($0.entityID, $0) })
        }
        if let services = services {
            self.services = services
        }
        if let panels = panels {
            self.panels = panels
        }
        if let currentUser = currentUser {
            self.currentUser = currentUser
        }
        if let userData = userData {
            self.userData = userData
        }
        if let systemData = systemData {
            self.systemData = systemData
        }
    }

    @MainActor
    public func apply(stateChanged event: HAEvent<HAStateChangedEventData>) {
        guard event.eventType == "state_changed" else {
            return
        }
        if let newState = event.data.newState {
            states[event.data.entityID] = newState
        } else {
            states.removeValue(forKey: event.data.entityID)
        }
    }

    public var summary: HomeAssistantStores {
        HomeAssistantStores(
            statesCount: states.count,
            servicesCount: services.count,
            panelsCount: panels.count
        )
    }
}
