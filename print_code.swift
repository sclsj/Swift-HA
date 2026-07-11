import Foundation
enum HAWebSocketClientError: Error {
    case invalidOutboundMessage
    case invalidInboundMessage
    case missingRequestID
    case authRequiredExpected
}

let error1 = HAWebSocketClientError.invalidOutboundMessage as NSError
print("invalidOutboundMessage code: \(error1.code)")

let error2 = HAWebSocketClientError.invalidInboundMessage as NSError
print("invalidInboundMessage code: \(error2.code)")

let error3 = HAWebSocketClientError.missingRequestID as NSError
print("missingRequestID code: \(error3.code)")

let error4 = HAWebSocketClientError.authRequiredExpected as NSError
print("authRequiredExpected code: \(error4.code)")
