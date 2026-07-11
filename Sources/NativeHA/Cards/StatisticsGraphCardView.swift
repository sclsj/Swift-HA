import Foundation
import NativeHACore
import SwiftUI

struct StatisticsGraphChartData: Equatable {
    var visibleRange: ChartVisibleRange
    var series: LineSeriesBuildResult

    var isEmpty: Bool {
        series.series.isEmpty
    }
}

enum StatisticsGraphEmptyReason: Equatable {
    case noEntities
    case historyDisabled
    case noData

    var message: String {
        switch self {
        case .noEntities:
            return "No statistics entities configured."
        case .historyDisabled:
            return "History is disabled."
        case .noData:
            return "No statistics found."
        }
    }
}

enum StatisticsGraphCardPhase: Equatable {
    case idle
    case loading
    case empty(StatisticsGraphEmptyReason)
    case loaded(StatisticsGraphChartData)
    case error(String)
}

@MainActor
final class StatisticsGraphCardViewModel: ObservableObject {
    @Published private(set) var phase: StatisticsGraphCardPhase = .idle

    private let now: () -> Date
    private var activeConfigurationKey: String?
    private var generation = 0
    private var loadTask: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func start(
        model: StatisticsGraphCardModel,
        provider: StatisticsGraphDataProviding?,
        displayContext: EntityDisplayContext
    ) {
        guard displayContext.config?.components.contains("history") != false else {
            cancel()
            phase = .empty(.historyDisabled)
            return
        }

        guard !model.entityIDs.isEmpty else {
            cancel()
            phase = .empty(.noEntities)
            return
        }

        guard let provider = provider else {
            cancel()
            phase = .error("Statistics data provider is unavailable.")
            return
        }

        guard activeConfigurationKey != model.configurationKey else {
            return
        }

        cancel()
        activeConfigurationKey = model.configurationKey
        generation += 1
        let currentGeneration = generation

        loadTask = Task { [weak self] in
            await self?.load(
                model: model,
                provider: provider,
                displayContext: displayContext,
                generation: currentGeneration,
                markLoading: true
            )
        }
    }

    func load(
        model: StatisticsGraphCardModel,
        provider: StatisticsGraphDataProviding,
        displayContext: EntityDisplayContext
    ) async {
        await load(
            model: model,
            provider: provider,
            displayContext: displayContext,
            generation: nil,
            markLoading: true
        )
    }

    func cancel() {
        generation += 1
        activeConfigurationKey = nil
        loadTask?.cancel()
        loadTask = nil
        if case .loading = phase {
            phase = .idle
        }
    }

    private func load(
        model: StatisticsGraphCardModel,
        provider: StatisticsGraphDataProviding,
        displayContext: EntityDisplayContext,
        generation: Int?,
        markLoading: Bool
    ) async {
        guard !model.entityIDs.isEmpty else {
            phase = .empty(.noEntities)
            return
        }

        if markLoading {
            phase = .loading
        }

        let endTime = now()
        let fetchWindow = model.fetchWindow(endingAt: endTime)

        do {
            let metadata = try await provider.fetchStatisticMetadata(statisticIDs: model.entityIDs)
            try Task.checkCancellation()
            let statistics = try await provider.fetchStatistics(
                startTime: fetchWindow.start,
                endTime: fetchWindow.end,
                statisticIDs: model.entityIDs,
                period: model.period,
                types: model.statTypes
            )
            try Task.checkCancellation()

            let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.statisticID, $0) })
            let builtSeries = StatisticsSeriesBuilder.buildSeries(
                statistics: statistics,
                metadata: metadataByID,
                statisticIDs: model.entityIDs,
                statTypes: model.statTypes,
                chartType: model.chartType,
                names: model.displayNames,
                colors: model.colors,
                currentStates: displayContext.states,
                endTime: fetchWindow.end.timeIntervalSince1970 * 1_000,
                now: endTime.timeIntervalSince1970 * 1_000
            )
            let chartData = StatisticsGraphChartData(
                visibleRange: model.visibleRange(endingAt: endTime),
                series: builtSeries
            )

            guard shouldApplyResult(generation: generation) else {
                return
            }
            phase = chartData.isEmpty ? .empty(.noData) : .loaded(chartData)
        } catch is CancellationError {
        } catch {
            guard shouldApplyResult(generation: generation) else {
                return
            }
            phase = .error(Self.errorMessage(error))
        }
    }

    private func shouldApplyResult(generation: Int?) -> Bool {
        guard let generation = generation else {
            return !Task.isCancelled
        }
        return generation == self.generation && !Task.isCancelled
    }

    private static func errorMessage(_ error: Error) -> String {
        if let websocketError = error as? HAWebSocketClientError {
            switch websocketError {
            case let .requestFailed(payload):
                return payload.message
            default:
                return String(describing: websocketError)
            }
        }
        return String(describing: error)
    }
}

struct StatisticsGraphCardView: View {
    let config: StatisticsGraphCardConfig
    let displayContext: EntityDisplayContext

    @Environment(\.statisticsGraphDataProvider) private var statisticsProvider
    @StateObject private var viewModel = StatisticsGraphCardViewModel()

    private var model: StatisticsGraphCardModel {
        StatisticsGraphCardModel(config: config, displayContext: displayContext)
    }

    private var taskKey: String {
        "\(model.configurationKey)|provider:\(statisticsProvider == nil ? "missing" : "ready")"
    }

    var body: some View {
        let model = model

        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                if let title = model.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                }

                content(for: viewModel.phase, model: model)
            }
        }
        .task(id: taskKey) {
            viewModel.start(
                model: model,
                provider: statisticsProvider,
                displayContext: displayContext
            )
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    @ViewBuilder
    private func content(
        for phase: StatisticsGraphCardPhase,
        model: StatisticsGraphCardModel
    ) -> some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading statistics")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
        case let .empty(reason):
            Text(reason.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
        case let .error(message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        case let .loaded(chartData):
            LineHistoryChartView(
                series: chartData.series.series,
                yAxisMetadata: chartData.series.yAxis,
                initialVisibleRange: chartData.visibleRange,
                fixedMinimumY: model.minYAxis,
                fixedMaximumY: model.maxYAxis,
                minimumHeight: 180
            )
        }
    }
}
