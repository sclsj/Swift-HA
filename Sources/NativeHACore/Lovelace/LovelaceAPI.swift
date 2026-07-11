import Foundation

public struct LovelaceAPI {
    private let client: HAWebSocketClientProtocol

    public init(client: HAWebSocketClientProtocol) {
        self.client = client
    }

    public func dashboards() async throws -> [LovelaceDashboard] {
        let response: [LovelaceDashboard] = try await client.callWS(
            HAWebSocketRequest(type: "lovelace/dashboards/list")
        )
        return response
    }

    public func configuration(urlPath: String? = nil, force: Bool = false) async throws -> LovelaceRawConfig {
        let response: LovelaceRawConfig = try await client.callWS(
            HAWebSocketRequest(
                type: "lovelace/config",
                payload: [
                    "url_path": normalizedURLPath(urlPath).map(HAJSONValue.string) ?? .null,
                    "force": .bool(force)
                ]
            )
        )
        return response
    }

    public func resources() async throws -> [LovelaceResource] {
        let response: [LovelaceResource] = try await client.callWS(
            HAWebSocketRequest(type: "lovelace/resources")
        )
        return response
    }

    public func info() async throws -> LovelaceInfo {
        let response: LovelaceInfo = try await client.callWS(
            HAWebSocketRequest(type: "lovelace/info")
        )
        return response
    }

    private func normalizedURLPath(_ urlPath: String?) -> String? {
        guard let urlPath = urlPath?.trimmingCharacters(in: .whitespacesAndNewlines), !urlPath.isEmpty else {
            return nil
        }
        return urlPath.hasPrefix("/") ? String(urlPath.dropFirst()) : urlPath
    }
}

public final class HALovelaceConfigProvider: LovelaceConfigProvider {
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

    public func dashboardList() async throws -> [LovelaceDashboardReference] {
        let dashboards = try await api().dashboards()
        return dashboards.map {
            LovelaceDashboardReference(path: $0.urlPath, title: $0.title, showInSidebar: $0.showInSidebar, requireAdmin: $0.requireAdmin ?? false)
        }
    }

    public func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        let urlPath = Self.websocketURLPath(forDashboardPath: dashboardPath)
        let config = try await api().configuration(urlPath: urlPath, force: false)
        return LovelaceConfiguration(
            dashboardPath: dashboardPath,
            rawJSON: Self.rawJSONString(from: config.raw),
            config: config
        )
    }

    private func api() throws -> LovelaceAPI {
        LovelaceAPI(client: try clientResolver())
    }

    private static func websocketURLPath(forDashboardPath dashboardPath: String) -> String {
        let normalized = AppRoute.dashboardPath(dashboardPath)
        return normalized.hasPrefix("/") ? String(normalized.dropFirst()) : normalized
    }

    private static func rawJSONString(from value: HAJSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
