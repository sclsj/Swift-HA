import Combine
import Foundation

public protocol LovelaceUpdateSubscription {
    func cancel()
}

extension HASubscription: LovelaceUpdateSubscription {}

public protocol LovelaceUpdateEventSource {
    func subscribeLovelaceUpdates(
        onUpdate: @escaping (LovelaceUpdateEvent) -> Void
    ) async throws -> LovelaceUpdateSubscription
}

public struct LovelaceUpdateEvent: Equatable {
    public var dashboardPath: String?
    public var mode: String?

    public init(urlPath: String?, mode: String? = nil) {
        if let urlPath = urlPath?.trimmingCharacters(in: .whitespacesAndNewlines), !urlPath.isEmpty {
            dashboardPath = AppRoute.dashboardPath(urlPath)
        } else {
            dashboardPath = nil
        }
        self.mode = mode
    }

    public func matches(dashboardPath: String) -> Bool {
        let normalizedDashboardPath = AppRoute.dashboardPath(dashboardPath)
        if let eventDashboardPath = self.dashboardPath {
            return AppRoute.dashboardPath(eventDashboardPath) == normalizedDashboardPath
        }

        return normalizedDashboardPath == "/lovelace"
    }
}

public struct PlaceholderLovelaceUpdateEventSource: LovelaceUpdateEventSource {
    public init() {}

    public func subscribeLovelaceUpdates(
        onUpdate: @escaping (LovelaceUpdateEvent) -> Void
    ) async throws -> LovelaceUpdateSubscription {
        LovelaceNoopUpdateSubscription()
    }
}

public struct LovelaceNoopUpdateSubscription: LovelaceUpdateSubscription {
    public init() {}

    public func cancel() {}
}

public final class HALovelaceUpdateEventSource: LovelaceUpdateEventSource {
    private let clientResolver: () throws -> HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.clientResolver = { client }
    }

    public init(connection: HAConnection) {
        self.clientResolver = { [weak connection] in
            guard let client = connection?.client else {
                throw HAWebSocketClientError.disconnected
            }
            return client
        }
    }

    public func subscribeLovelaceUpdates(
        onUpdate: @escaping (LovelaceUpdateEvent) -> Void
    ) async throws -> LovelaceUpdateSubscription {
        let subscription: HASubscription = try await clientResolver().subscribe(
            HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("lovelace_updated")])
        ) { (event: HAEvent<HALovelaceUpdatedEventData>) in
            guard event.eventType == "lovelace_updated" else {
                return
            }
            onUpdate(LovelaceUpdateEvent(urlPath: event.data.urlPath, mode: event.data.mode))
        }
        return subscription
    }
}

private struct HALovelaceUpdatedEventData: Decodable {
    var urlPath: String?
    var mode: String?

    enum CodingKeys: String, CodingKey {
        case urlPath = "url_path"
        case mode
    }
}

public struct LovelaceDashboardContent: Equatable {
    public var dashboardPath: String
    public var rawJSON: String?
    public var rawConfig: LovelaceRawConfig
    public var config: LovelaceConfig
    public var selectedRoute: LovelaceViewRoute
    public var selectedView: LovelaceViewConfig?
    public var dashboards: [LovelaceDashboardReference]
    public var loadedAt: Date?

    public init(
        dashboardPath: String,
        rawJSON: String?,
        rawConfig: LovelaceRawConfig,
        config: LovelaceConfig,
        selectedRoute: LovelaceViewRoute,
        selectedView: LovelaceViewConfig?,
        dashboards: [LovelaceDashboardReference],
        loadedAt: Date? = nil
    ) {
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.rawJSON = rawJSON
        self.rawConfig = rawConfig
        self.config = config
        self.selectedRoute = selectedRoute
        self.selectedView = selectedView
        self.dashboards = dashboards
        self.loadedAt = loadedAt
    }
}

public struct LovelaceStrategyPlaceholder: Equatable {
    public var dashboardPath: String
    public var rawJSON: String?
    public var rawConfig: LovelaceRawConfig
    public var strategy: LovelaceStrategyConfig
    public var requestedViewPath: String?
    public var requestedViewIndex: Int?
    public var dashboards: [LovelaceDashboardReference]
    public var loadedAt: Date?

    public init(
        dashboardPath: String,
        rawJSON: String?,
        rawConfig: LovelaceRawConfig,
        strategy: LovelaceStrategyConfig,
        requestedViewPath: String? = nil,
        requestedViewIndex: Int? = nil,
        dashboards: [LovelaceDashboardReference],
        loadedAt: Date? = nil
    ) {
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.rawJSON = rawJSON
        self.rawConfig = rawConfig
        self.strategy = strategy
        self.requestedViewPath = requestedViewPath
        self.requestedViewIndex = requestedViewIndex
        self.dashboards = dashboards
        self.loadedAt = loadedAt
    }
}

public struct LovelaceDashboardError: Equatable {
    public var dashboardPath: String
    public var message: String

    public init(dashboardPath: String, message: String) {
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.message = message
    }
}

public enum LovelaceStoreState: Equatable {
    case idle
    case loading(dashboardPath: String)
    case loaded(LovelaceDashboardContent)
    case error(LovelaceDashboardError)
    case generatedStrategyPlaceholder(LovelaceStrategyPlaceholder)

    public var loadedDashboard: LovelaceDashboardContent? {
        guard case let .loaded(content) = self else {
            return nil
        }
        return content
    }

    public var strategyPlaceholder: LovelaceStrategyPlaceholder? {
        guard case let .generatedStrategyPlaceholder(placeholder) = self else {
            return nil
        }
        return placeholder
    }
}

public enum LovelaceStoreError: Error, Equatable {
    case missingConfiguration(String)
}

@MainActor
public final class LovelaceStore: ObservableObject {
    @Published public private(set) var state: LovelaceStoreState
    @Published public private(set) var dashboards: [LovelaceDashboardReference]
    @Published public private(set) var currentDashboardPath: String

    private let configProvider: LovelaceConfigProvider
    private let updateEventSource: LovelaceUpdateEventSource
    private let router: LovelaceRouter
    private let clock: Clock?
    private let logger: Logger?

    private var requestedViewPath: String?
    private var requestedViewIndex: Int?
    private var updateSubscription: LovelaceUpdateSubscription?

    public init(
        configProvider: LovelaceConfigProvider,
        updateEventSource: LovelaceUpdateEventSource = PlaceholderLovelaceUpdateEventSource(),
        router: LovelaceRouter = LovelaceRouter(),
        clock: Clock? = nil,
        logger: Logger? = nil
    ) {
        self.configProvider = configProvider
        self.updateEventSource = updateEventSource
        self.router = router
        self.clock = clock
        self.logger = logger
        self.state = .idle
        self.dashboards = []
        self.currentDashboardPath = "/lovelace"
    }

    public convenience init(environment: AppEnvironment) {
        self.init(
            configProvider: environment.lovelaceConfigProvider,
            updateEventSource: environment.lovelaceUpdateEventSource,
            clock: environment.clock,
            logger: environment.logger
        )
    }

    deinit {
        updateSubscription?.cancel()
    }

    public func load(
        dashboardPath: String,
        viewPath: String? = nil,
        viewIndex: Int? = nil
    ) async {
        let normalizedDashboardPath = AppRoute.dashboardPath(dashboardPath)
        currentDashboardPath = normalizedDashboardPath
        requestedViewPath = viewPath
        requestedViewIndex = viewIndex
        state = .loading(dashboardPath: normalizedDashboardPath)

        await ensureUpdateSubscription()

        do {
            let fetchedDashboards = try await configProvider.dashboardList()
            dashboards = fetchedDashboards

            let configuration = try await configProvider.configuration(for: normalizedDashboardPath)
            try apply(
                configuration: configuration,
                dashboardPath: normalizedDashboardPath,
                dashboards: fetchedDashboards,
                viewPath: viewPath,
                viewIndex: viewIndex
            )
        } catch {
            state = .error(LovelaceDashboardError(
                dashboardPath: normalizedDashboardPath,
                message: Self.errorMessage(from: error)
            ))
        }
    }

    public func refetch() async {
        await load(
            dashboardPath: currentDashboardPath,
            viewPath: requestedViewPath,
            viewIndex: requestedViewIndex
        )
    }

    public func selectView(path: String?) {
        requestedViewPath = path
        requestedViewIndex = nil
        updateLoadedSelection()
    }

    public func selectView(index: Int?) {
        requestedViewPath = nil
        requestedViewIndex = index
        updateLoadedSelection()
    }

    public func cancelUpdateSubscription() {
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    private func ensureUpdateSubscription() async {
        guard updateSubscription == nil else {
            return
        }

        do {
            updateSubscription = try await updateEventSource.subscribeLovelaceUpdates { [weak self] event in
                Task {
                    await self?.handleLovelaceUpdate(event)
                }
            }
        } catch {
            logger?.warning(
                "Failed to subscribe to Lovelace update events",
                metadata: ["error": String(describing: error)]
            )
        }
    }

    private func handleLovelaceUpdate(_ event: LovelaceUpdateEvent) async {
        guard event.matches(dashboardPath: currentDashboardPath) else {
            return
        }
        await refetch()
    }

    private func apply(
        configuration: LovelaceConfiguration,
        dashboardPath: String,
        dashboards: [LovelaceDashboardReference],
        viewPath: String?,
        viewIndex: Int?
    ) throws {
        guard let rawConfig = configuration.config else {
            throw LovelaceStoreError.missingConfiguration(dashboardPath)
        }

        switch rawConfig {
        case let .config(config):
            let route = router.route(
                dashboardPath: dashboardPath,
                config: config,
                requestedViewPath: viewPath,
                requestedViewIndex: viewIndex
            )
            let selectedView = route.selectedViewIndex.flatMap { index in
                config.views.indices.contains(index) ? config.views[index] : nil
            }
            state = .loaded(LovelaceDashboardContent(
                dashboardPath: dashboardPath,
                rawJSON: configuration.rawJSON,
                rawConfig: rawConfig,
                config: config,
                selectedRoute: route,
                selectedView: selectedView,
                dashboards: dashboards,
                loadedAt: clock?.now
            ))
        case let .strategy(strategyConfig):
            state = .generatedStrategyPlaceholder(LovelaceStrategyPlaceholder(
                dashboardPath: dashboardPath,
                rawJSON: configuration.rawJSON,
                rawConfig: rawConfig,
                strategy: strategyConfig.strategy,
                requestedViewPath: viewPath,
                requestedViewIndex: viewIndex,
                dashboards: dashboards,
                loadedAt: clock?.now
            ))
        }
    }

    private func updateLoadedSelection() {
        guard case var .loaded(content) = state else {
            return
        }

        let route = router.route(
            dashboardPath: content.dashboardPath,
            config: content.config,
            requestedViewPath: requestedViewPath,
            requestedViewIndex: requestedViewIndex
        )
        content.selectedRoute = route
        content.selectedView = route.selectedViewIndex.flatMap { index in
            content.config.views.indices.contains(index) ? content.config.views[index] : nil
        }
        state = .loaded(content)
    }

    private static func errorMessage(from error: Error) -> String {
        if let storeError = error as? LovelaceStoreError {
            switch storeError {
            case let .missingConfiguration(dashboardPath):
                return "No Lovelace configuration was returned for \(dashboardPath)."
            }
        }

        if let localizedError = error as? LocalizedError, let errorDescription = localizedError.errorDescription {
            return errorDescription
        }

        return String(describing: error)
    }
}
