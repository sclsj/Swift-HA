import Foundation

public struct MoreInfoAttributeRow: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var value: String

    public init(key: String, label: String, value: String) {
        self.key = key
        self.label = label
        self.value = value
    }
}

public struct MoreInfoModel: Equatable {
    public var entityID: EntityID
    public var domain: String
    public var name: String
    public var state: String
    public var stateDisplay: String
    public var isMissing: Bool
    public var isUnavailable: Bool
    public var lastChangedDisplay: String?
    public var lastUpdatedDisplay: String?
    public var attributes: [MoreInfoAttributeRow]
    public var climate: ClimateControlModel?

    public init(
        entityID: EntityID,
        domain: String,
        name: String,
        state: String,
        stateDisplay: String,
        isMissing: Bool,
        isUnavailable: Bool,
        lastChangedDisplay: String?,
        lastUpdatedDisplay: String?,
        attributes: [MoreInfoAttributeRow],
        climate: ClimateControlModel?
    ) {
        self.entityID = entityID
        self.domain = domain
        self.name = name
        self.state = state
        self.stateDisplay = stateDisplay
        self.isMissing = isMissing
        self.isUnavailable = isUnavailable
        self.lastChangedDisplay = lastChangedDisplay
        self.lastUpdatedDisplay = lastUpdatedDisplay
        self.attributes = attributes
        self.climate = climate
    }

    public static func build(
        entityID: EntityID,
        states: [EntityID: HassEntity],
        registryEntries: [EntityID: HAEntityRegistryDisplayEntry] = [:],
        config: HAConfig? = nil,
        maxAttributes: Int = 16
    ) -> MoreInfoModel {
        let domain = EntityIDParser.domain(from: entityID)
        guard let stateObj = states[entityID] else {
            return MoreInfoModel(
                entityID: entityID,
                domain: domain,
                name: missingName(entityID: entityID),
                state: HAStateValue.unavailable,
                stateDisplay: "missing",
                isMissing: true,
                isUnavailable: true,
                lastChangedDisplay: nil,
                lastUpdatedDisplay: nil,
                attributes: [],
                climate: nil
            )
        }

        let registryEntry = registryEntries[stateObj.entityID]
        let attributeRows = stateObj.attributes
            .keys
            .sorted()
            .filter { !hiddenAttributeKeys.contains($0) }
            .prefix(maxAttributes)
            .compactMap { key -> MoreInfoAttributeRow? in
                guard stateObj.attributes[key] != nil else {
                    return nil
                }
                return MoreInfoAttributeRow(
                    key: key,
                    label: HAEntityFormatting.attributeNameDisplay(key),
                    value: HAEntityFormatting.attributeDisplay(
                        for: stateObj,
                        attribute: key,
                        config: config
                    )
                )
            }

        return MoreInfoModel(
            entityID: stateObj.entityID,
            domain: domain,
            name: HAEntityFormatting.displayName(for: stateObj),
            state: stateObj.state,
            stateDisplay: HAEntityFormatting.stateDisplay(
                for: stateObj,
                registryEntry: registryEntry,
                config: config
            ),
            isMissing: false,
            isUnavailable: stateObj.state == HAStateValue.unavailable
                || stateObj.state == HAStateValue.unknown,
            lastChangedDisplay: HAEntityFormatting.stateContentDisplay(
                "last_changed",
                for: stateObj,
                registryEntry: registryEntry,
                config: config
            ),
            lastUpdatedDisplay: HAEntityFormatting.stateContentDisplay(
                "last_updated",
                for: stateObj,
                registryEntry: registryEntry,
                config: config
            ),
            attributes: Array(attributeRows),
            climate: ClimateControlModel(
                stateObj: stateObj,
                registryEntry: registryEntry,
                config: config
            )
        )
    }

    private static func missingName(entityID: EntityID) -> String {
        guard !entityID.isEmpty else {
            return "Missing entity"
        }
        return EntityIDParser.displayObjectID(from: entityID)
    }

    private static let hiddenAttributeKeys: Set<String> = [
        "entity_picture",
        "entity_picture_local"
    ]
}
