import NativeHACore
import SwiftUI

enum EntityRowKind: Equatable {
    case simple
    case sensor
    case toggle
    case button
}

struct EntityRowView: View {
    let row: LovelaceEntityRowConfig
    let displayContext: EntityDisplayContext
    var inheritedStateColor: Bool?
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }

    @State private var isHovering = false

    var body: some View {
        let model = EntityRowModel(row: row)

        if model.entityID.isEmpty {
            EntityNotFoundWarningRow(entityID: nil)
        } else if let stateObj = displayContext.states[model.entityID] {
            rowContent(model: model, stateObj: stateObj)
        } else {
            EntityNotFoundWarningRow(entityID: model.entityID)
        }
    }

    @ViewBuilder
    private func rowContent(model: EntityRowModel, stateObj: HassEntity) -> some View {
        HStack(spacing: 0) {
            if model.showIcon {
                LovelaceIconView(
                    entityID: stateObj.entityID,
                    icon: model.icon,
                    color: iconColor(for: stateObj, model: model)
                )
                .frame(
                    width: HAStyleTokens.entityIconColumnWidth,
                    height: HAStyleTokens.entityIconColumnWidth
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                if model.showName {
                    Text(displayContext.displayName(for: stateObj, overrideName: model.name))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let secondary = secondaryInfo(model: model, stateObj: stateObj) {
                    Text(secondary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, model.showIcon ? HAStyleTokens.space4 : 0)
            .padding(.trailing, HAStyleTokens.space2)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingContent(model: model, stateObj: stateObj)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: HAStyleTokens.entityRowMinimumHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: HAStyleTokens.space2)
                .fill(isHovering ? HAStyleTokens.rowHoverColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            performTap(model: model, stateObj: stateObj, gesture: .doubleTap)
        }
        .onTapGesture(count: 1) {
            performTap(model: model, stateObj: stateObj, gesture: .tap)
        }
        .onLongPressGesture {
            performTap(model: model, stateObj: stateObj, gesture: .hold)
        }
    }

    @ViewBuilder
    private func trailingContent(model: EntityRowModel, stateObj: HassEntity) -> some View {
        switch Self.kind(for: model, stateObj: stateObj) {
        case .button:
            Button("Press") {
                onServiceCall(HAServiceCall(
                    domain: "button",
                    service: "press",
                    serviceData: ["entity_id": .string(stateObj.entityID)]
                ))
            }
            .buttonStyle(.borderless)
            .disabled(stateObj.state == HAStateValue.unavailable)
        case .toggle:
            if Self.shouldShowToggle(for: stateObj) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { stateObj.state == "on" },
                        set: { turnOn in
                            onServiceCall(LovelaceActionResolver.serviceCallForTurnOnOff(
                                entityID: stateObj.entityID,
                                turnOn: turnOn
                            ))
                        }
                    )
                )
                .labelsHidden()
                .disabled(stateObj.state == HAStateValue.unavailable)
            } else {
                stateText(stateObj)
            }
        case .simple, .sensor:
            stateText(stateObj)
        }
    }

    private func stateText(_ stateObj: HassEntity) -> some View {
        Text(displayContext.stateDisplay(for: stateObj))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func performTap(model: EntityRowModel, stateObj: HassEntity, gesture: LovelaceActionGesture) {
        CardActionDispatcher(
            entityID: stateObj.entityID,
            states: displayContext.states,
            onMoreInfo: onMoreInfo,
            onServiceCall: onServiceCall
        )
        .perform(
            gesture: gesture,
            tapAction: model.tapAction,
            holdAction: model.holdAction,
            doubleTapAction: model.doubleTapAction
        )
    }

    private func secondaryInfo(model: EntityRowModel, stateObj: HassEntity) -> String? {
        guard let secondaryInfo = model.secondaryInfo else {
            return nil
        }

        switch secondaryInfo {
        case "entity-id":
            return stateObj.entityID
        case "last-changed":
            return displayContext.stateContentDisplay("last_changed", for: stateObj)
        case "last-updated":
            return displayContext.stateContentDisplay("last_updated", for: stateObj)
        case "last-triggered":
            return displayContext.stateContentDisplay("last_triggered", for: stateObj)
        case "position":
            if let pos = stateObj.attributes["current_position"]?.haNumberValue {
                return "Position: \(Int(pos))"
            }
            return nil
        case "tilt-position":
            if let tilt = stateObj.attributes["current_tilt_position"]?.haNumberValue {
                return "Tilt position: \(Int(tilt))"
            }
            return nil
        case "brightness":
            if let brightness = stateObj.attributes["brightness"]?.haNumberValue {
                let percent = Int(round((brightness / 255.0) * 100.0))
                return "\(percent) %"
            }
            return nil
        case "state":
            return displayContext.stateDisplay(for: stateObj)
        default:
            return nil
        }
    }

    private func iconColor(for stateObj: HassEntity, model: EntityRowModel) -> Color? {
        let shouldColor = model.stateColor ?? inheritedStateColor ?? false
        guard shouldColor, let stateColor = HAStateColorResolver.color(for: stateObj) else {
            return nil
        }
        return Color(haHex: stateColor.hex)
    }

    static func kind(for row: LovelaceEntityRowConfig) -> EntityRowKind {
        let model = EntityRowModel(row: row)
        return kind(for: model, stateObj: nil)
    }

    static func kind(for model: EntityRowModel, stateObj: HassEntity?) -> EntityRowKind {
        if let explicit = model.type {
            switch explicit {
            case "button":
                return .button
            case "toggle":
                return .toggle
            case "sensor":
                return .sensor
            case "simple-entity", "entity":
                return .simple
            default:
                break
            }
        }

        let domain = EntityIDParser.domain(from: stateObj?.entityID ?? model.entityID)
        switch domain {
        case "button":
            return .button
        case "automation", "fan", "humidifier", "input_boolean", "light", "script", "switch":
            return .toggle
        case "sensor":
            return .sensor
        default:
            return .simple
        }
    }

    static func shouldShowToggle(for stateObj: HassEntity) -> Bool {
        ["on", "off", HAStateValue.unknown, HAStateValue.unavailable].contains(stateObj.state)
    }
}

struct EntityRowModel: Equatable {
    var entityID: EntityID
    var name: String?
    var icon: String?
    var type: String?
    var secondaryInfo: String?
    var stateColor: Bool?
    var showName: Bool
    var showIcon: Bool
    var tapAction: LovelaceActionConfig?
    var holdAction: LovelaceActionConfig?
    var doubleTapAction: LovelaceActionConfig?

    init(row: LovelaceEntityRowConfig) {
        switch row {
        case let .entity(entityID):
            self.entityID = entityID
            self.name = nil
            self.icon = nil
            self.type = nil
            self.secondaryInfo = nil
            self.stateColor = nil
            self.showName = true
            self.showIcon = true
            self.tapAction = nil
            self.holdAction = nil
            self.doubleTapAction = nil
        case let .config(config):
            self.entityID = config.entity
            self.name = config.name
            self.icon = config.icon
            self.type = config.type
            self.secondaryInfo = config.secondaryInfo
            self.stateColor = config.stateColor
            self.showName = config.showName ?? true
            self.showIcon = config.showIcon ?? true
            self.tapAction = config.tapAction
            self.holdAction = config.holdAction
            self.doubleTapAction = config.doubleTapAction
        }
    }
}
