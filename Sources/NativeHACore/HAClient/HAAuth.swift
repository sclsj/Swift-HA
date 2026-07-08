import Foundation

public struct HAAuth: Equatable {
    public var credentials: HomeAssistantCredentials

    public init(credentials: HomeAssistantCredentials) {
        self.credentials = credentials
    }

    public init(credentialProvider: CredentialProvider) throws {
        self.credentials = try credentialProvider.credentials()
    }

    public var serverURL: URL {
        credentials.serverURL
    }

    public var accessToken: String {
        credentials.accessToken
    }

    public func webSocketURL() throws -> URL {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw CredentialProviderError.invalidServerURL(credentials.serverURL.absoluteString)
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw CredentialProviderError.invalidServerURL(credentials.serverURL.absoluteString)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/api/websocket" : "/\(basePath)/api/websocket"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw CredentialProviderError.invalidServerURL(credentials.serverURL.absoluteString)
        }
        return url
    }

    public func authRequest() -> HAWebSocketRequest {
        HAWebSocketRequest(
            type: "auth",
            payload: ["access_token": .string(credentials.accessToken)]
        )
    }
}
