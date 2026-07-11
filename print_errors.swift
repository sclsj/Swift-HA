import Foundation
enum HAWebSocketClientError: Error, Equatable {
    case invalidOutboundMessage
    case invalidInboundMessage
    case missingRequestID
    case authRequiredExpected
}
print((HAWebSocketClientError.invalidInboundMessage as NSError).description)
print((HAWebSocketClientError.invalidOutboundMessage as NSError).description)
