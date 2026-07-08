import NativeHACore
import SwiftUI

struct TileCardView: View {
    let config: TileCardConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    var body: some View {
        guard let entityID = config.entity, !entityID.isEmpty else {
            return AnyView(CardWarningView(title: "Tile entity missing", detail: nil))
        }

        guard let stateObj = displayContext.states[entityID] else {
            return AnyView(CardWarningView(title: "Entity not found", detail: entityID))
        }

        return AnyView(tileContent(stateObj))
    }

    private func tileContent(_ stateObj: HassEntity) -> some View {
        CardChrome {
            HStack(spacing: 12) {
                iconContent(stateObj)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayContext.displayName(for: stateObj, overrideName: config.name))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if config.hideState != true {
                        Text(stateDisplay(for: stateObj))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            performCardTap(stateObj)
        }
    }

    @ViewBuilder
    private func iconContent(_ stateObj: HassEntity) -> some View {
        let action = Self.resolveIconTapAction(
            config: config,
            entityID: stateObj.entityID,
            states: displayContext.states
        )

        if Self.isActionable(action) {
            Button {
                performIconAction(action)
            } label: {
                tileIcon(stateObj)
            }
            .buttonStyle(.plain)
        } else {
            tileIcon(stateObj)
        }
    }

    private func tileIcon(_ stateObj: HassEntity) -> some View {
        LovelaceIconView(
            entityID: stateObj.entityID,
            icon: config.icon,
            color: iconColor(for: stateObj),
            size: 20
        )
        .padding(8)
        .background(iconBackground(for: stateObj))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconBackground(for stateObj: HassEntity) -> Color {
        if HAStateColorResolver.color(for: stateObj) != nil {
            return (iconColor(for: stateObj) ?? .accentColor).opacity(0.16)
        }
        return Color.secondary.opacity(0.10)
    }

    private func iconColor(for stateObj: HassEntity) -> Color? {
        guard let stateColor = HAStateColorResolver.color(for: stateObj) else {
            return nil
        }
        return Color(haHex: stateColor.hex)
    }

    private func stateDisplay(for stateObj: HassEntity) -> String {
        let content = config.stateContent ?? HAEntityFormatting.defaultStateContent(for: stateObj)
        let values = content.compactMap {
            displayContext.stateContentDisplay($0, for: stateObj)
        }
        if !values.isEmpty {
            return values.joined(separator: " · ")
        }
        return displayContext.stateDisplay(for: stateObj)
    }

    private func performCardTap(_ stateObj: HassEntity) {
        CardActionDispatcher(
            entityID: stateObj.entityID,
            states: displayContext.states,
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(
            tapAction: config.tapAction,
            holdAction: config.holdAction,
            doubleTapAction: config.doubleTapAction
        )
    }

    private func performIconAction(_ action: LovelaceResolvedAction) {
        CardActionDispatcher(
            entityID: config.entity,
            states: displayContext.states,
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(action)
    }

    static func resolveIconTapAction(
        config: TileCardConfig,
        entityID: EntityID,
        states: [EntityID: HassEntity]
    ) -> LovelaceResolvedAction {
        LovelaceActionResolver.resolveTileIconTap(
            explicitAction: config.iconTapAction,
            context: LovelaceActionResolutionContext(entity: entityID, states: states)
        )
    }

    static func isActionable(_ action: LovelaceResolvedAction) -> Bool {
        switch action {
        case .moreInfo, .callService, .navigate, .openURL, .assist, .fireDOMEvent:
            return true
        case .none, .unsupported:
            return false
        }
    }
}
