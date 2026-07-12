import NativeHACore
import SwiftUI

struct EntitiesCardView: View {
    let config: EntitiesCardConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 10) {
                if shouldShowHeader {
                    header
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(config.entities.enumerated()), id: \.offset) { _, row in
                        EntityRowView(
                            row: row,
                            displayContext: displayContext,
                            inheritedStateColor: config.stateColor,
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

    private var shouldShowHeader: Bool {
        (config.title?.isEmpty == false) || (config.icon?.isEmpty == false) || Self.computeShowHeaderToggle(config)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = config.icon, !icon.isEmpty {
                LovelaceIconView(entityID: nil, icon: icon, size: 17)
            }

            if let title = config.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if Self.computeShowHeaderToggle(config) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { allToggleRowsOn },
                        set: { turnOn in setAllToggleRows(turnOn: turnOn) }
                    )
                )
                .labelsHidden()
            }
        }
    }

    private var toggleableEntityIDs: [EntityID] {
        config.entities.compactMap { row in
            guard let entityID = row.entity else {
                return nil
            }
            let domain = EntityIDParser.domain(from: entityID)
            return Self.toggleableDomains.contains(domain) ? entityID : nil
        }
    }

    private var allToggleRowsOn: Bool {
        let toggleRows = toggleableEntityIDs.compactMap { displayContext.states[$0] }
        guard !toggleRows.isEmpty else {
            return false
        }
        return toggleRows.allSatisfy { $0.state == "on" }
    }

    private func setAllToggleRows(turnOn: Bool) {
        for entityID in toggleableEntityIDs {
            onServiceCall(LovelaceActionResolver.serviceCallForTurnOnOff(
                entityID: entityID,
                turnOn: turnOn
            ))
        }
    }

    static let toggleableDomains: Set<String> = [
        "automation",
        "fan",
        "group",
        "humidifier",
        "input_boolean",
        "light",
        "switch",
        "valve"
    ]

    static func computeShowHeaderToggle(_ config: EntitiesCardConfig) -> Bool {
        if let showHeaderToggle = config.showHeaderToggle {
            return showHeaderToggle
        }

        guard config.title != nil else {
            return false
        }

        var toggleableCount = 0
        for row in config.entities {
            guard let entityID = row.entity else {
                continue
            }
            if toggleableDomains.contains(EntityIDParser.domain(from: entityID)) {
                toggleableCount += 1
                if toggleableCount == 2 {
                    return true
                }
            }
        }

        return false
    }
}
