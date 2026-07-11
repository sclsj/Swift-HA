import Foundation
import XCTest
@testable import NativeHACore

final class LovelaceStoreRouterTests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"

    func testViewVisibilityHandlesBooleansAndUserRestrictions() {
        let router = LovelaceRouter()
        let omitted = LovelaceViewConfig(path: "omitted")
        let enabled = LovelaceViewConfig(path: "enabled", visible: .bool(true))
        let disabled = LovelaceViewConfig(path: "disabled", visible: .bool(false))
        let restricted = LovelaceViewConfig(
            path: "restricted",
            visible: .array([.object(["user": .string("user-a")])])
        )

        XCTAssertTrue(router.isVisible(omitted))
        XCTAssertTrue(router.isVisible(enabled))
        XCTAssertFalse(router.isVisible(disabled))
        XCTAssertTrue(router.isVisible(restricted, userID: "user-a"))
        XCTAssertFalse(router.isVisible(restricted, userID: "user-b"))
        XCTAssertFalse(router.isVisible(restricted, userID: nil))
    }

    func testRoutingSelectsZeroIndexWhenExplicitRequestIsMissing() {
        let router = LovelaceRouter()
        let config = LovelaceConfig(
            views: [
                LovelaceViewConfig(path: "private", visible: .bool(false)),
                LovelaceViewConfig(path: "public", visible: .bool(true))
            ],
            raw: .object([:])
        )
        
        // If explicitly requested view is not found, fallback to 0 (regardless of visibility)
        XCTAssertEqual(
            router.route(dashboardPath: "/lovelace", config: config, requestedViewPath: "missing", userID: nil).selectedViewIndex,
            0
        )
        
        // If no explicit request, fallback to first visible view
        XCTAssertEqual(
            router.route(dashboardPath: "/lovelace", config: config, requestedViewPath: nil, userID: nil).selectedViewIndex,
            1
        )
    }

    func testRoutingDoesNotSelectRestrictedViewWithoutMatchingUser() {
        let router = LovelaceRouter()
        let config = LovelaceConfig(
            views: [
                LovelaceViewConfig(
                    path: "private",
                    visible: .array([.object(["user": .string("user-a")])])
                ),
                LovelaceViewConfig(path: "public")
            ],
            raw: .object([:])
        )

        // With explicit request, bypass visibility gate
        XCTAssertEqual(
            router.route(
                dashboardPath: "/lovelace",
                config: config,
                requestedViewPath: "private",
                userID: nil
            ).selectedViewPath,
            "private"
        )
        
        // Without explicit request, fallback to public since private is restricted
        XCTAssertEqual(
            router.route(
                dashboardPath: "/lovelace",
                config: config,
                requestedViewPath: nil,
                userID: nil
            ).selectedViewPath,
            "public"
        )
    }

    @MainActor
    func testStorePassesCurrentUserToRouting() async throws {
        let store = LovelaceStore(configProvider: RestrictedViewConfigProvider())

        await store.load(
            dashboardPath: "/lovelace",
            viewPath: nil,
            userID: "user-b"
        )
        XCTAssertEqual(try XCTUnwrap(store.state.loadedDashboard).selectedView?.path, "public")

        await store.load(
            dashboardPath: "/lovelace",
            viewPath: nil,
            userID: "user-a"
        )
        XCTAssertEqual(try XCTUnwrap(store.state.loadedDashboard).selectedView?.path, "private")
    }

    @MainActor
    func testStoreLoadsExpectedDashboardConfigsThroughMockProvider() async throws {
        let provider = SnapshotLovelaceConfigProvider(snapshotDirectory: snapshotDirectory)
        let store = LovelaceStore(configProvider: provider)

        let expectations: [(path: String, viewCount: Int)] = [
            ("/lovelace", 3),
            ("/all-devices", 1),
            ("/dashboard-ultrasonic", 1)
        ]

        for expectation in expectations {
            await store.load(dashboardPath: expectation.path)

            guard case let .loaded(content) = store.state else {
                XCTFail("Expected loaded dashboard for \(expectation.path), got \(store.state).")
                continue
            }

            XCTAssertEqual(content.dashboardPath, expectation.path)
            XCTAssertEqual(content.config.views.count, expectation.viewCount)
            XCTAssertNotNil(content.rawJSON)
            XCTAssertEqual(content.rawConfig.views.count, expectation.viewCount)
            XCTAssertEqual(content.dashboards.count, 4)
        }

        XCTAssertEqual(provider.configurationRequests(), ["/lovelace", "/all-devices", "/dashboard-ultrasonic"])
    }

    @MainActor
    func testStoreSelectsOverviewViewsByPath() async throws {
        let provider = SnapshotLovelaceConfigProvider(snapshotDirectory: snapshotDirectory)
        let store = LovelaceStore(configProvider: provider)

        let expectations: [(path: String, index: Int)] = [
            ("default_view", 0),
            ("home_3h", 1),
            ("home_12h", 2)
        ]

        for expectation in expectations {
            await store.load(dashboardPath: "/lovelace", viewPath: expectation.path)

            let content = try XCTUnwrap(store.state.loadedDashboard)
            XCTAssertEqual(content.selectedRoute.selectedViewIndex, expectation.index)
            XCTAssertEqual(content.selectedRoute.selectedViewPath, expectation.path)
            XCTAssertEqual(content.selectedView?.path, expectation.path)
        }
    }

    @MainActor
    func testStoreRefetchesOnMatchingLovelaceUpdateEvent() async throws {
        let provider = SnapshotLovelaceConfigProvider(snapshotDirectory: snapshotDirectory)
        let updateSource = MockLovelaceUpdateEventSource()
        let store = LovelaceStore(configProvider: provider, updateEventSource: updateSource)

        await store.load(dashboardPath: "/lovelace", viewPath: "home_3h")

        XCTAssertEqual(updateSource.subscribeCount, 1)
        XCTAssertEqual(provider.configurationCallCount(for: "/lovelace"), 1)

        updateSource.emit(LovelaceUpdateEvent(urlPath: "map", mode: "storage"))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(provider.configurationCallCount(for: "/lovelace"), 1)

        updateSource.emit(LovelaceUpdateEvent(urlPath: "lovelace", mode: "storage"))
        try await waitUntil {
            provider.configurationCallCount(for: "/lovelace") == 2
        }

        let content = try XCTUnwrap(store.state.loadedDashboard)
        XCTAssertEqual(content.selectedRoute.selectedViewPath, "home_3h")
        XCTAssertEqual(updateSource.subscribeCount, 1)
    }

    @MainActor
    func testStoreIgnoresStaleDashboardLoadAfterNewerRouteWins() async throws {
        let provider = DelayedLovelaceConfigProvider()
        let store = LovelaceStore(configProvider: provider)

        let slowLoad = Task {
            await store.load(dashboardPath: "/slow")
        }
        await provider.waitForConfigurationRequest("/slow")

        await store.load(dashboardPath: "/fast")
        XCTAssertEqual(try XCTUnwrap(store.state.loadedDashboard).dashboardPath, "/fast")

        provider.finishSlowConfiguration()
        await slowLoad.value

        XCTAssertEqual(try XCTUnwrap(store.state.loadedDashboard).dashboardPath, "/fast")
        XCTAssertEqual(provider.configurationRequests(), ["/slow", "/fast"])
    }

    @MainActor
    func testMapStrategyDashboardBecomesPlaceholder() async throws {
        let provider = SnapshotLovelaceConfigProvider(snapshotDirectory: snapshotDirectory)
        let store = LovelaceStore(configProvider: provider)

        await store.load(dashboardPath: "/map")

        guard case let .generatedStrategyPlaceholder(placeholder) = store.state else {
            XCTFail("Expected strategy placeholder, got \(store.state).")
            return
        }

        XCTAssertEqual(placeholder.dashboardPath, "/map")
        XCTAssertEqual(placeholder.strategy.type, "map")
        XCTAssertEqual(placeholder.rawConfig.strategy?.type, "map")
        XCTAssertNotNil(placeholder.rawJSON)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        predicate: @escaping () -> Bool
    ) async throws {
        let interval: UInt64 = 10_000_000
        let attempts = Int(timeoutNanoseconds / interval)

        for _ in 0..<attempts {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: interval)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

private final class SnapshotLovelaceConfigProvider: LovelaceConfigProvider {
    private let snapshotDirectory: String
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var requestedConfigurations: [String] = []

    init(snapshotDirectory: String) {
        self.snapshotDirectory = snapshotDirectory
    }

    func dashboardList() async throws -> [LovelaceDashboardReference] {
        let dashboards: [LovelaceDashboard] = try decodeSnapshot("lovelace_dashboards")
        return dashboards.map {
            LovelaceDashboardReference(
                path: $0.urlPath,
                title: $0.title,
                showInSidebar: $0.showInSidebar
            )
        }
    }

    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        let normalizedPath = AppRoute.dashboardPath(dashboardPath)
        recordConfigurationRequest(normalizedPath)

        let snapshotName: String
        switch normalizedPath {
        case "/lovelace":
            snapshotName = "lovelace_config_lovelace"
        case "/all-devices":
            snapshotName = "lovelace_config_all-devices"
        case "/dashboard-ultrasonic":
            snapshotName = "lovelace_config_dashboard-ultrasonic"
        case "/map":
            snapshotName = "lovelace_config_map"
        default:
            throw SnapshotLovelaceConfigProviderError.unknownDashboard(normalizedPath)
        }

        let data = try snapshotData(snapshotName)
        return LovelaceConfiguration(
            dashboardPath: normalizedPath,
            rawJSON: String(data: data, encoding: .utf8),
            config: try decoder.decode(LovelaceRawConfig.self, from: data)
        )
    }

    func configurationRequests() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedConfigurations
    }

    func configurationCallCount(for dashboardPath: String) -> Int {
        let normalizedPath = AppRoute.dashboardPath(dashboardPath)
        lock.lock()
        defer { lock.unlock() }
        return requestedConfigurations.filter { $0 == normalizedPath }.count
    }

    private func recordConfigurationRequest(_ dashboardPath: String) {
        lock.lock()
        requestedConfigurations.append(dashboardPath)
        lock.unlock()
    }

    private func decodeSnapshot<T: Decodable>(_ name: String) throws -> T {
        try decoder.decode(T.self, from: snapshotData(name))
    }

    private func snapshotData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        return try Data(contentsOf: url)
    }
}

private enum SnapshotLovelaceConfigProviderError: Error, Equatable {
    case unknownDashboard(String)
}

private final class MockLovelaceUpdateEventSource: LovelaceUpdateEventSource {
    private var callbacks: [(LovelaceUpdateEvent) -> Void] = []
    private(set) var subscribeCount = 0

    func subscribeLovelaceUpdates(
        onUpdate: @escaping (LovelaceUpdateEvent) -> Void
    ) async throws -> LovelaceUpdateSubscription {
        subscribeCount += 1
        callbacks.append(onUpdate)
        return MockLovelaceUpdateSubscription()
    }

    func emit(_ event: LovelaceUpdateEvent) {
        callbacks.forEach { callback in
            callback(event)
        }
    }
}

private final class MockLovelaceUpdateSubscription: LovelaceUpdateSubscription {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

private final class DelayedLovelaceConfigProvider: LovelaceConfigProvider {
    private let lock = NSLock()
    private var requestedConfigurations: [String] = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var slowConfigurationContinuation: CheckedContinuation<LovelaceConfiguration, Error>?

    func dashboardList() async throws -> [LovelaceDashboardReference] {
        [
            LovelaceDashboardReference(path: "/slow", title: "Slow"),
            LovelaceDashboardReference(path: "/fast", title: "Fast")
        ]
    }

    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        let normalizedPath = AppRoute.dashboardPath(dashboardPath)
        recordConfigurationRequest(normalizedPath)

        if normalizedPath == "/slow" {
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                slowConfigurationContinuation = continuation
                lock.unlock()
            }
        }

        return Self.configuration(path: normalizedPath)
    }

    func waitForConfigurationRequest(_ dashboardPath: String) async {
        let normalizedPath = AppRoute.dashboardPath(dashboardPath)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if requestedConfigurations.contains(normalizedPath) {
                lock.unlock()
                continuation.resume()
            } else {
                requestWaiters[normalizedPath, default: []].append(continuation)
                lock.unlock()
            }
        }
    }

    func finishSlowConfiguration() {
        lock.lock()
        let continuation = slowConfigurationContinuation
        slowConfigurationContinuation = nil
        lock.unlock()
        continuation?.resume(returning: Self.configuration(path: "/slow"))
    }

    func configurationRequests() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedConfigurations
    }

    private func recordConfigurationRequest(_ dashboardPath: String) {
        lock.lock()
        requestedConfigurations.append(dashboardPath)
        let waiters = requestWaiters.removeValue(forKey: dashboardPath) ?? []
        lock.unlock()

        waiters.forEach { $0.resume() }
    }

    private static func configuration(path: String) -> LovelaceConfiguration {
        LovelaceConfiguration(
            dashboardPath: path,
            config: .config(LovelaceConfig(
                views: [LovelaceViewConfig(path: "default")],
                raw: .object([:])
            ))
        )
    }
}

private struct RestrictedViewConfigProvider: LovelaceConfigProvider {
    func dashboardList() async throws -> [LovelaceDashboardReference] {
        [LovelaceDashboardReference(path: "/lovelace", title: "Overview")]
    }

    func configuration(for dashboardPath: String) async throws -> LovelaceConfiguration {
        let config = LovelaceConfig(
            views: [
                LovelaceViewConfig(
                    path: "private",
                    visible: .array([.object(["user": .string("user-a")])])
                ),
                LovelaceViewConfig(path: "public")
            ],
            raw: .object([:])
        )
        return LovelaceConfiguration(
            dashboardPath: dashboardPath,
            config: .config(config)
        )
    }
}
