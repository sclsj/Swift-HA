import NativeHACore
import SwiftUI

struct WeatherForecastCardView: View {
    let config: WeatherForecastCardConfig
    let displayContext: EntityDisplayContext
    var onMoreInfo: (EntityID) -> Void = { _ in }
    var onServiceCall: (HAServiceCall) -> Void = { _ in }
    var onNavigate: (String, Bool) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        guard let entityID = config.entity, !entityID.isEmpty else {
            return AnyView(CardWarningView(title: "Weather entity missing", detail: nil))
        }

        guard let stateObj = displayContext.states[entityID] else {
            return AnyView(CardWarningView(title: "Entity not found", detail: entityID))
        }

        if stateObj.state == HAStateValue.unavailable {
            return AnyView(CardWarningView(
                title: "Weather unavailable",
                detail: "\(displayContext.displayName(for: stateObj, overrideName: config.name)) (\(entityID))"
            ))
        }

        return AnyView(weatherContent(stateObj))
    }

    private func weatherContent(_ stateObj: HassEntity) -> some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: Self.symbol(forWeatherState: stateObj.state))
                        .font(.system(size: 34, weight: .regular))
                        .foregroundColor(weatherColor(for: stateObj))
                        .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayContext.stateDisplay(for: stateObj).capitalized)
                            .font(.title3)
                            .lineLimit(1)
                        Text(displayContext.displayName(for: stateObj, overrideName: config.name))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let temperature = weatherAttribute("temperature", stateObj: stateObj) {
                        Text(temperature)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }

                let attributes = weatherAttributes(for: stateObj)
                if !attributes.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 115), spacing: 8, alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(attributes, id: \.name) { attribute in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attribute.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(attribute.value)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if config.showForecast != false {
                    Text("Forecast unavailable in this native preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            CardActionDispatcher(
                entityID: stateObj.entityID,
                states: displayContext.states,
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
        }
    }

    private func weatherColor(for stateObj: HassEntity) -> Color {
        guard let stateColor = HAStateColorResolver.color(for: stateObj) else {
            return .accentColor
        }
        return Color(haHex: stateColor.hex) ?? .accentColor
    }

    private func weatherAttributes(for stateObj: HassEntity) -> [WeatherAttributeDisplay] {
        let keys = [
            "humidity",
            "pressure",
            "wind_speed",
            "wind_bearing",
            "visibility",
            "precipitation"
        ]

        return keys.compactMap { key in
            guard stateObj.attributes[key] != nil else {
                return nil
            }
            return WeatherAttributeDisplay(
                name: HAEntityFormatting.attributeNameDisplay(key),
                value: weatherAttribute(key, stateObj: stateObj)
                    ?? HAEntityFormatting.attributeDisplay(for: stateObj, attribute: key, config: displayContext.config)
            )
        }
    }

    private func weatherAttribute(_ attribute: String, stateObj: HassEntity) -> String? {
        guard stateObj.attributes[attribute] != nil else {
            return nil
        }
        return HAEntityFormatting.attributeDisplay(
            for: stateObj,
            attribute: attribute,
            config: displayContext.config
        )
    }

    static func symbol(forWeatherState state: String) -> String {
        switch state {
        case "clear-night":
            return "moon.stars"
        case "cloudy", "fog", "partlycloudy":
            return "cloud"
        case "hail", "snowy", "snowy-rainy":
            return "cloud.snow"
        case "lightning", "lightning-rainy":
            return "cloud.bolt"
        case "pouring", "rainy":
            return "cloud.rain"
        case "sunny":
            return "sun.max"
        case "windy", "windy-variant":
            return "wind"
        default:
            return "cloud.sun"
        }
    }
}

private struct WeatherAttributeDisplay: Equatable {
    var name: String
    var value: String
}
