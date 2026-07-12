import NativeHACore
import SwiftUI

struct MasonryLayoutView: View {
    let cards: [LovelaceCardConfig]
    let displayContext: EntityDisplayContext
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        LayoutWidthReader { width in
            let columnCount = CardGridSizing.masonryColumnCount(for: width)
            let visibleCards = LovelaceElementFactory.visibleCards(
                cards,
                states: displayContext.states,
                maxColumns: columnCount
            )
            masonryContent(cards: visibleCards, columnCount: columnCount)
        }
    }

    @ViewBuilder
    private func masonryContent(cards: [LovelaceCardConfig], columnCount: Int) -> some View {
        if cards.isEmpty {
            EmptyDashboardLayoutView(message: "No cards")
        } else {
            let sizes = cards.map(CardGridSizing.cardSize(for:))
            let assignments = CardGridSizing.masonryColumnAssignments(
                cardSizes: sizes,
                columnCount: columnCount
            )

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(assignments.enumerated()), id: \.offset) { _, cardIndexes in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cardIndexes, id: \.self) { cardIndex in
                            CardHostView(
                                card: cards[cardIndex],
                                displayContext: displayContext,
                                maxColumns: columnCount,
                                templateSubscriber: templateSubscriber,
                                userName: userName,
                                onMoreInfo: onMoreInfo,
                                onServiceCall: onServiceCall,
                                onNavigate: onNavigate,
                                onOpenURL: onOpenURL
                            )
                        }
                    }
                    .frame(maxWidth: 500, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

struct EmptyDashboardLayoutView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}
