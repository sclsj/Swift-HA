import XCTest
@testable import NativeHA
@testable import NativeHACore

final class SettingsDashboardTests: XCTestCase {
    @MainActor
    func testSettingsRouteOpensNativeSettingsModelWithoutMutatingDashboardSelection() {
        let state = AppState(environment: .settingsTest)

        state.selectDashboard(path: "/lovelace")
        state.navigate(to: .settings)

        XCTAssertEqual(state.route, .settings)
        XCTAssertEqual(state.selectedDashboardPath, "/lovelace")

        let model = SettingsDashboardModel(context: adminContext())
        XCTAssertTrue(model.sections.flatMap(\.items).contains { $0.title == "Devices & services" })
    }

    @MainActor
    func testSettingsRouteDoesNotBreakMoreInfoRouting() {
        let state = AppState(environment: .settingsTest)

        state.presentMoreInfo(entityID: "sensor.temperature")
        state.navigate(to: .settings)

        XCTAssertEqual(state.presentation.moreInfoRoute, .moreInfo(entityID: "sensor.temperature"))
    }

    func testSettingsModelHandlesMissingServerAndUserSafely() {
        let model = SettingsDashboardModel(context: SettingsDashboardContext())

        XCTAssertEqual(model.summary.title, "Home Assistant")
        XCTAssertEqual(model.summary.serverURL, "Not configured")
        XCTAssertEqual(model.summary.user, "Unknown user")
        XCTAssertEqual(model.summary.role, "Unknown")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testConnectionStatusAndSummaryFormattingIsDeterministic() {
        let model = SettingsDashboardModel(context: SettingsDashboardContext(
            serverURL: URL(string: "http://ha.local:8123"),
            connectionState: .failed(message: "offline"),
            stores: HomeAssistantStores(
                statesCount: 2,
                entitiesCount: 3,
                devicesCount: 4,
                areasCount: 5,
                floorsCount: 6,
                servicesCount: 7,
                panelsCount: 8
            ),
            config: config(components: ["cloud", "lovelace"]),
            currentUser: HAUser(id: "user", name: "Ada", isAdmin: true, isOwner: false)
        ))

        XCTAssertEqual(model.summary.connectionStatus, "Failed: offline")
        XCTAssertEqual(model.summary.serverURL, "http://ha.local:8123")
        XCTAssertEqual(model.summary.version, "2026.7.0")
        XCTAssertEqual(model.summary.user, "Ada")
        XCTAssertEqual(model.summary.role, "Administrator")
        XCTAssertEqual(model.summary.storeCounts, "2 states, 3 entities, 4 devices, 5 areas")
        XCTAssertEqual(model.summary.components, "2 components")
    }

    func testSettingsVisibilityMatchesAdminAndComponentGates() {
        let model = SettingsDashboardModel(context: adminContext(
            components: [
                "cloud",
                "lovelace",
                "zone",
                "tag",
                "person",
                "users",
                "bluetooth",
                "radio_frequency"
            ],
            states: [:],
            hasBluetoothConfigEntries: true
        ))
        let titles = model.sections.flatMap(\.items).map(\.title)

        XCTAssertTrue(titles.contains("Home Assistant Cloud"))
        XCTAssertTrue(titles.contains("Devices & services"))
        XCTAssertTrue(titles.contains("Areas, labels & zones"))
        XCTAssertTrue(titles.contains("Dashboards"))
        XCTAssertTrue(titles.contains("Voice Assistants"))
        XCTAssertTrue(titles.contains("Bluetooth"))
        XCTAssertTrue(titles.contains("Tags"))
        XCTAssertTrue(titles.contains("People"))
        XCTAssertTrue(titles.contains("System"))
        XCTAssertTrue(titles.contains("Tools"))
        XCTAssertTrue(titles.contains("About"))
        XCTAssertFalse(titles.contains("Matter"))
        XCTAssertFalse(titles.contains("Radio-frequency"))

        let nonAdmin = SettingsDashboardModel(context: SettingsDashboardContext(
            serverURL: URL(string: "http://ha.local:8123"),
            connectionState: .connected,
            config: config(components: ["cloud", "lovelace"]),
            currentUser: HAUser(id: "user", name: "Guest", isAdmin: false, isOwner: false)
        ))
        let nonAdminTitles = nonAdmin.sections.flatMap(\.items).map(\.title)
        XCTAssertEqual(nonAdminTitles, ["Home Assistant Cloud"])

        let noBluetoothEntriesModel = SettingsDashboardModel(context: adminContext(
            components: ["bluetooth"],
            hasBluetoothConfigEntries: false
        ))
        let noBluetoothTitles = noBluetoothEntriesModel.sections.flatMap(\.items).map(\.title)
        XCTAssertFalse(noBluetoothTitles.contains("Bluetooth"))
    }

    func testFallbackURLsAndSettingsRouterAreDeterministic() throws {
        let router = SettingsRouter(baseURL: URL(string: "http://ha.local:8123"))

        XCTAssertEqual(router.route(for: "/config"), .dashboard)
        XCTAssertEqual(router.route(for: "/config/dashboard"), .dashboard)
        XCTAssertEqual(router.route(for: "config/tools"), .fallback(path: "/config/tools"))
        XCTAssertEqual(router.fallbackURL(for: "/config/tools?historyBack=1")?.absoluteString, "http://ha.local:8123/config/tools?historyBack=1")

        let model = SettingsDashboardModel(context: adminContext())
        let devices = try XCTUnwrap(model.sections.flatMap(\.items).first { $0.id == "devices" })
        XCTAssertEqual(devices.fallbackURL?.absoluteString, "http://ha.local:8123/config/integrations")
    }

    private func adminContext(
        components: [String] = ["cloud", "lovelace", "zone", "tag", "person", "users"],
        states: [EntityID: HassEntity] = [:],
        hasBluetoothConfigEntries: Bool? = nil
    ) -> SettingsDashboardContext {
        SettingsDashboardContext(
            serverURL: URL(string: "http://ha.local:8123"),
            connectionState: .connected,
            stores: HomeAssistantStores(statesCount: states.count),
            config: config(components: components),
            currentUser: HAUser(id: "owner", name: "Owner", isAdmin: true, isOwner: true),
            states: states,
            hasBluetoothConfigEntries: hasBluetoothConfigEntries
        )
    }

    private func config(components: [String]) -> HAConfig {
        HAConfig(
            latitude: 0,
            longitude: 0,
            elevation: 0,
            locationName: "Test Home",
            timeZone: "UTC",
            unitSystem: [:],
            version: "2026.7.0",
            components: components,
            configDir: nil,
            configSource: nil,
            country: nil,
            currency: nil,
            language: nil,
            internalURL: nil,
            externalURL: nil,
            safeMode: false,
            recoveryMode: nil,
            state: nil
        )
    }
}

private extension AppEnvironment {
    static var settingsTest: AppEnvironment {
        AppEnvironment(
            client: SettingsTestHAClient(),
            lovelaceConfigProvider: SettingsTestLovelaceConfigProvider(),
            clock: SettingsTestClock(),
            logger: SettingsTestLogger(),
            credentialProvider: SettingsTestCredentialProvider(),
            platform: PlatformTraits(
                operatingSystem: .macOS,
                idiom: .desktop,
                isMac: true,
                isMobile: false,
                localeIdentifier: "en_US",
                timeZoneIdentifier: "UTC"
            )
        )
    }
}

private struct SettingsTestHAClient: HAClientProtocol {
    func connect() async throws {}
    func disconnect() async {}
}

private struct SettingsTestLovelaceConfigProvider: LovelaceConfigProvider {
    func dashboardList() async throws -> [LovelaceDashboardReference] {
        []
    }

    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        LovelaceConfiguration(dashboardPath: dashboardPath)
    }
}

private struct SettingsTestClock: Clock {
    var now: Date {
        Date(timeIntervalSince1970: 0)
    }
}

private struct SettingsTestLogger: Logger {
    func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {}
}

private struct SettingsTestCredentialProvider: CredentialProvider {
    func credentials() throws -> HomeAssistantCredentials {
        HomeAssistantCredentials(
            serverURL: URL(string: "http://ha.local:8123")!,
            accessToken: "test-token"
        )
    }
}
