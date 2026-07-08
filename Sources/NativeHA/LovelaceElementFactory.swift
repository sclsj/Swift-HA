import NativeHACore
import SwiftUI

enum LovelaceCardRenderKind: Equatable {
    case nativePlaceholder
    case verticalStack
    case fallback
    case error
}

struct LovelaceCardDescriptor: Equatable {
    var type: String
    var renderKind: LovelaceCardRenderKind
    var title: String?
    var entityID: EntityID?
    var childCount: Int
    var rawSummary: String

    var debugHints: [String] {
        var hints: [String] = []
        hints.append("type: \(type.isEmpty ? "missing" : type)")
        if let title = title, !title.isEmpty {
            hints.append("title: \(title)")
        }
        if let entityID = entityID, !entityID.isEmpty {
            hints.append("entity: \(entityID)")
        }
        if childCount > 0 {
            hints.append("children: \(childCount)")
        }
        if !rawSummary.isEmpty {
            hints.append("raw: \(rawSummary)")
        }
        return hints
    }
}

struct LovelaceElementFactory {
    static let nativeCardTypes: Set<String> = [
        "entities",
        "history-graph",
        "weather-forecast",
        "markdown",
        "vertical-stack",
        "heading",
        "tile"
    ]

    static func descriptor(for card: LovelaceCardConfig) -> LovelaceCardDescriptor {
        let type = card.type
        let renderKind: LovelaceCardRenderKind
        if type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            renderKind = .error
        } else if case .verticalStack = card {
            renderKind = .verticalStack
        } else if nativeCardTypes.contains(type) {
            renderKind = .nativePlaceholder
        } else {
            renderKind = .fallback
        }

        return LovelaceCardDescriptor(
            type: type,
            renderKind: renderKind,
            title: title(for: card),
            entityID: primaryEntityID(for: card),
            childCount: childCount(for: card),
            rawSummary: rawSummary(card.raw)
        )
    }

    static func metadata(for card: LovelaceCardConfig) -> LovelaceCardMetadata {
        switch card {
        case let .entities(config):
            return config.metadata
        case let .historyGraph(config):
            return config.metadata
        case let .weatherForecast(config):
            return config.metadata
        case let .markdown(config):
            return config.metadata
        case let .verticalStack(config):
            return config.metadata
        case let .heading(config):
            return config.metadata
        case let .tile(config):
            return config.metadata
        case let .unknown(config):
            return metadata(from: config.raw)
        }
    }

    static func isVisible(
        card: LovelaceCardConfig,
        states: [EntityID: HassEntity],
        maxColumns: Int?
    ) -> Bool {
        let context = LovelaceVisibilityContext(
            states: states,
            entityID: primaryEntityID(for: card),
            maxColumns: maxColumns
        )
        return LovelaceCardVisibility.isVisible(metadata: metadata(for: card), context: context)
    }

    static func visibleCards(
        _ cards: [LovelaceCardConfig],
        states: [EntityID: HassEntity],
        maxColumns: Int?
    ) -> [LovelaceCardConfig] {
        cards.filter {
            isVisible(card: $0, states: states, maxColumns: maxColumns)
        }
    }

    static func visibleSections(
        _ sections: [LovelaceSectionConfig],
        states: [EntityID: HassEntity],
        maxColumns: Int?
    ) -> [LovelaceSectionConfig] {
        let context = LovelaceVisibilityContext(
            states: states,
            entityID: nil,
            maxColumns: maxColumns
        )
        return sections.filter {
            LovelaceCardVisibility.isVisible(section: $0, context: context)
        }
    }

    static func primaryEntityID(for card: LovelaceCardConfig) -> EntityID? {
        switch card {
        case let .entities(config):
            return config.entities.compactMap(\.entity).first
        case let .historyGraph(config):
            return config.entities.compactMap(\.entity).first
        case let .weatherForecast(config):
            return config.entity
        case let .markdown(config):
            return config.entityIDs?.first
        case let .verticalStack(config):
            return config.cards.compactMap(primaryEntityID(for:)).first
        case .heading:
            return nil
        case let .tile(config):
            return config.entity
        case let .unknown(config):
            return entityID(in: config.raw.objectValue?["entity"])
                ?? entityID(in: config.raw.objectValue?["entities"])
        }
    }

    static func title(for card: LovelaceCardConfig) -> String? {
        switch card {
        case let .entities(config):
            return config.title
        case let .historyGraph(config):
            return config.title
        case let .weatherForecast(config):
            return config.name
        case let .markdown(config):
            return config.title
        case let .verticalStack(config):
            return config.title
        case let .heading(config):
            return config.heading
        case let .tile(config):
            return config.name
        case let .unknown(config):
            let object = config.raw.objectValue
            return object?["title"]?.stringValue
                ?? object?["name"]?.stringValue
                ?? object?["heading"]?.stringValue
        }
    }

    static func viewLayoutPosition(for card: LovelaceCardConfig) -> String? {
        metadata(for: card).viewLayout?.objectValue?["position"]?.stringValue
    }

    @ViewBuilder
    func makeCard(
        for card: LovelaceCardConfig,
        displayContext: EntityDisplayContext,
        maxColumns: Int?,
        templateSubscriber: MarkdownTemplateSubscribing?,
        userName: String,
        onMoreInfo: @escaping (EntityID) -> Void,
        onServiceCall: @escaping (HAServiceCall) -> Void
    ) -> some View {
        switch card {
        case let .entities(config):
            EntitiesCardView(
                config: config,
                displayContext: displayContext,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        case .historyGraph:
            NativePlaceholderCardView(
                card: card,
                descriptor: Self.descriptor(for: card),
                states: displayContext.states
            )
        case let .weatherForecast(config):
            WeatherForecastCardView(
                config: config,
                displayContext: displayContext,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        case let .markdown(config):
            MarkdownCardView(
                config: config,
                templateSubscriber: templateSubscriber,
                userName: userName,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        case let .verticalStack(config):
            VerticalStackCardView(
                config: config,
                displayContext: displayContext,
                maxColumns: maxColumns,
                templateSubscriber: templateSubscriber,
                userName: userName,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        case let .heading(config):
            HeadingCardView(
                config: config,
                displayContext: displayContext,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        case let .tile(config):
            TileCardView(
                config: config,
                displayContext: displayContext,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        default:
            let descriptor = Self.descriptor(for: card)
            switch descriptor.renderKind {
            case .nativePlaceholder:
                NativePlaceholderCardView(card: card, descriptor: descriptor, states: displayContext.states)
            case .fallback:
                CardFallbackView(descriptor: descriptor)
            case .error:
                ErrorCardView(
                    title: "Invalid card configuration",
                    message: "No Lovelace card type was configured.",
                    rawSummary: descriptor.rawSummary
                )
            case .verticalStack:
                EmptyView()
            }
        }
    }

    private static func childCount(for card: LovelaceCardConfig) -> Int {
        if case let .verticalStack(config) = card {
            return config.cards.count
        }
        return 0
    }

    private static func metadata(from raw: HAJSONValue) -> LovelaceCardMetadata {
        let object = raw.objectValue ?? [:]
        return LovelaceCardMetadata(
            index: int(from: object["index"]),
            viewIndex: int(from: object["view_index"]),
            viewLayout: object["view_layout"],
            layoutOptions: object["layout_options"],
            gridOptions: object["grid_options"],
            visibility: object["visibility"]?.arrayValue,
            disabled: bool(from: object["disabled"])
        )
    }

    private static func entityID(in value: HAJSONValue?) -> EntityID? {
        guard let value = value else {
            return nil
        }

        switch value {
        case let .string(entityID):
            return entityID
        case let .object(object):
            return object["entity"]?.stringValue
        case let .array(values):
            return values.compactMap(entityID(in:)).first
        default:
            return nil
        }
    }

    private static func rawSummary(_ value: HAJSONValue, limit: Int = 180) -> String {
        let summary = compactSummary(value)
        guard summary.count > limit else {
            return summary
        }
        let endIndex = summary.index(summary.startIndex, offsetBy: limit)
        return "\(summary[..<endIndex])..."
    }

    private static func compactSummary(_ value: HAJSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .string(value):
            return "\"\(value)\""
        case let .array(values):
            let prefix = values.prefix(4).map(compactSummary).joined(separator: ", ")
            let suffix = values.count > 4 ? ", ..." : ""
            return "[\(prefix)\(suffix)]"
        case let .object(object):
            let keys = object.keys.sorted()
            let prefix = keys.prefix(6).map { key -> String in
                "\(key): \(compactSummary(object[key] ?? .null))"
            }.joined(separator: ", ")
            let suffix = keys.count > 6 ? ", ..." : ""
            return "{\(prefix)\(suffix)}"
        }
    }

    private static func bool(from value: HAJSONValue?) -> Bool? {
        guard let value = value else {
            return nil
        }
        if case let .bool(boolValue) = value {
            return boolValue
        }
        return nil
    }

    private static func int(from value: HAJSONValue?) -> Int? {
        guard let value = value else {
            return nil
        }
        switch value {
        case let .integer(intValue):
            return intValue
        case let .double(doubleValue):
            return Int(doubleValue)
        case let .string(stringValue):
            return Int(stringValue)
        default:
            return nil
        }
    }
}
