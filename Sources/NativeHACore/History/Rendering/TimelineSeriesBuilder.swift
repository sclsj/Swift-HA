import Foundation

public enum TimelineSeriesBuilder {
    public static let defaultPalette = LineSeriesBuilder.defaultPalette
    public static let unknownColor = "#9e9e9e"
    public static let unavailableColor = HAStateColorResolver.unavailable.hex

    public static func buildRows(
        from entities: [TimelineEntity],
        endTime: Double,
        currentStates: [EntityID: HassEntity] = [:],
        palette: [String] = defaultPalette
    ) -> TimelineSeriesBuildResult {
        var colorAllocator = TimelineColorAllocator(palette: palette)
        var rows: [TimelineRow] = []
        var legendByKey: [String: LegendItem] = [:]
        var legendOrder: [String] = []

        for entity in entities {
            let states = entity.data.filter { $0.lastChanged <= endTime }
            guard !states.isEmpty else {
                continue
            }

            var segments: [TimelineSegment] = []
            segments.reserveCapacity(states.count)
            for index in states.indices {
                let state = states[index]
                let start = state.lastChanged
                let nextStart = states.index(after: index) < states.endIndex
                    ? states[states.index(after: index)].lastChanged
                    : endTime
                let end = min(nextStart, endTime)
                guard start <= end else {
                    continue
                }

                let color = colorAllocator.color(
                    state: state.state,
                    entityID: entity.entityID,
                    currentState: currentStates[entity.entityID]
                )
                segments.append(TimelineSegment(
                    start: start,
                    end: end,
                    state: state.state,
                    stateLocalized: state.stateLocalized,
                    colorHex: color.hex,
                    colorName: color.name
                ))

                let legendKey = "\(entity.entityID)|\(state.state)"
                if legendByKey[legendKey] == nil {
                    legendOrder.append(legendKey)
                    legendByKey[legendKey] = LegendItem(
                        id: legendKey,
                        entityID: entity.entityID,
                        label: state.stateLocalized,
                        colorHex: color.hex,
                        seriesIDs: [entity.entityID]
                    )
                }
            }

            rows.append(TimelineRow(
                entityID: entity.entityID,
                name: entity.name,
                segments: segments
            ))
        }

        return TimelineSeriesBuildResult(
            rows: rows,
            legendItems: legendOrder.compactMap { legendByKey[$0] }
        )
    }
}

private struct TimelineColor {
    var name: String?
    var hex: String
}

private struct TimelineColorAllocator {
    private var palette: [String]
    private var index = 0
    private var genericColors: [String: TimelineColor] = [:]

    init(palette: [String]) {
        self.palette = palette.isEmpty ? TimelineSeriesBuilder.defaultPalette : palette
    }

    mutating func color(
        state: String,
        entityID: EntityID,
        currentState: HassEntity?
    ) -> TimelineColor {
        if state == HAStateValue.unavailable {
            return TimelineColor(name: "state-unavailable", hex: TimelineSeriesBuilder.unavailableColor)
        }
        if state == HAStateValue.unknown {
            return TimelineColor(name: "state-unknown", hex: TimelineSeriesBuilder.unknownColor)
        }
        if let currentState = currentState,
           let color = HAStateColorResolver.color(for: currentState, state: state) {
            return TimelineColor(name: color.name, hex: color.hex)
        }

        let key = "\(entityID)|\(state)"
        if let color = genericColors[key] {
            return color
        }

        let color = TimelineColor(name: nil, hex: palette[index % palette.count])
        index += 1
        genericColors[key] = color
        return color
    }
}
