import Combine
import Foundation

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(message: String)
}

public enum ThemePreference: Equatable {
    case system
    case light
    case dark
}

public struct HomeAssistantStores: Equatable {
    public var statesCount: Int
    public var entitiesCount: Int
    public var devicesCount: Int
    public var areasCount: Int
    public var floorsCount: Int
    public var servicesCount: Int
    public var panelsCount: Int

    public init(
        statesCount: Int = 0,
        entitiesCount: Int = 0,
        devicesCount: Int = 0,
        areasCount: Int = 0,
        floorsCount: Int = 0,
        servicesCount: Int = 0,
        panelsCount: Int = 0
    ) {
        self.statesCount = statesCount
        self.entitiesCount = entitiesCount
        self.devicesCount = devicesCount
        self.areasCount = areasCount
        self.floorsCount = floorsCount
        self.servicesCount = servicesCount
        self.panelsCount = panelsCount
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var connectionState: ConnectionState
    @Published public private(set) var stores: HomeAssistantStores
    @Published public private(set) var selectedDashboardPath: String?
    @Published public private(set) var route: AppRoute
    @Published public private(set) var presentation: AppPresentationState
    @Published public var themePreference: ThemePreference
    @Published public var platform: PlatformTraits

    public let environment: AppEnvironment

    public init(
        environment: AppEnvironment,
        initialRoute: AppRoute = .dashboardList,
        platform: PlatformTraits? = nil
    ) {
        self.environment = environment
        self.connectionState = .disconnected
        self.stores = HomeAssistantStores()
        self.selectedDashboardPath = nil
        self.route = initialRoute
        self.presentation = AppPresentationState()
        self.themePreference = .system
        self.platform = platform ?? environment.platform
    }

    public func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    public func updateStores(_ stores: HomeAssistantStores) {
        self.stores = stores
    }

    public func selectDashboard(path: String) {
        let normalizedPath = AppRoute.dashboardPath(path)
        selectedDashboardPath = normalizedPath
        route = .dashboard(urlPath: normalizedPath)
    }

    public func navigate(to route: AppRoute) {
        self.route = route
        if case let .dashboard(urlPath) = route {
            selectedDashboardPath = AppRoute.dashboardPath(urlPath)
        } else if case let .lovelaceView(dashboardPath, _, _) = route {
            selectedDashboardPath = AppRoute.dashboardPath(dashboardPath)
        }
    }

    public func presentMoreInfo(entityID: String) {
        guard !entityID.isEmpty else {
            presentation.moreInfoRoute = nil
            return
        }
        presentation.moreInfoRoute = .moreInfo(entityID: entityID)
    }

    public func dismissMoreInfo() {
        presentation.moreInfoRoute = nil
    }
}
