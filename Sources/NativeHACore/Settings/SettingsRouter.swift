import Foundation

public enum SettingsRoute: Equatable, Hashable {
    case dashboard
    case fallback(path: String)

    public var path: String {
        switch self {
        case .dashboard:
            return "/config/dashboard"
        case let .fallback(path):
            return path
        }
    }
}

public struct SettingsRouter: Equatable {
    public var baseURL: URL?

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    public func route(for path: String?) -> SettingsRoute {
        let normalized = Self.normalizedPath(path)
        if normalized == "/config" || normalized == "/config/dashboard" {
            return .dashboard
        }
        return .fallback(path: normalized)
    }

    public func fallbackURL(for path: String) -> URL? {
        guard let baseURL = baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let normalized = Self.normalizedPath(path)
        let parts = normalized.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components.path = parts.first.map(String.init) ?? "/config"
        components.query = parts.count > 1 ? String(parts[1]) : nil
        components.fragment = nil
        return components.url
    }

    public static func normalizedPath(_ path: String?) -> String {
        let trimmed = (path ?? "/config/dashboard").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "/config/dashboard"
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }
}
