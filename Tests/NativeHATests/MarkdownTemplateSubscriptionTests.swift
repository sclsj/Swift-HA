import XCTest
@testable import NativeHACore

final class MarkdownTemplateSubscriptionTests: XCTestCase {
    func testSubscribeRenderTemplateBuildsPayloadAndRoutesMockEvents() async throws {
        let client = MockTemplateWebSocketClient()
        let templateClient = MarkdownTemplateClient(client: client)
        var events: [MarkdownTemplateEvent] = []

        let subscription = try await templateClient.subscribeRenderTemplate(
            MarkdownTemplateRequest(
                template: "{{ states('sensor.demo') }}\nDone",
                entityIDs: ["sensor.demo"],
                variables: [
                    "config": .object(["type": .string("markdown")]),
                    "user": .string("Joy")
                ],
                strict: true,
                reportErrors: false
            )
        ) { event in
            events.append(event)
        }

        XCTAssertEqual(client.capturedRequest?.type, "render_template")
        XCTAssertEqual(client.capturedRequest?.payload["template"], .string("{{ states('sensor.demo') }}\nDone"))
        XCTAssertEqual(client.capturedRequest?.payload["entity_ids"], .array([.string("sensor.demo")]))
        XCTAssertEqual(client.capturedRequest?.payload["strict"], .bool(true))
        XCTAssertEqual(client.capturedRequest?.payload["report_errors"], .bool(false))
        XCTAssertEqual(
            client.capturedRequest?.payload["variables"],
            .object([
                "config": .object(["type": .string("markdown")]),
                "user": .string("Joy")
            ])
        )

        try client.emit(.object([
            "result": .string("Line 1\nLine 2"),
            "listeners": .object(["all": .bool(false)])
        ]))
        try client.emit(.object([
            "error": .string("Template failed"),
            "level": .string("ERROR")
        ]))

        XCTAssertEqual(events, [
            .rendered(MarkdownTemplateResult(
                result: "Line 1\nLine 2",
                listeners: .object(["all": .bool(false)])
            )),
            .error(MarkdownTemplateError(error: "Template failed", level: "ERROR"))
        ])

        subscription.cancel()
        XCTAssertTrue(client.cancelled)
    }
}

private final class MockTemplateWebSocketClient: HAWebSocketClientProtocol {
    var capturedRequest: HAWebSocketRequest?
    var cancelled = false
    private var eventSink: ((HAJSONValue) throws -> Void)?

    func connect() async throws {}

    func disconnect() async {}

    func callWS<T, Message>(_ message: Message) async throws -> T where T: Decodable, Message: Encodable {
        throw HAWebSocketClientError.disconnected
    }

    func subscribe<T, Message>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription where T: Decodable, Message: Encodable {
        let data = try JSONEncoder().encode(message)
        capturedRequest = try JSONDecoder().decode(HAWebSocketRequest.self, from: data)
        eventSink = { value in
            let eventData = try JSONEncoder().encode(value)
            onEvent(try JSONDecoder().decode(T.self, from: eventData))
        }
        return HASubscription(id: 77) { [weak self] in
            self?.cancelled = true
        }
    }

    func emit(_ value: HAJSONValue) throws {
        try eventSink?(value)
    }
}
