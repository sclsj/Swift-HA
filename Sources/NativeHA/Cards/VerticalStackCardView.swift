import NativeHACore
import SwiftUI

struct VerticalStackCardView: View {
    let config: VerticalStackCardConfig
    let displayContext: EntityDisplayContext
    let maxColumns: Int?
    var templateSubscriber: MarkdownTemplateSubscribing?
    var userName: String = "Home Assistant"
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = config.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 2)
            }

            ForEach(Array(config.cards.enumerated()), id: \.offset) { _, card in
                CardHostView(
                    card: card,
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
}
