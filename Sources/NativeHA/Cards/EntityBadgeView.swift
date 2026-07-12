import NativeHACore
import SwiftUI

struct BadgeHostView: View {
    let badge: LovelaceBadgeConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        switch badge {
        case let .entity(config):
            if LovelaceCardVisibility.isVisible(
                badge: config,
                context: LovelaceVisibilityContext(
                    states: displayContext.states,
                    entityID: config.entity
                )
            ) {
                EntityBadgeView(
                    config: config,
                    displayContext: displayContext,
                    onMoreInfo: onMoreInfo,
                    onServiceCall: onServiceCall,
                    onNavigate: onNavigate,
                    onOpenURL: onOpenURL
                )
            }
        case let .unknown(config):
            Text(config.type.isEmpty ? "Badge" : config.type)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

struct EntityBadgeView: View {
    let config: LovelaceEntityBadgeConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        guard let entityID = config.entity, !entityID.isEmpty else {
            return AnyView(errorBadge(label: "Missing entity"))
        }

        guard let stateObj = displayContext.states[entityID] else {
            return AnyView(errorBadge(label: entityID))
        }

        return AnyView(entityBadge(stateObj))
    }

    private func entityBadge(_ stateObj: HassEntity) -> some View {
        let options = DisplayOptions(config: config)
        let name = displayContext.displayName(for: stateObj, overrideName: config.name)
        let state = displayContext.defaultStateContentDisplay(for: stateObj)

        return Button {
            CardActionDispatcher(
                entityID: stateObj.entityID,
                states: displayContext.states,
                currentUser: displayContext.currentUser,
                onMoreInfo: onMoreInfo,
                onServiceCall: onServiceCall,
                onNavigate: onNavigate,
                onOpenURL: onOpenURL
            )
            .perform(
                tapAction: config.tapAction,
                holdAction: config.holdAction,
                doubleTapAction: config.doubleTapAction
            )
        } label: {
            HStack(spacing: 6) {
                if options.showIcon {
                    LovelaceIconView(
                        entityID: stateObj.entityID,
                        icon: config.icon,
                        color: iconColor(for: stateObj),
                        size: 15
                    )
                }

                if options.showName && options.showState {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(state)
                            .font(.caption)
                    }
                } else if options.showState {
                    Text(state)
                        .font(.caption)
                } else if options.showName {
                    Text(name)
                        .font(.caption)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(badgeBackground(for: stateObj))
            .foregroundColor(.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func errorBadge(label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(label)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
    }

    private func badgeBackground(for stateObj: HassEntity) -> Color {
        if let color = iconColor(for: stateObj) {
            return color.opacity(0.14)
        }
        return Color.secondary.opacity(0.08)
    }

    private func iconColor(for stateObj: HassEntity) -> Color? {
        guard let stateColor = HAStateColorResolver.color(for: stateObj) else {
            return nil
        }
        return Color(haHex: stateColor.hex)
    }

    struct DisplayOptions: Equatable {
        var showName: Bool
        var showState: Bool
        var showIcon: Bool

        init(showName: Bool, showState: Bool, showIcon: Bool) {
            self.showName = showName
            self.showState = showState
            self.showIcon = showIcon
        }

        init(config: LovelaceEntityBadgeConfig) {
            showName = config.showName ?? false
            showState = config.showState ?? true
            showIcon = config.showIcon ?? true
        }
    }
}
