import Foundation

public enum AppRoute: Hashable, Identifiable {
    case dashboardList
    case dashboard(urlPath: String)
    case lovelaceView(dashboardPath: String, viewPath: String?, viewIndex: Int?)
    case moreInfo(entityID: String)
    case settings

    public var id: String {
        switch self {
        case .dashboardList:
            return "dashboard-list"
        case let .dashboard(urlPath):
            return "dashboard:\(urlPath)"
        case let .lovelaceView(dashboardPath, viewPath, viewIndex):
            let path = viewPath ?? ""
            let index = viewIndex.map(String.init) ?? ""
            return "lovelace-view:\(dashboardPath):\(path):\(index)"
        case let .moreInfo(entityID):
            return "more-info:\(entityID)"
        case .settings:
            return "settings"
        }
    }

    public var title: String {
        switch self {
        case .dashboardList:
            return "Dashboards"
        case let .dashboard(urlPath):
            return normalizedDashboardPath(urlPath)
        case let .lovelaceView(dashboardPath, viewPath, viewIndex):
            if let viewPath = viewPath, !viewPath.isEmpty {
                return "\(normalizedDashboardPath(dashboardPath)) / \(viewPath)"
            }
            if let viewIndex = viewIndex {
                return "\(normalizedDashboardPath(dashboardPath)) / View \(viewIndex)"
            }
            return normalizedDashboardPath(dashboardPath)
        case let .moreInfo(entityID):
            return entityID.isEmpty ? "More Info" : "More Info: \(entityID)"
        case .settings:
            return "Settings"
        }
    }

    public var entityIDForMoreInfo: String? {
        guard case let .moreInfo(entityID) = self else {
            return nil
        }
        return entityID
    }

    public static func dashboardPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "/lovelace"
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func normalizedDashboardPath(_ path: String) -> String {
        Self.dashboardPath(path)
    }
}

public struct AppPresentationState: Equatable {
    public var moreInfoRoute: AppRoute?

    public init(moreInfoRoute: AppRoute? = nil) {
        self.moreInfoRoute = moreInfoRoute
    }
}
