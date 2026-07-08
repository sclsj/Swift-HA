import XCTest
@testable import NativeHACore

final class AppScaffoldTests: XCTestCase {
    func testDashboardPathsAreNormalized() {
        XCTAssertEqual(AppRoute.dashboardPath("lovelace/default_view"), "/lovelace/default_view")
        XCTAssertEqual(AppRoute.dashboardPath("/all-devices"), "/all-devices")
        XCTAssertEqual(AppRoute.dashboardPath(""), "/lovelace")
    }

    func testAppStateTracksDashboardSelectionFromRoutes() {
        let state = AppState(environment: .test)

        state.selectDashboard(path: "dashboard-ultrasonic")
        XCTAssertEqual(state.selectedDashboardPath, "/dashboard-ultrasonic")
        XCTAssertEqual(state.route, .dashboard(urlPath: "/dashboard-ultrasonic"))

        state.navigate(to: .lovelaceView(dashboardPath: "/lovelace", viewPath: "default_view", viewIndex: nil))
        XCTAssertEqual(state.selectedDashboardPath, "/lovelace")
    }

    func testMoreInfoPresentationUsesEntityRoute() {
        let state = AppState(environment: .test)

        state.presentMoreInfo(entityID: "sensor.temperature")
        XCTAssertEqual(state.presentation.moreInfoRoute, .moreInfo(entityID: "sensor.temperature"))

        state.dismissMoreInfo()
        XCTAssertNil(state.presentation.moreInfoRoute)
    }

    func testFileCredentialProviderReadsLocalDevelopmentFiles() throws {
        let directory = NSTemporaryDirectory()
        let serverPath = "\(directory)/native-ha-server-\(UUID().uuidString).txt"
        let tokenPath = "\(directory)/native-ha-token-\(UUID().uuidString).txt"
        try "http://homeassistant.local:8123\n".write(toFile: serverPath, atomically: true, encoding: .utf8)
        try "test-token\n".write(toFile: tokenPath, atomically: true, encoding: .utf8)

        let provider = FileCredentialProvider(serverFilePath: serverPath, tokenFilePath: tokenPath)
        let credentials = try provider.credentials()

        XCTAssertEqual(credentials.serverURL.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(credentials.accessToken, "test-token")
    }
}

private extension AppEnvironment {
    static var test: AppEnvironment {
        AppEnvironment(
            client: TestHAClient(),
            lovelaceConfigProvider: TestLovelaceConfigProvider(),
            clock: TestClock(),
            logger: TestLogger(),
            credentialProvider: TestCredentialProvider(),
            platform: PlatformTraits(
                operatingSystem: .macOS,
                idiom: .desktop,
                isMac: true,
                isMobile: false,
                localeIdentifier: "en_US",
                timeZoneIdentifier: "Asia/Shanghai"
            )
        )
    }
}

private struct TestHAClient: HAClientProtocol {
    func connect() async throws {}
    func disconnect() async {}
}

private struct TestLovelaceConfigProvider: LovelaceConfigProvider {
    func dashboardList() async throws -> [LovelaceDashboardReference] {
        []
    }

    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        LovelaceConfiguration(dashboardPath: dashboardPath)
    }
}

private struct TestClock: Clock {
    var now: Date {
        Date(timeIntervalSince1970: 0)
    }
}

private struct TestLogger: Logger {
    func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {}
}

private struct TestCredentialProvider: CredentialProvider {
    func credentials() throws -> HomeAssistantCredentials {
        HomeAssistantCredentials(
            serverURL: URL(string: "http://homeassistant.local:8123")!,
            accessToken: "test-token"
        )
    }
}
