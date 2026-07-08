import Foundation

public protocol HAClientProtocol {
    func connect() async throws
    func disconnect() async
}

public protocol LovelaceConfigProvider {
    func dashboardList() async throws -> [LovelaceDashboardReference]
    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration
}

public protocol Clock {
    var now: Date { get }
}

public protocol CredentialProvider {
    func credentials() throws -> HomeAssistantCredentials
}

public struct HomeAssistantCredentials: Equatable {
    public var serverURL: URL
    public var accessToken: String

    public init(serverURL: URL, accessToken: String) {
        self.serverURL = serverURL
        self.accessToken = accessToken
    }
}

public struct LovelaceDashboardReference: Equatable {
    public var path: String
    public var title: String
    public var showInSidebar: Bool

    public init(path: String, title: String, showInSidebar: Bool = true) {
        self.path = AppRoute.dashboardPath(path)
        self.title = title
        self.showInSidebar = showInSidebar
    }
}

public struct LovelaceConfiguration: Equatable {
    public var dashboardPath: String
    public var rawJSON: String?
    public var config: LovelaceRawConfig?

    public init(dashboardPath: String, rawJSON: String? = nil, config: LovelaceRawConfig? = nil) {
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.rawJSON = rawJSON
        self.config = config
    }
}

public struct AppEnvironment {
    public var client: HAClientProtocol
    public var lovelaceConfigProvider: LovelaceConfigProvider
    public var lovelaceUpdateEventSource: LovelaceUpdateEventSource
    public var clock: Clock
    public var logger: Logger
    public var credentialProvider: CredentialProvider
    public var platform: PlatformTraits

    public init(
        client: HAClientProtocol,
        lovelaceConfigProvider: LovelaceConfigProvider,
        lovelaceUpdateEventSource: LovelaceUpdateEventSource = PlaceholderLovelaceUpdateEventSource(),
        clock: Clock,
        logger: Logger,
        credentialProvider: CredentialProvider,
        platform: PlatformTraits
    ) {
        self.client = client
        self.lovelaceConfigProvider = lovelaceConfigProvider
        self.lovelaceUpdateEventSource = lovelaceUpdateEventSource
        self.clock = clock
        self.logger = logger
        self.credentialProvider = credentialProvider
        self.platform = platform
    }

    public static func development(
        serverFilePath: String = "/Users/jin/Documents/HA/ha_server.txt",
        tokenFilePath: String = "/Users/jin/Documents/HA/ha_apikey.txt"
    ) -> AppEnvironment {
        let logger = ConsoleLogger()
        let credentialProvider = FileCredentialProvider(
            serverFilePath: serverFilePath,
            tokenFilePath: tokenFilePath
        )

        let connection = HAConnection(
            credentialProvider: credentialProvider,
            logger: logger
        )

        return AppEnvironment(
            client: connection,
            lovelaceConfigProvider: HALovelaceConfigProvider(connection: connection),
            lovelaceUpdateEventSource: HALovelaceUpdateEventSource(connection: connection),
            clock: SystemClock(),
            logger: logger,
            credentialProvider: credentialProvider,
            platform: PlatformTraits.current
        )
    }
}

public struct PlaceholderHAClient: HAClientProtocol {
    public init() {}

    public func connect() async throws {}

    public func disconnect() async {}
}

public struct PlaceholderLovelaceConfigProvider: LovelaceConfigProvider {
    public init() {}

    public func dashboardList() async throws -> [LovelaceDashboardReference] {
        []
    }

    public func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        LovelaceConfiguration(dashboardPath: dashboardPath)
    }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        Date()
    }
}

public enum CredentialProviderError: Error, Equatable {
    case missingServerURL
    case invalidServerURL(String)
    case missingAccessToken
}

public struct FileCredentialProvider: CredentialProvider {
    public var serverFilePath: String
    public var tokenFilePath: String

    public init(serverFilePath: String, tokenFilePath: String) {
        self.serverFilePath = serverFilePath
        self.tokenFilePath = tokenFilePath
    }

    public func credentials() throws -> HomeAssistantCredentials {
        let server = try readTrimmedFile(at: serverFilePath)
        guard !server.isEmpty else {
            throw CredentialProviderError.missingServerURL
        }
        guard let serverURL = URL(string: server) else {
            throw CredentialProviderError.invalidServerURL(server)
        }

        let token = try readTrimmedFile(at: tokenFilePath)
        guard !token.isEmpty else {
            throw CredentialProviderError.missingAccessToken
        }

        return HomeAssistantCredentials(serverURL: serverURL, accessToken: token)
    }

    private func readTrimmedFile(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
