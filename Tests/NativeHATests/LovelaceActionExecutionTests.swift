import XCTest
@testable import NativeHA
@testable import NativeHACore

final class LovelaceActionExecutionTests: XCTestCase {
    func testDispatcherExecutesNavigateAndOpenURLActions() {
        var navigationPath: String?
        var navigationReplace: Bool?
        var openedURL: String?

        let dispatcher = CardActionDispatcher(
            entityID: nil,
            states: [:],
            onMoreInfo: { _ in XCTFail("Navigate and URL actions should not open more-info.") },
            onServiceCall: { _ in XCTFail("Navigate and URL actions should not call a service.") },
            onNavigate: { path, replace in
                navigationPath = path
                navigationReplace = replace
            },
            onOpenURL: { url in
                openedURL = url
            }
        )

        dispatcher.perform(.navigate(path: "/lovelace/lab", replace: true))
        dispatcher.perform(.openURL("https://example.test/dashboard"))

        XCTAssertEqual(navigationPath, "/lovelace/lab")
        XCTAssertEqual(navigationReplace, true)
        XCTAssertEqual(openedURL, "https://example.test/dashboard")
    }

    func testUnsupportedResolvedActionsAreExplicitNoOps() {
        var callbackCount = 0
        let executor = LovelaceActionExecutor(
            onMoreInfo: { _ in callbackCount += 1 },
            onServiceCall: { _ in callbackCount += 1 },
            onNavigate: { _, _ in callbackCount += 1 },
            onOpenURL: { _ in callbackCount += 1 }
        )

        executor.perform(.assist(startListening: true, pipelineID: "last_used"))
        executor.perform(.fireDOMEvent(LovelaceActionConfig(action: "fire-dom-event")))

        XCTAssertEqual(callbackCount, 0)
    }

    func testConfirmedActionCanExecuteThroughSharedExecutor() throws {
        let notificationExpectation = expectation(description: "confirmation notification")
        let confirmation = LovelaceConfirmationRestrictionConfig(title: "Confirm")
        var pendingAction: LovelaceResolvedAction?

        let observer = NotificationCenter.default.addObserver(
            forName: .lovelaceActionRequiresConfirmation,
            object: nil,
            queue: nil
        ) { notification in
            XCTAssertEqual(
                notification.userInfo?["config"] as? LovelaceConfirmationRestrictionConfig,
                confirmation
            )
            pendingAction = notification.userInfo?["action"] as? LovelaceResolvedAction
            notificationExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        var navigationPath: String?
        var navigationReplace: Bool?
        let executor = LovelaceActionExecutor(
            onNavigate: { path, replace in
                navigationPath = path
                navigationReplace = replace
            }
        )

        executor.perform(.confirmation(
            confirmation,
            then: .navigate(path: "/lovelace/confirmed", replace: false)
        ))
        wait(for: [notificationExpectation], timeout: 1)

        executor.perform(try XCTUnwrap(pendingAction))

        XCTAssertEqual(navigationPath, "/lovelace/confirmed")
        XCTAssertEqual(navigationReplace, false)
    }

    func testDispatcherBypassesConfirmationForExemptUser() {
        let noConfirmationExpectation = expectation(description: "confirmation not requested")
        noConfirmationExpectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .lovelaceActionRequiresConfirmation,
            object: nil,
            queue: nil
        ) { _ in
            noConfirmationExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        var serviceCall: HAServiceCall?
        let dispatcher = CardActionDispatcher(
            entityID: nil,
            states: [:],
            currentUser: HAUser(id: "exempt-user", name: "Ada"),
            onMoreInfo: { _ in XCTFail("Exempt service action should not open more-info.") },
            onServiceCall: { serviceCall = $0 }
        )

        dispatcher.perform(tapAction: confirmedServiceAction(exemptUserID: "exempt-user"))

        wait(for: [noConfirmationExpectation], timeout: 0.1)
        XCTAssertEqual(serviceCall?.domain, "light")
        XCTAssertEqual(serviceCall?.service, "turn_on")
    }

    func testDispatcherRequiresConfirmationForNonExemptUser() {
        let notificationExpectation = expectation(description: "confirmation requested")
        var pendingAction: LovelaceResolvedAction?
        let observer = NotificationCenter.default.addObserver(
            forName: .lovelaceActionRequiresConfirmation,
            object: nil,
            queue: nil
        ) { notification in
            pendingAction = notification.userInfo?["action"] as? LovelaceResolvedAction
            notificationExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        var serviceCall: HAServiceCall?
        let dispatcher = CardActionDispatcher(
            entityID: nil,
            states: [:],
            currentUser: HAUser(id: "other-user", name: "Grace"),
            onMoreInfo: { _ in XCTFail("Confirmed service action should not open more-info.") },
            onServiceCall: { serviceCall = $0 }
        )

        dispatcher.perform(tapAction: confirmedServiceAction(exemptUserID: "exempt-user"))

        wait(for: [notificationExpectation], timeout: 1)
        XCTAssertNil(serviceCall)
        guard case let .callService(call)? = pendingAction else {
            return XCTFail("Expected the confirmation to carry the pending service call.")
        }
        XCTAssertEqual(call.domain, "light")
        XCTAssertEqual(call.service, "turn_on")
    }

    func testTileIconTapPassesDisplayContextUserToConfirmationExemption() throws {
        let noConfirmationExpectation = expectation(description: "tile icon confirmation not requested")
        noConfirmationExpectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .lovelaceActionRequiresConfirmation,
            object: nil,
            queue: nil
        ) { _ in
            noConfirmationExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let stateObj = entity("switch.kitchen", state: "on")
        let config = try tileConfig(
            """
            {
              "type": "tile",
              "entity": "switch.kitchen",
              "icon_tap_action": {
                "action": "call-service",
                "perform_action": "switch.turn_off",
                "confirmation": {
                  "exemptions": [
                    { "user": "tile-user" }
                  ]
                }
              }
            }
            """
        )
        var serviceCall: HAServiceCall?
        let view = TileCardView(
            config: config,
            displayContext: EntityDisplayContext(
                states: [stateObj.entityID: stateObj],
                currentUser: HAUser(id: "tile-user", name: "Tile User")
            ),
            onMoreInfo: { _ in XCTFail("Tile icon service action should not open more-info.") },
            onServiceCall: { serviceCall = $0 }
        )

        view.performIconGesture(stateObj, gesture: .tap)

        wait(for: [noConfirmationExpectation], timeout: 0.1)
        XCTAssertEqual(serviceCall?.domain, "switch")
        XCTAssertEqual(serviceCall?.service, "turn_off")
    }

    private func confirmedServiceAction(exemptUserID: String) -> LovelaceActionConfig {
        LovelaceActionConfig(
            action: "call-service",
            confirmation: LovelaceConfirmationRestrictionConfig(
                exemptions: [LovelaceRestrictionConfig(user: exemptUserID)]
            ),
            performAction: "light.turn_on"
        )
    }

    private func tileConfig(_ json: String) throws -> TileCardConfig {
        try JSONDecoder().decode(TileCardConfig.self, from: Data(json.utf8))
    }

    private func entity(_ entityID: EntityID, state: String) -> HassEntity {
        let date = Date(timeIntervalSince1970: 0)
        return HassEntity(
            entityID: entityID,
            state: state,
            attributes: [:],
            lastChanged: date,
            lastUpdated: date,
            context: HAContext(id: "test")
        )
    }
}
