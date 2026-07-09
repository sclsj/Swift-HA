import NativeHACore
import SwiftUI

enum HAStyleTokens {
    static let space2: CGFloat = 8
    static let space4: CGFloat = 16

    static let cardCornerRadius: CGFloat = 12
    static let cardBorderWidth: CGFloat = 1
    static let cardContentInsets = EdgeInsets(
        top: space4,
        leading: space4,
        bottom: space4,
        trailing: space4
    )

    static let entityIconColumnWidth: CGFloat = 40
    static let entityRowMinimumHeight: CGFloat = 40
    static let tileMinimumHeight: CGFloat = 56
    static let tileIconSize: CGFloat = 36
    static let tileHorizontalInset: CGFloat = 10

    static let cardBorderColor = Color.primary.opacity(0.12)
    static let rowHoverColor = Color.primary.opacity(0.04)
    static let inactiveControlFillOpacity = 0.12
    static let activeControlFillOpacity = 0.20

    static var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

struct EntityDisplayContext {
    var states: [EntityID: HassEntity]
    var config: HAConfig?
    var registryEntries: [EntityID: HAEntityRegistryDisplayEntry]

    init(
        states: [EntityID: HassEntity] = [:],
        config: HAConfig? = nil,
        registryEntries: [EntityID: HAEntityRegistryDisplayEntry] = [:]
    ) {
        self.states = states
        self.config = config
        self.registryEntries = registryEntries
    }

    static let empty = EntityDisplayContext()

    func stateDisplay(for stateObj: HassEntity) -> String {
        HAEntityFormatting.stateDisplay(
            for: stateObj,
            registryEntry: registryEntries[stateObj.entityID],
            config: config
        )
    }

    func defaultStateContentDisplay(for stateObj: HassEntity) -> String {
        HAEntityFormatting.defaultStateContentDisplay(
            for: stateObj,
            registryEntry: registryEntries[stateObj.entityID],
            config: config
        )
    }

    func stateContentDisplay(_ content: String, for stateObj: HassEntity) -> String? {
        HAEntityFormatting.stateContentDisplay(
            content,
            for: stateObj,
            registryEntry: registryEntries[stateObj.entityID],
            config: config
        )
    }

    func displayName(for stateObj: HassEntity, overrideName: String? = nil) -> String {
        HAEntityFormatting.displayName(for: stateObj, overrideName: overrideName)
    }
}

struct CardActionDispatcher {
    var entityID: EntityID?
    var states: [EntityID: HassEntity]
    var onMoreInfo: (EntityID) -> Void
    var onServiceCall: (HAServiceCall) -> Void

    func perform(
        gesture: LovelaceActionGesture = .tap,
        tapAction: LovelaceActionConfig? = nil,
        holdAction: LovelaceActionConfig? = nil,
        doubleTapAction: LovelaceActionConfig? = nil
    ) {
        let resolved = LovelaceActionResolver.resolve(
            gesture: gesture,
            tapAction: tapAction,
            holdAction: holdAction,
            doubleTapAction: doubleTapAction,
            context: LovelaceActionResolutionContext(entity: entityID, states: states)
        )
        perform(resolved)
    }

    func perform(_ action: LovelaceResolvedAction) {
        switch action {
        case let .moreInfo(entityID):
            onMoreInfo(entityID)
        case let .callService(call):
            onServiceCall(call)
        default:
            break
        }
    }
}

struct EntityNotFoundWarningRow: View {
    var entityID: EntityID?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Entity not found")
                    .font(.subheadline)
                if let entityID = entityID, !entityID.isEmpty {
                    Text(entityID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardWarningView: View {
    var title: String
    var detail: String?

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(title)
                        .font(.headline)
                }
                if let detail = detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct LovelaceIconView: View {
    var entityID: EntityID?
    var icon: String?
    var color: Color?
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(color ?? .secondary)
            .frame(width: size + 8, height: size + 8)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        if let icon = icon, let mapped = Self.symbol(forIcon: icon) {
            return mapped
        }
        return Self.symbol(forDomain: entityID.map(EntityIDParser.domain(from:)))
    }

    static func symbol(forDomain domain: String?) -> String {
        switch domain {
        case "binary_sensor":
            return "circle.lefthalf.filled"
        case "button", "input_button":
            return "button.programmable"
        case "climate":
            return "thermometer.medium"
        case "fan":
            return "fanblades"
        case "light":
            return "lightbulb"
        case "person", "device_tracker":
            return "person.circle"
        case "sensor":
            return "waveform.path.ecg"
        case "switch":
            return "power"
        case "weather":
            return "cloud.sun"
        default:
            return "circle"
        }
    }

    static func symbol(forIcon icon: String) -> String? {
        switch icon {
        case "mdi:fan":
            return "fanblades"
        case "mdi:fridge":
            return "refrigerator"
        case "mdi:lightbulb":
            return "lightbulb"
        case "mdi:power", "mdi:power-plug":
            return "power"
        case "mdi:thermometer":
            return "thermometer.medium"
        case "mdi:weather-rainy":
            return "cloud.rain"
        case "mdi:weather-sunny":
            return "sun.max"
        default:
            return nil
        }
    }
}

extension Color {
    init?(haHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

extension HAJSONValue {
    var nativeScalarString: String? {
        switch self {
        case let .string(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null, .array, .object:
            return nil
        }
    }
}
