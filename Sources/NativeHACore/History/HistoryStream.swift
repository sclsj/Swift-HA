import Foundation

public final class HistoryStream {
    public var hoursToShow: Double?
    public private(set) var combinedHistory: HistoryStates

    private let now: () -> Date

    public init(
        hoursToShow: Double? = nil,
        combinedHistory: HistoryStates = [:],
        now: @escaping () -> Date = Date.init
    ) {
        self.hoursToShow = hoursToShow
        self.combinedHistory = combinedHistory
        self.now = now
    }

    @discardableResult
    public func processMessage(_ streamMessage: HistoryStreamMessage) -> HistoryStates {
        if combinedHistory.isEmpty {
            combinedHistory = streamMessage.states
            return combinedHistory
        }

        if streamMessage.states.isEmpty {
            return combinedHistory
        }

        let purgeBefore = hoursToShow.map {
            now().timeIntervalSince1970 - 60 * 60 * $0
        }
        let streamStates = streamMessage.states
        var newHistory: HistoryStates = [:]

        func processEntity(_ entityID: EntityID) {
            let combinedStates = combinedHistory[entityID]
            let incomingStates = streamStates[entityID]

            if let combinedStates = combinedStates, let incomingStates = incomingStates {
                var merged = combinedStates + incomingStates
                if let firstIncoming = incomingStates.first,
                   let lastCombined = combinedStates.last,
                   firstIncoming.lastUpdated < lastCombined.lastUpdated {
                    merged = stableSortByLastUpdated(merged)
                }
                newHistory[entityID] = merged
            } else if let combinedStates = combinedStates {
                newHistory[entityID] = combinedStates
            } else if let incomingStates = incomingStates {
                // Matches the frontend stream-only branch: brand-new entities
                // are accepted as sent and will be purged on a later update.
                newHistory[entityID] = incomingStates
                return
            } else {
                return
            }

            guard let purgeBefore = purgeBefore, let states = newHistory[entityID] else {
                return
            }

            var kept: [EntityHistoryState] = []
            kept.reserveCapacity(states.count)
            var lastExpiredState: EntityHistoryState?

            for state in states {
                if state.lastUpdated < purgeBefore {
                    lastExpiredState = state
                } else {
                    kept.append(state)
                }
            }

            guard var boundaryState = lastExpiredState else {
                return
            }

            newHistory[entityID] = kept
            if kept.first?.lastUpdated == purgeBefore {
                return
            }

            boundaryState.lastUpdated = purgeBefore
            boundaryState.lastChanged = nil
            kept.insert(boundaryState, at: 0)
            newHistory[entityID] = kept
        }

        for entityID in combinedHistory.keys {
            processEntity(entityID)
        }

        for entityID in streamStates.keys where combinedHistory[entityID] == nil {
            processEntity(entityID)
        }

        combinedHistory = newHistory
        return combinedHistory
    }

    private func stableSortByLastUpdated(_ states: [EntityHistoryState]) -> [EntityHistoryState] {
        states.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.lastUpdated == rhs.element.lastUpdated {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.lastUpdated < rhs.element.lastUpdated
            }
            .map(\.element)
    }
}
