import NativeHACore
import SwiftUI

struct CardHostView: View {
    let card: LovelaceCardConfig
    let displayContext: EntityDisplayContext
    let maxColumns: Int?
    let templateSubscriber: MarkdownTemplateSubscribing?
    let userName: String
    let onMoreInfo: (EntityID) -> Void
    let onServiceCall: (HAServiceCall) -> Void

    private let factory = LovelaceElementFactory()

    init(
        card: LovelaceCardConfig,
        states: [EntityID: HassEntity],
        maxColumns: Int? = nil,
        templateSubscriber: MarkdownTemplateSubscribing? = nil,
        userName: String = "Home Assistant",
        onMoreInfo: @escaping (EntityID) -> Void = { _ in },
        onServiceCall: @escaping (HAServiceCall) -> Void = { _ in }
    ) {
        self.card = card
        self.displayContext = EntityDisplayContext(states: states)
        self.maxColumns = maxColumns
        self.templateSubscriber = templateSubscriber
        self.userName = userName
        self.onMoreInfo = onMoreInfo
        self.onServiceCall = onServiceCall
    }

    init(
        card: LovelaceCardConfig,
        displayContext: EntityDisplayContext,
        maxColumns: Int? = nil,
        templateSubscriber: MarkdownTemplateSubscribing? = nil,
        userName: String = "Home Assistant",
        onMoreInfo: @escaping (EntityID) -> Void = { _ in },
        onServiceCall: @escaping (HAServiceCall) -> Void = { _ in }
    ) {
        self.card = card
        self.displayContext = displayContext
        self.maxColumns = maxColumns
        self.templateSubscriber = templateSubscriber
        self.userName = userName
        self.onMoreInfo = onMoreInfo
        self.onServiceCall = onServiceCall
    }

    @ViewBuilder
    var body: some View {
        if LovelaceElementFactory.isVisible(card: card, states: displayContext.states, maxColumns: maxColumns) {
            factory.makeCard(
                for: card,
                displayContext: displayContext,
                maxColumns: maxColumns,
                templateSubscriber: templateSubscriber,
                userName: userName,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
        }
    }
}

struct CardChrome<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
    }
}

struct NativePlaceholderCardView: View {
    let card: LovelaceCardConfig
    let descriptor: LovelaceCardDescriptor
    let states: [EntityID: HassEntity]

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(descriptor.type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.secondary.opacity(0.10))
                        .cornerRadius(6)
                }

                ForEach(summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var displayTitle: String {
        if let title = descriptor.title, !title.isEmpty {
            return title
        }

        switch card {
        case .entities:
            return "Entities"
        case .historyGraph:
            return "History graph"
        case .weatherForecast:
            return "Weather"
        case .markdown:
            return "Markdown"
        case .tile:
            return tileTitle
        case .heading:
            return "Heading"
        case .verticalStack:
            return "Vertical stack"
        case .unknown:
            return "Card"
        }
    }

    private var tileTitle: String {
        guard let entityID = descriptor.entityID else {
            return "Tile"
        }
        return states[entityID]?.friendlyName ?? entityID
    }

    private var summaryLines: [String] {
        switch card {
        case let .entities(config):
            let visibleRows = config.entities.compactMap { row -> String? in
                if let name = row.name, !name.isEmpty {
                    return name
                }
                return row.entity
            }
            return [
                "\(config.entities.count) rows",
                previewList(visibleRows)
            ].filter { !$0.isEmpty }
        case let .historyGraph(config):
            let entities = config.entities.compactMap(\.entity)
            var lines = ["\(entities.count) history entities"]
            if let hours = config.hoursToShow {
                lines.append("window: \(formatHours(hours))")
            }
            let preview = previewList(entities)
            if !preview.isEmpty {
                lines.append(preview)
            }
            return lines
        case let .weatherForecast(config):
            guard let entityID = config.entity else {
                return ["missing weather entity"]
            }
            let stateLine = entityStateLine(entityID)
            return [stateLine, config.showForecast == false ? "forecast hidden" : "forecast placeholder"]
        case let .markdown(config):
            let content = config.content?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let content = content, !content.isEmpty {
                return ["template markdown", String(content.prefix(96))]
            }
            return ["template markdown"]
        case let .tile(config):
            guard let entityID = config.entity else {
                return ["missing tile entity"]
            }
            return [entityStateLine(entityID)]
        case .heading:
            return []
        case let .verticalStack(config):
            return ["\(config.cards.count) stacked cards"]
        case .unknown:
            return descriptor.debugHints
        }
    }

    private func entityStateLine(_ entityID: EntityID) -> String {
        guard let entity = states[entityID] else {
            return "\(entityID): state unavailable"
        }
        let name = entity.friendlyName ?? entityID
        return "\(name): \(entity.state)"
    }

    private func previewList(_ values: [String]) -> String {
        guard !values.isEmpty else {
            return ""
        }
        let prefix = values.prefix(4).joined(separator: ", ")
        return values.count > 4 ? "\(prefix), ..." : prefix
    }

    private func formatHours(_ hours: Double) -> String {
        if hours.rounded() == hours {
            return "\(Int(hours))h"
        }
        return "\(hours)h"
    }
}
