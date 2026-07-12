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
}
