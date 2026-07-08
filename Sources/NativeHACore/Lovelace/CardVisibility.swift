import Foundation

public struct LovelaceVisibilityContext {
    public var states: [EntityID: HassEntity]
    public var entityID: EntityID?
    public var maxColumns: Int?

    public init(
        states: [EntityID: HassEntity],
        entityID: EntityID? = nil,
        maxColumns: Int? = nil
    ) {
        self.states = states
        self.entityID = entityID
        self.maxColumns = maxColumns
    }
}

public enum LovelaceCardVisibility {
    public static func isVisible(
        conditions: [HAJSONValue]?,
        context: LovelaceVisibilityContext
    ) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else {
            return true
        }

        return conditions.allSatisfy { conditionMet($0, context: context) }
    }

    public static func isVisible(
        metadata: LovelaceCardMetadata,
        context: LovelaceVisibilityContext
    ) -> Bool {
        metadata.disabled != true && isVisible(conditions: metadata.visibility, context: context)
    }

    public static func isVisible(
        badge: LovelaceEntityBadgeConfig,
        context: LovelaceVisibilityContext
    ) -> Bool {
        badge.disabled != true && isVisible(conditions: badge.visibility, context: context)
    }

    public static func isVisible(
        section: LovelaceSectionConfig,
        context: LovelaceVisibilityContext
    ) -> Bool {
        section.disabled != true && isVisible(conditions: section.visibility, context: context)
    }

    public static func conditionMet(
        _ condition: HAJSONValue,
        context: LovelaceVisibilityContext
    ) -> Bool {
        guard let object = condition.objectValue else {
            return false
        }

        switch object["condition"]?.stringValue {
        case "numeric_state":
            return numericStateConditionMet(object, context: context)
        case "and":
            return nestedConditions(object, context: context).allSatisfy {
                conditionMet($0, context: context)
            }
        case "or":
            let nested = nestedConditions(object, context: context)
            guard !nested.isEmpty else {
                return true
            }
            return nested.contains {
                conditionMet($0, context: context)
            }
        case "not":
            let nested = nestedConditions(object, context: context)
            guard !nested.isEmpty else {
                return true
            }
            return !nested.allSatisfy {
                conditionMet($0, context: context)
            }
        case "view_columns":
            return viewColumnsConditionMet(object, context: context)
        case "state", nil:
            return stateConditionMet(object, context: context)
        default:
            return stateConditionMet(object, context: context)
        }
    }

    public static func extractEntityIDs(from conditions: [HAJSONValue]) -> Set<EntityID> {
        var entityIDs = Set<EntityID>()

        for condition in conditions {
            guard let object = condition.objectValue else {
                continue
            }

            if let entity = object["entity"]?.stringValue {
                entityIDs.insert(entity)
            }

            for key in ["state", "state_not", "above", "below"] {
                for value in conditionValues(object[key]) where EntityIDParser.isValid(value) {
                    entityIDs.insert(value)
                }
            }

            if let nested = object["conditions"]?.arrayValue {
                entityIDs.formUnion(extractEntityIDs(from: nested))
            }
        }

        return entityIDs
    }

    private static func stateConditionMet(
        _ condition: [String: HAJSONValue],
        context: LovelaceVisibilityContext
    ) -> Bool {
        let entityID = condition["entity"]?.stringValue ?? context.entityID
        let actualState = stateString(
            entityID: entityID,
            attribute: condition["attribute"]?.stringValue,
            context: context
        )

        let expectedValue = condition["state"] ?? condition["state_not"]
        guard let expectedValue = expectedValue else {
            return false
        }

        let expectedStates = expandedStateValues(expectedValue, context: context)
        if condition["state"] != nil {
            return expectedStates.contains(actualState)
        }
        return !expectedStates.contains(actualState)
    }

    private static func numericStateConditionMet(
        _ condition: [String: HAJSONValue],
        context: LovelaceVisibilityContext
    ) -> Bool {
        let entityID = condition["entity"]?.stringValue ?? context.entityID
        let numericState = numericStateValue(
            entityID: entityID,
            attribute: condition["attribute"]?.stringValue,
            context: context
        )

        guard let numericState = numericState else {
            return false
        }

        let above = numericBound(condition["above"], context: context)
        let below = numericBound(condition["below"], context: context)

        return (above == nil || above! < numericState)
            && (below == nil || below! > numericState)
    }

    private static func viewColumnsConditionMet(
        _ condition: [String: HAJSONValue],
        context: LovelaceVisibilityContext
    ) -> Bool {
        guard let maxColumns = context.maxColumns else {
            return true
        }

        let min = condition["min"]?.haNumberValue
        let max = condition["max"]?.haNumberValue

        return (min == nil || Double(maxColumns) >= min!)
            && (max == nil || Double(maxColumns) <= max!)
    }

    private static func nestedConditions(
        _ condition: [String: HAJSONValue],
        context _: LovelaceVisibilityContext
    ) -> [HAJSONValue] {
        condition["conditions"]?.arrayValue ?? []
    }

    private static func stateString(
        entityID: EntityID?,
        attribute: String?,
        context: LovelaceVisibilityContext
    ) -> String {
        guard let entityID = entityID, let stateObj = context.states[entityID] else {
            return HAStateValue.unknown
        }

        guard let attribute = attribute else {
            return stateObj.state
        }

        return stateObj.attributes[attribute]?.haScalarStringValue ?? HAStateValue.unknown
    }

    private static func numericStateValue(
        entityID: EntityID?,
        attribute: String?,
        context: LovelaceVisibilityContext
    ) -> Double? {
        guard let entityID = entityID, let stateObj = context.states[entityID] else {
            return nil
        }

        if let attribute = attribute {
            return stateObj.attributes[attribute]?.haNumberValue
        }

        return Double(stateObj.state)
    }

    private static func conditionValues(_ value: HAJSONValue?) -> [String] {
        guard let value = value else {
            return []
        }

        switch value {
        case let .array(values):
            return values.compactMap(\.haScalarStringValue)
        default:
            return value.haScalarStringValue.map { [$0] } ?? []
        }
    }

    private static func expandedStateValues(
        _ value: HAJSONValue,
        context: LovelaceVisibilityContext
    ) -> Set<String> {
        let literalValues = conditionValues(value)
        var values = Set(literalValues)
        for candidate in literalValues where EntityIDParser.isValid(candidate) {
            if let state = context.states[candidate]?.state {
                values.insert(state)
            }
        }
        return values
    }

    private static func numericBound(
        _ value: HAJSONValue?,
        context: LovelaceVisibilityContext
    ) -> Double? {
        guard let value = value else {
            return nil
        }

        if let entityID = value.stringValue,
           EntityIDParser.isValid(entityID),
           let state = context.states[entityID]?.state,
           let numericState = Double(state) {
            return numericState
        }

        return value.haNumberValue
    }
}
