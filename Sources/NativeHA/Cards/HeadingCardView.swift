import NativeHACore
import SwiftUI

struct HeadingCardView: View {
    let config: HeadingCardConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = config.icon, !icon.isEmpty {
                LovelaceIconView(entityID: nil, icon: icon, size: 17)
            }

            if let heading = config.heading, !heading.isEmpty {
                Text(heading)
                    .font(config.headingStyle == "subtitle" ? .headline : .title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let badgeCount = config.badges?.count, badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            CardActionDispatcher(
                entityID: nil,
                states: displayContext.states,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall
            )
            .perform(tapAction: config.tapAction ?? LovelaceActionConfig(action: "none"))
        }
    }
}
