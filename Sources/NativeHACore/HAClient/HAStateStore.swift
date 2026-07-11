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

    @MainActor private var bufferedStateEvents: [HAEvent<HAStateChangedEventData>]? = nil

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
        await MainActor.run { self.bufferedStateEvents = [] }
        
        do {
            async let config: HAConfig = client.callWS(HAWebSocketRequest(type: "get_config"))
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
                services,
                panels,
                currentUser,
                userData,
                systemData
            )

            await apply(
                config: resolved.0,
                states: nil,
                services: resolved.1,
                panels: resolved.2,
                currentUser: resolved.3,
                userData: resolved.4.value ?? [:],
                systemData: resolved.5.value ?? [:]
            )
        } catch {
            await MainActor.run { self.bufferedStateEvents = nil }
            throw error
        }
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
    public func apply(updates: HAStateUpdatesEventData) {
        if let additions = updates.a {
            for (entityID, update) in additions {
                let lastChanged = update.lc.flatMap { Date(timeIntervalSince1970: $0) } ?? Date()
                let lastUpdated = update.lu.flatMap { Date(timeIntervalSince1970: $0) } ?? lastChanged
                
                var context = HAContext(id: "")
                if let cValue = update.c {
                    if let cStr = cValue.stringValue {
                        context = HAContext(id: cStr, parentID: nil, userID: nil)
                    } else if let cDict = cValue.objectValue {
                        context = HAContext(
                            id: cDict["id"]?.stringValue ?? "",
                            parentID: cDict["parent_id"]?.stringValue,
                            userID: cDict["user_id"]?.stringValue
                        )
                    }
                }
                
                let state = HassEntity(
                    entityID: entityID,
                    state: update.s ?? "unknown",
                    attributes: update.a ?? [:],
                    lastChanged: lastChanged,
                    lastUpdated: lastUpdated,
                    context: context
                )
                states[entityID] = state
            }
        }
        
        if let removals = updates.r {
            for entityID in removals {
                states.removeValue(forKey: entityID)
            }
        }
        
        if let changes = updates.c {
            for (entityID, diff) in changes {
                guard var entity = states[entityID] else { continue }
                
                if let toAdd = diff.plus {
                    if let s = toAdd.s {
                        entity.state = s
                    }
                    if let lc = toAdd.lc {
                        let date = Date(timeIntervalSince1970: lc)
                        entity.lastChanged = date
                        entity.lastUpdated = date
                    } else if let lu = toAdd.lu {
                        entity.lastUpdated = Date(timeIntervalSince1970: lu)
                    }
                    
                    if let a = toAdd.a {
                        for (key, value) in a {
                            entity.attributes[key] = value
                        }
                    }
                    
                    if let cValue = toAdd.c {
                        if let cStr = cValue.stringValue {
                            entity.context.id = cStr
                        } else if let cDict = cValue.objectValue {
                            if let id = cDict["id"]?.stringValue { entity.context.id = id }
                            if let pid = cDict["parent_id"]?.stringValue { entity.context.parentID = pid }
                            if let uid = cDict["user_id"]?.stringValue { entity.context.userID = uid }
                        }
                    }
                }
                
                if let toRemove = diff.minus {
                    if let a = toRemove.a {
                        for key in a {
                            entity.attributes.removeValue(forKey: key)
                        }
                    }
                }
                
                states[entityID] = entity
            }
        }
    }

    @MainActor
    public var summary: HomeAssistantStores {
        HomeAssistantStores(
            statesCount: states.count,
            servicesCount: services.count,
            panelsCount: panels.count
        )
    }
}
