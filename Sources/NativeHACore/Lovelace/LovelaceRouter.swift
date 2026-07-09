import Foundation

public struct LovelaceViewRoute: Equatable, Identifiable {
    public var dashboardPath: String
    public var requestedViewPath: String?
    public var requestedViewIndex: Int?
    public var selectedViewIndex: Int?
    public var selectedViewPath: String?
    public var isSubview: Bool
    public var backPath: String?

    public init(
        dashboardPath: String,
        requestedViewPath: String? = nil,
        requestedViewIndex: Int? = nil,
        selectedViewIndex: Int? = nil,
        selectedViewPath: String? = nil,
        isSubview: Bool = false,
        backPath: String? = nil
    ) {
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.requestedViewPath = requestedViewPath
        self.requestedViewIndex = requestedViewIndex
        self.selectedViewIndex = selectedViewIndex
        self.selectedViewPath = selectedViewPath
        self.isSubview = isSubview
        self.backPath = backPath
    }

    public var id: String {
        let selected = selectedViewPath ?? selectedViewIndex.map(String.init) ?? ""
        return "\(dashboardPath):\(selected)"
    }

    public var routeComponent: String? {
        selectedViewPath ?? selectedViewIndex.map(String.init)
    }
}

public struct LovelaceRouter: Equatable {
    public init() {}

    public func route(
        dashboardPath: String,
        config: LovelaceConfig,
        requestedViewPath: String? = nil,
        requestedViewIndex: Int? = nil,
        userID: String? = nil
    ) -> LovelaceViewRoute {
        let normalizedDashboardPath = AppRoute.dashboardPath(dashboardPath)
        let views = config.views
        let selectedIndex = selectViewIndex(
            views: views,
            requestedViewPath: requestedViewPath,
            requestedViewIndex: requestedViewIndex,
            userID: userID
        )

        guard let selectedIndex = selectedIndex, views.indices.contains(selectedIndex) else {
            return LovelaceViewRoute(
                dashboardPath: normalizedDashboardPath,
                requestedViewPath: requestedViewPath,
                requestedViewIndex: requestedViewIndex
            )
        }

        let view = views[selectedIndex]
        return LovelaceViewRoute(
            dashboardPath: normalizedDashboardPath,
            requestedViewPath: requestedViewPath,
            requestedViewIndex: requestedViewIndex,
            selectedViewIndex: selectedIndex,
            selectedViewPath: view.path,
            isSubview: view.subview == true,
            backPath: view.backPath
        )
    }

    public func isVisible(_ view: LovelaceViewConfig, userID: String? = nil) -> Bool {
        guard let visible = view.visible else {
            return true
        }

        switch visible {
        case let .bool(value):
            return value
        case let .array(values):
            guard let userID = userID else {
                return false
            }
            return values.contains { value in
                value.objectValue?["user"]?.stringValue == userID
            }
        default:
            return true
        }
    }

    public func visibleViewIndexes(in config: LovelaceConfig, userID: String? = nil) -> [Int] {
        config.views.indices.filter { index in
            isVisible(config.views[index], userID: userID)
        }
    }

    private func selectViewIndex(
        views: [LovelaceViewConfig],
        requestedViewPath: String?,
        requestedViewIndex: Int?,
        userID: String?
    ) -> Int? {
        guard !views.isEmpty else {
            return nil
        }

        if let requestedViewPath = requestedViewPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedViewPath.isEmpty {
            let requestedIndex = Int(requestedViewPath)
            for index in views.indices {
                if (views[index].path == requestedViewPath || index == requestedIndex),
                   isVisible(views[index], userID: userID) {
                    return index
                }
            }
        }

        if let requestedViewIndex = requestedViewIndex,
           views.indices.contains(requestedViewIndex),
           isVisible(views[requestedViewIndex], userID: userID) {
            return requestedViewIndex
        }

        return views.indices.first { isVisible(views[$0], userID: userID) }
    }
}
