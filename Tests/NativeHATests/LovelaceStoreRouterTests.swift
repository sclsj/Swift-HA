import Foundation
import XCTest
@testable import NativeHACore

final class LovelaceStoreRouterTests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"

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
        try await Task.sleep(nanoseconds: 50_000_000)
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
