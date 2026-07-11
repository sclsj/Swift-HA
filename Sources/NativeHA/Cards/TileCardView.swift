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
        CardChrome(contentInsets: EdgeInsets(
            top: 0,
            leading: HAStyleTokens.tileHorizontalInset,
            bottom: 0,
            trailing: HAStyleTokens.tileHorizontalInset
        )) {
            HStack(spacing: HAStyleTokens.tileHorizontalInset) {
                iconContent(stateObj)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayContext.displayName(for: stateObj, overrideName: config.name))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if config.hideState != true {
                        Text(stateDisplay(for: stateObj))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .frame(minHeight: HAStyleTokens.tileMinimumHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            performCardTap(stateObj, gesture: .doubleTap)
        }
        .onTapGesture(count: 1) {
            performCardTap(stateObj, gesture: .tap)
        }
        .onLongPressGesture {
            performCardTap(stateObj, gesture: .hold)
        }
    }

    @ViewBuilder
    private func iconContent(_ stateObj: HassEntity) -> some View {
        tileIcon(stateObj)
            .onTapGesture(count: 2) {
                performIconGesture(stateObj, gesture: .doubleTap)
            }
            .onTapGesture(count: 1) {
                performIconGesture(stateObj, gesture: .tap)
            }
            .onLongPressGesture {
                performIconGesture(stateObj, gesture: .hold)
            }
    }

    private func tileIcon(_ stateObj: HassEntity) -> some View {
        LovelaceIconView(
            entityID: stateObj.entityID,
            icon: config.icon,
            color: iconColor(for: stateObj),
            size: 20
        )
        .frame(
            width: HAStyleTokens.tileIconSize,
            height: HAStyleTokens.tileIconSize
        )
        .background(iconBackground(for: stateObj))
        .clipShape(Circle())
    }

    private func resolveTileColor(for stateObj: HassEntity) -> (color: Color, isInactive: Bool)? {
        let domain = EntityIDParser.domain(from: stateObj.entityID)
        let stateColor = HAStateColorResolver.color(for: stateObj)
        let isInactive = stateColor == HAStateColorResolver.inactive || stateColor == HAStateColorResolver.unavailable
        
        if domain == "light", !isInactive,
           let rgbArray = stateObj.attributes["rgb_color"]?.arrayValue,
           rgbArray.count == 3,
           let r = rgbArray[0].asDouble,
           let g = rgbArray[1].asDouble,
           let b = rgbArray[2].asDouble {
            
            let rNorm = r / 255.0
            let gNorm = g / 255.0
            let bNorm = b / 255.0
            let maxC = max(rNorm, max(gNorm, bNorm))
            let minC = min(rNorm, min(gNorm, bNorm))
            let delta = maxC - minC
            
            var h = 0.0
            if delta != 0 {
                if maxC == rNorm {
                    h = 60.0 * ((gNorm - bNorm) / delta).truncatingRemainder(dividingBy: 6.0)
                } else if maxC == gNorm {
                    h = 60.0 * (((bNorm - rNorm) / delta) + 2.0)
                } else {
                    h = 60.0 * (((rNorm - gNorm) / delta) + 4.0)
                }
                if h < 0 { h += 360.0 }
            }
            
            var s = maxC == 0 ? 0 : delta / maxC
            var v = maxC
            
            if s < 0.4 {
                if s < 0.1 {
                    v = 225.0 / 255.0
                } else {
                    s = 0.4
                }
            }
            
            return (Color(hue: h / 360.0, saturation: s, brightness: v), false)
        }
        
        guard let stateColor = stateColor, let baseColor = Color(haHex: stateColor.hex) else {
            return nil
        }
        
        return (baseColor, isInactive)
    }

    private func iconBackground(for stateObj: HassEntity) -> Color {
        if let tileColor = resolveTileColor(for: stateObj) {
            return tileColor.color.opacity(
                tileColor.isInactive
                    ? HAStyleTokens.inactiveControlFillOpacity
                    : HAStyleTokens.activeControlFillOpacity
            )
        }
        return Color.secondary.opacity(HAStyleTokens.inactiveControlFillOpacity)
    }

    private func iconColor(for stateObj: HassEntity) -> Color? {
        resolveTileColor(for: stateObj)?.color
    }

    private func stateDisplay(for stateObj: HassEntity) -> String {
        if config.stateContent == nil,
           let climate = ClimateControlModel(
               stateObj: stateObj,
               registryEntry: displayContext.registryEntries[stateObj.entityID],
               config: displayContext.config
           ) {
            return climate.tileStateSummary
        }

        let content = config.stateContent ?? HAEntityFormatting.defaultStateContent(for: stateObj)
        let values = content.compactMap {
            displayContext.stateContentDisplay($0, for: stateObj)
        }
        if !values.isEmpty {
            return values.joined(separator: " · ")
        }
        return displayContext.stateDisplay(for: stateObj)
    }

    private func performCardTap(_ stateObj: HassEntity, gesture: LovelaceActionGesture) {
        CardActionDispatcher(
            entityID: stateObj.entityID,
            states: displayContext.states,
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(
            gesture: gesture,
            tapAction: config.tapAction,
            holdAction: config.holdAction,
            doubleTapAction: config.doubleTapAction
        )
    }

    private func performIconGesture(_ stateObj: HassEntity, gesture: LovelaceActionGesture) {
        CardActionDispatcher(
            entityID: stateObj.entityID,
            states: displayContext.states,
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(
            gesture: gesture,
            tapAction: config.iconTapAction,
            holdAction: config.iconHoldAction,
            doubleTapAction: config.iconDoubleTapAction
        )
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
        case .moreInfo, .callService, .navigate, .openURL, .assist, .fireDOMEvent, .confirmation:
            return true
        case .none, .unsupported:
            return false
        }
    }
}

private extension HAJSONValue {
    var asDouble: Double? {
        switch self {
        case let .double(d): return d
        case let .integer(i): return Double(i)
        default: return nil
        }
    }
}
