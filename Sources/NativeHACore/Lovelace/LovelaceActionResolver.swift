import Foundation

public enum LovelaceActionGesture: String {
    case tap
    case hold
    case doubleTap = "double_tap"
}

public struct LovelaceActionResolutionContext {
    public var entity: EntityID?
    public var cameraImage: EntityID?
    public var imageEntity: EntityID?
    public var states: [EntityID: HassEntity]

    public init(
        entity: EntityID? = nil,
        cameraImage: EntityID? = nil,
        imageEntity: EntityID? = nil,
        states: [EntityID: HassEntity] = [:]
    ) {
        self.entity = entity
        self.cameraImage = cameraImage
        self.imageEntity = imageEntity
        self.states = states
    }
}

public enum LovelaceResolvedAction: Equatable {
    case moreInfo(entityID: EntityID)
    case callService(HAServiceCall)
    case navigate(path: String, replace: Bool)
    case openURL(String)
    case assist(startListening: Bool, pipelineID: String)
    case fireDOMEvent(LovelaceActionConfig)
    case none(reason: String)
    case unsupported(action: String)
}

public enum LovelaceActionResolver {
    public static let defaultAction = LovelaceActionConfig(action: "more-info")

    public static func resolve(
        gesture: LovelaceActionGesture,
        tapAction: LovelaceActionConfig? = nil,
        holdAction: LovelaceActionConfig? = nil,
        doubleTapAction: LovelaceActionConfig? = nil,
        context: LovelaceActionResolutionContext
    ) -> LovelaceResolvedAction {
        let actionConfig: LovelaceActionConfig?
        switch gesture {
        case .tap:
            actionConfig = tapAction
        case .hold:
            actionConfig = holdAction
        case .doubleTap:
            actionConfig = doubleTapAction
        }

        return resolve(actionConfig ?? defaultAction, context: context)
    }

    public static func resolveTileIconTap(
        explicitAction: LovelaceActionConfig?,
        context: LovelaceActionResolutionContext
    ) -> LovelaceResolvedAction {
        if let explicitAction = explicitAction {
            return resolve(explicitAction, context: context)
        }

        guard let entityID = context.entity else {
            return .none(reason: "Missing entity for tile icon action.")
        }

        let domain = EntityIDParser.domain(from: entityID)
        if domain == "button" || domain == "input_button" || isToggleableDomain(domain) {
            return resolve(LovelaceActionConfig(action: "toggle"), context: context)
        }

        return .none(reason: "No default icon action for \(domain).")
    }

    public static func resolve(
        _ actionConfig: LovelaceActionConfig,
        context: LovelaceActionResolutionContext
    ) -> LovelaceResolvedAction {
        switch normalizedAction(actionConfig.action) {
        case "more-info":
            guard let entityID = actionConfig.entity ?? context.entity ?? context.cameraImage ?? context.imageEntity else {
                return .none(reason: "Missing entity for more-info action.")
            }
            return .moreInfo(entityID: entityID)

        case "navigate":
            guard let path = actionConfig.navigationPath, !path.isEmpty else {
                return .none(reason: "Missing navigation path.")
            }
            return .navigate(path: path, replace: actionConfig.navigationReplace ?? false)

        case "url":
            guard let url = actionConfig.urlPath, !url.isEmpty else {
                return .none(reason: "Missing URL path.")
            }
            return .openURL(url)

        case "toggle":
            guard let entityID = context.entity else {
                return .none(reason: "Missing entity for toggle action.")
            }
            let currentState = context.states[entityID]?.state ?? HAStateValue.unknown
            return .callService(HADomainLogic.toggleServiceCall(entityID: entityID, currentState: currentState))

        case "perform-action", "call-service":
            guard let serviceID = actionConfig.performAction ?? actionConfig.service else {
                return .none(reason: "Missing service action.")
            }
            guard let serviceCall = explicitServiceCall(
                serviceID: serviceID,
                data: actionConfig.data ?? actionConfig.serviceData ?? [:],
                target: actionConfig.target
            ) else {
                return .none(reason: "Invalid service action '\(serviceID)'.")
            }
            return .callService(serviceCall)

        case "assist":
            return .assist(
                startListening: actionConfig.startListening ?? false,
                pipelineID: actionConfig.pipelineID ?? "last_used"
            )

        case "fire-dom-event":
            return .fireDOMEvent(actionConfig)

        case let action:
            return .unsupported(action: action)
        }
    }

    public static func serviceCallForTurnOnOff(
        entityID: EntityID,
        turnOn: Bool
    ) -> HAServiceCall {
        HADomainLogic.turnOnOffServiceCall(entityID: entityID, turnOn: turnOn)
    }

    private static func normalizedAction(_ action: String) -> String {
        action.isEmpty ? "more-info" : action
    }

    private static func explicitServiceCall(
        serviceID: String,
        data: [String: HAJSONValue],
        target: HAJSONValue?
    ) -> HAServiceCall? {
        let parts = serviceID.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }

        return HAServiceCall(
            domain: parts[0],
            service: parts[1],
            serviceData: data,
            target: target
        )
    }

    private static func isToggleableDomain(_ domain: String) -> Bool {
        [
            "automation",
            "climate",
            "cover",
            "fan",
            "group",
            "humidifier",
            "input_boolean",
            "light",
            "lock",
            "media_player",
            "scene",
            "switch",
            "vacuum",
            "valve",
            "water_heater"
        ].contains(domain)
    }
}
