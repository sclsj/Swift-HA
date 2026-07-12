import NativeHACore
import SwiftUI

struct PanelLayoutView: View {
    let view: LovelaceViewConfig
    let displayContext: EntityDisplayContext
    let layout: LovelaceViewLayout
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        switch layout {
        case .sidebar:
            sidebarContent
        default:
            panelContent
        }
    }

    private var panelContent: some View {
        let visibleCards = LovelaceElementFactory.visibleCards(
            view.cards,
            states: displayContext.states,
            maxColumns: 1
        )

        return VStack(alignment: .leading, spacing: 8) {
            if visibleCards.count > 1 {
                Text("Multiple panel cards configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let firstCard = visibleCards.first {
                CardHostView(
                    card: firstCard,
                    displayContext: displayContext,
                    maxColumns: 1,
                    templateSubscriber: templateSubscriber,
                    userName: userName,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall,
                    onNavigate: onNavigate,
                    onOpenURL: onOpenURL
                )
                    .frame(maxWidth: .infinity, alignment: .top)
            } else {
                EmptyDashboardLayoutView(message: "No panel card")
            }
        }
    }

    private var sidebarContent: some View {
        LayoutWidthReader { width in
            let maxColumns = width >= 760 ? 2 : 1
            let visibleCards = LovelaceElementFactory.visibleCards(
                view.cards,
                states: displayContext.states,
                maxColumns: maxColumns
            )
            let sidebarCards = visibleCards.filter {
                LovelaceElementFactory.viewLayoutPosition(for: $0) == "sidebar"
            }
            let mainCards = visibleCards.filter {
                LovelaceElementFactory.viewLayoutPosition(for: $0) != "sidebar"
            }

            if width >= 760 {
                HStack(alignment: .top, spacing: 12) {
                    cardStack(mainCards, maxColumns: maxColumns)
                        .frame(maxWidth: .infinity, alignment: .top)
                    cardStack(sidebarCards, maxColumns: maxColumns)
                        .frame(width: sidebarCards.isEmpty ? 0 : 360, alignment: .top)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    cardStack(mainCards, maxColumns: maxColumns)
                    cardStack(sidebarCards, maxColumns: maxColumns)
                }
            }
        }
    }

    @ViewBuilder
    private func cardStack(_ cards: [LovelaceCardConfig], maxColumns: Int) -> some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    CardHostView(
                        card: card,
                        displayContext: displayContext,
                        maxColumns: maxColumns,
                        templateSubscriber: templateSubscriber,
                        userName: userName,
                        onMoreInfo: onMoreInfo,
                        onServiceCall: onServiceCall,
                        onNavigate: onNavigate,
                        onOpenURL: onOpenURL
                    )
                }
            }
        }
    }
}
