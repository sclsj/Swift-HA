import Foundation

enum HAWebSocketClientError: Error, Equatable {
    case invalidOutboundMessage
    case invalidInboundMessage
    case missingRequestID
    case authRequiredExpected
    case invalidAuth(String)
    case requestFailed(HAWebSocketErrorPayload)
    case disconnected
    case timedOut
    case unsupportedTransportMessage
}

struct HAWebSocketErrorPayload: Equatable {
    var code: String
    var message: String
}

for c in [
    HAWebSocketClientError.invalidOutboundMessage,
    HAWebSocketClientError.invalidInboundMessage,
    HAWebSocketClientError.missingRequestID,
    HAWebSocketClientError.authRequiredExpected,
    HAWebSocketClientError.invalidAuth("x"),
    HAWebSocketClientError.requestFailed(HAWebSocketErrorPayload(code: "y", message: "z")),
    HAWebSocketClientError.disconnected,
    HAWebSocketClientError.timedOut,
    HAWebSocketClientError.unsupportedTransportMessage
] {
    let err = c as NSError
    print("\(c): \(err.code)")
}
