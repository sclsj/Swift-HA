import NativeHACore
import SwiftUI

struct SectionsLayoutView: View {
    let view: LovelaceViewConfig
    let displayContext: EntityDisplayContext
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        LayoutWidthReader { width in
            let columnCount = CardGridSizing.sectionsColumnCount(
                for: width,
                maxColumns: view.maxColumns
            )
            let visibleSections = LovelaceElementFactory.visibleSections(
                view.sections,
                states: displayContext.states,
                maxColumns: columnCount
            )
            sectionsContent(
                sections: visibleSections,
                columnCount: columnCount
            )
        }
    }

    @ViewBuilder
    private func sectionsContent(
        sections: [LovelaceSectionConfig],
        columnCount: Int
    ) -> some View {
        let sectionColumnCount = max(1, min(columnCount, max(1, sections.count)))

        VStack(alignment: .leading, spacing: 12) {
            if let headerCard = view.header?.card {
                CardHostView(
                    card: headerCard,
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

            if sections.isEmpty {
                EmptyDashboardLayoutView(message: "No sections")
            } else {
                LazyVGrid(
                    columns: gridColumns(count: sectionColumnCount),
                    alignment: .center,
                    spacing: 12
                ) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        SectionColumnView(
                            section: section,
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
            }

            if !view.cards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Imported cards")
                        .font(.headline)
                    MasonryLayoutView(
                        cards: view.cards,
                        displayContext: displayContext,
                        templateSubscriber: templateSubscriber,
                        userName: userName,
                        onMoreInfo: onMoreInfo,
                        onServiceCall: onServiceCall,
                        onNavigate: onNavigate,
                        onOpenURL: onOpenURL
                    )
                }
            }

            if let sidebar = view.sidebar, !sidebar.sections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sidebar.sidebarLabel ?? "Sidebar")
                        .font(.headline)
                    ForEach(Array(sidebar.sections.enumerated()), id: \.offset) { _, section in
                        SectionColumnView(
                            section: section,
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
            }

            if let footerCard = view.footer?.card {
                CardHostView(
                    card: footerCard,
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
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 220, maximum: 420), spacing: 12, alignment: .top),
            count: max(1, count)
        )
    }
}

private struct SectionColumnView: View {
    let section: LovelaceSectionConfig
    let displayContext: EntityDisplayContext
    let maxColumns: Int?
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        let cards = LovelaceElementFactory.visibleCards(
            section.cards,
            states: displayContext.states,
            maxColumns: maxColumns
        )

        VStack(alignment: .leading, spacing: 8) {
            if let title = section.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 2)
            }

            if cards.isEmpty {
                EmptyDashboardLayoutView(message: "No section cards")
            } else {
                ForEach(Array(cardRuns(for: cards).enumerated()), id: \.offset) { _, run in
                    switch run {
                    case let .full(card):
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
                    case let .compact(cards):
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func cardRuns(for cards: [LovelaceCardConfig]) -> [SectionCardRun] {
        var runs: [SectionCardRun] = []
        var compactCards: [LovelaceCardConfig] = []

        func flushCompactCards() {
            guard !compactCards.isEmpty else {
                return
            }
            runs.append(.compact(compactCards))
            compactCards.removeAll()
        }

        for card in cards {
            if CardGridSizing.prefersCompactGrid(card) {
                compactCards.append(card)
            } else {
                flushCompactCards()
                runs.append(.full(card))
            }
        }
        flushCompactCards()

        return runs
    }
}

private enum SectionCardRun {
    case full(LovelaceCardConfig)
    case compact([LovelaceCardConfig])
}
