import NativeHACore
import SwiftUI

struct HistoryGraphLineChartData: Equatable {
    var unit: LineChartUnit
    var series: LineSeriesBuildResult
}

struct HistoryGraphTimelineChartData: Equatable {
    var series: TimelineSeriesBuildResult
}

struct HistoryGraphChartData: Equatable {
    var visibleRange: ChartVisibleRange
    var lineCharts: [HistoryGraphLineChartData]
    var timelineChart: HistoryGraphTimelineChartData?

    var isEmpty: Bool {
        lineCharts.allSatisfy { $0.series.series.isEmpty }
            && (timelineChart?.series.rows.isEmpty ?? true)
    }
}

enum HistoryGraphEmptyReason: Equatable {
    case noEntities
    case historyDisabled
    case noData

    var message: String {
        switch self {
        case .noEntities:
            return "No history entities configured."
        case .historyDisabled:
            return "History is disabled."
        case .noData:
            return "No history found."
        }
    }
}

enum HistoryGraphCardPhase: Equatable {
    case idle
    case loading
    case empty(HistoryGraphEmptyReason)
    case loaded(HistoryGraphChartData)
    case error(String)
}

@MainActor
final class HistoryGraphCardViewModel: ObservableObject {
    typealias Sleep = (UInt64) async throws -> Void

    @Published private(set) var phase: HistoryGraphCardPhase = .idle
    private(set) var refreshLoopStartCount = 0

    private let now: () -> Date
    private let sleep: Sleep
    private var activeConfigurationKey: String?
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    var hasScheduledRefresh: Bool {
        refreshTask != nil
    }

    func start(
        model: HistoryGraphCardModel,
        provider: HistoryGraphDataProviding?,
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
            phase = .error("History data provider is unavailable.")
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

        if let interval = model.refreshIntervalSeconds {
            refreshLoopStartCount += 1
            refreshTask = Task { [weak self] in
                await self?.runRefreshLoop(
                    interval: interval,
                    model: model,
                    provider: provider,
                    displayContext: displayContext,
                    generation: currentGeneration
                )
            }
        }
    }

    func load(
        model: HistoryGraphCardModel,
        provider: HistoryGraphDataProviding,
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
        refreshTask?.cancel()
        loadTask = nil
        refreshTask = nil
        if case .loading = phase {
            phase = .idle
        }
    }

    private func runRefreshLoop(
        interval: Double,
        model: HistoryGraphCardModel,
        provider: HistoryGraphDataProviding,
        displayContext: EntityDisplayContext,
        generation: Int
    ) async {
        let nanoseconds = UInt64(interval * 1_000_000_000)

        while !Task.isCancelled, generation == self.generation {
            do {
                try await sleep(nanoseconds)
            } catch {
                break
            }

            guard !Task.isCancelled, generation == self.generation else {
                break
            }

            await load(
                model: model,
                provider: provider,
                displayContext: displayContext,
                generation: generation,
                markLoading: false
            )
        }
    }

    private func load(
        model: HistoryGraphCardModel,
        provider: HistoryGraphDataProviding,
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
            let history = try await provider.fetchHistory(
                startTime: fetchWindow.start,
                endTime: fetchWindow.end,
                entityIDs: model.entityIDs,
                currentStates: displayContext.states
            )
            try Task.checkCancellation()

            let processingContext = HistoryProcessingContext(
                states: displayContext.states,
                config: displayContext.config,
                registryEntries: displayContext.registryEntries
            )
            let stateHistory = HistoryProcessor.computeHistory(
                stateHistory: history,
                entityIDs: model.entityIDs,
                context: processingContext,
                splitDeviceClasses: model.splitDeviceClasses
            )

            let statisticsHistory: HistoryResult?
            if let statisticsWindow = model.statisticsWindow(endingAt: endTime) {
                do {
                    let statistics = try await provider.fetchStatistics(
                        startTime: statisticsWindow.start,
                        endTime: statisticsWindow.end,
                        statisticIDs: model.entityIDs
                    )
                    try Task.checkCancellation()
                    statisticsHistory = HistoryProcessor.convertStatisticsToHistory(
                        statistics: statistics,
                        statisticIDs: model.entityIDs,
                        context: processingContext,
                        splitDeviceClasses: model.splitDeviceClasses
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    statisticsHistory = nil
                }
            } else {
                statisticsHistory = nil
            }

            let mergedHistory = HistoryProcessor.mergeHistoryResults(
                historyResult: stateHistory,
                longTermStatisticsResult: statisticsHistory,
                splitDeviceClasses: model.splitDeviceClasses
            )
            let chartData = Self.chartData(
                from: mergedHistory,
                model: model,
                displayContext: displayContext,
                endTime: endTime
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

    private static func chartData(
        from history: HistoryResult,
        model: HistoryGraphCardModel,
        displayContext: EntityDisplayContext,
        endTime: Date
    ) -> HistoryGraphChartData {
        let endMilliseconds = endTime.timeIntervalSince1970 * 1_000
        let visibleRange = model.visibleRange(endingAt: endTime)

        let lineCharts = history.line.compactMap { unit -> HistoryGraphLineChartData? in
            let builtSeries = LineSeriesBuilder.buildSeries(
                for: unit,
                endTime: endMilliseconds,
                now: endMilliseconds,
                currentStates: displayContext.states,
                names: model.displayNames,
                colors: model.colors,
                showNames: model.showNames
            )
            guard !builtSeries.series.isEmpty else {
                return nil
            }
            return HistoryGraphLineChartData(unit: unit, series: builtSeries)
        }

        let timelineEntities = history.timeline.map { entity -> TimelineEntity in
            var entity = entity
            if let name = model.displayNames[entity.entityID] {
                entity.name = name
            }
            return entity
        }
        let timelineSeries = TimelineSeriesBuilder.buildRows(
            from: timelineEntities,
            endTime: endMilliseconds,
            currentStates: displayContext.states
        )
        let timelineChart = timelineSeries.rows.isEmpty
            ? nil
            : HistoryGraphTimelineChartData(series: timelineSeries)

        return HistoryGraphChartData(
            visibleRange: visibleRange,
            lineCharts: lineCharts,
            timelineChart: timelineChart
        )
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

struct HistoryGraphCardView: View {
    let config: HistoryGraphCardConfig
    let displayContext: EntityDisplayContext

    @Environment(\.historyGraphDataProvider) private var historyProvider
    @StateObject private var viewModel = HistoryGraphCardViewModel()

    private var model: HistoryGraphCardModel {
        HistoryGraphCardModel(config: config, displayContext: displayContext)
    }

    private var taskKey: String {
        "\(model.configurationKey)|provider:\(historyProvider == nil ? "missing" : "ready")"
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
                provider: historyProvider,
                displayContext: displayContext
            )
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    @ViewBuilder
    private func content(
        for phase: HistoryGraphCardPhase,
        model: HistoryGraphCardModel
    ) -> some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading history")
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
            chartContent(chartData, model: model)
        }
    }

    @ViewBuilder
    private func chartContent(
        _ chartData: HistoryGraphChartData,
        model: HistoryGraphCardModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let timelineChart = chartData.timelineChart {
                TimelineHistoryChartView(
                    rows: timelineChart.series.rows,
                    initialVisibleRange: chartData.visibleRange,
                    showRowLabels: model.showNames,
                    showSegmentLabels: true,
                    minimumHeight: max(86, CGFloat(timelineChart.series.rows.count) * 30 + 34)
                )
            }

            ForEach(Array(chartData.lineCharts.enumerated()), id: \.offset) { _, chart in
                LineHistoryChartView(
                    series: chart.series.series,
                    yAxisMetadata: chart.series.yAxis,
                    initialVisibleRange: chartData.visibleRange,
                    fixedMinimumY: model.minYAxis,
                    fixedMaximumY: model.maxYAxis,
                    fitYData: model.fitYData,
                    logarithmicScale: model.logarithmicScale,
                    minimumHeight: 180
                )
            }
        }
    }
}
