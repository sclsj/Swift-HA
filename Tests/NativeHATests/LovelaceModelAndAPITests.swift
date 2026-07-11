import XCTest
@testable import NativeHACore

final class LovelaceModelAndAPITests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"
    private let decoder = JSONDecoder()

    func testDecodesLovelaceDashboardListSnapshot() throws {
        let dashboards: [LovelaceDashboard] = try decodeSnapshot("lovelace_dashboards")

        XCTAssertEqual(dashboards.count, 4)
        XCTAssertEqual(dashboards.first { $0.urlPath == "lovelace" }?.title, "Overview")
        XCTAssertEqual(dashboards.first { $0.urlPath == "map" }?.icon, "mdi:map")
        XCTAssertEqual(dashboards.first { $0.urlPath == "all-devices" }?.mode, "storage")
        XCTAssertEqual(dashboards.first { $0.urlPath == "dashboard-ultrasonic" }?.showInSidebar, true)
    }

    func testLovelaceViewConfigLayoutPrecedence() throws {
        XCTAssertEqual(LovelaceViewConfig(panel: false, type: "panel").layout, .panel)
        XCTAssertEqual(LovelaceViewConfig(panel: true, type: "sidebar").layout, .sidebar)
        XCTAssertEqual(LovelaceViewConfig(panel: true, type: "custom:test").layout, .custom("custom:test"))
        
        XCTAssertEqual(LovelaceViewConfig(panel: true).layout, .panel)
        
        // completely empty config falls back to .sections
        XCTAssertEqual(LovelaceViewConfig().layout, .sections)
        
        let masonryConfig: LovelaceViewConfig = try decodeInline("""
        {"cards": [{"type": "markdown", "content": "hello"}]}
        """)
        XCTAssertEqual(masonryConfig.layout, .masonry)

        let sectionsConfig: LovelaceViewConfig = try decodeInline("""
        {"sections": [{"cards": []}]}
        """)
        XCTAssertEqual(sectionsConfig.layout, .sections)
    }

    func testDecodesOverviewDashboardCardsBadgesAndKeyFields() throws {
        let rawConfig: LovelaceRawConfig = try decodeSnapshot("lovelace_config_lovelace")
        guard case let .config(config) = rawConfig else {
            XCTFail("Expected regular Lovelace config.")
            return
        }

        XCTAssertEqual(config.views.count, 3)
        let home = config.views[0]
        XCTAssertEqual(home.path, "default_view")
        XCTAssertEqual(home.title, "Home")
        XCTAssertEqual(home.layout, .masonry)

        if case let .entity(badge)? = home.badges.first {
            XCTAssertEqual(badge.entity, "climate.room_ac")
            XCTAssertNil(badge.showName)
            XCTAssertEqual(badge.raw.objectValue?["type"], .string("entity"))
        } else {
            XCTFail("Expected entity badge.")
        }

        let cards = allCards(in: config)
        let cardTypes = Set(cards.map(\.type))
        XCTAssertTrue(cardTypes.isSuperset(of: [
            "entities",
            "history-graph",
            "weather-forecast",
            "markdown",
            "vertical-stack"
        ]))

        guard case let .verticalStack(stack)? = home.cards.first else {
            XCTFail("Expected first home card to be a vertical stack.")
            return
        }
        XCTAssertEqual(stack.cards.count, 1)

        guard case let .entities(stackEntities)? = stack.cards.first else {
            XCTFail("Expected vertical stack child to be an entities card.")
            return
        }
        XCTAssertEqual(stackEntities.title, "温湿度")
        XCTAssertEqual(stackEntities.entities.first?.entity, "sensor.qtpy_sensors_bme688_temperature")

        let weatherCards = cards.compactMap { card -> WeatherForecastCardConfig? in
            guard case let .weatherForecast(config) = card else {
                return nil
            }
            return config
        }
        XCTAssertEqual(weatherCards.first?.entity, "weather.forecast_wo_de_jia")
        XCTAssertEqual(weatherCards.first?.showForecast, false)

        let markdownCards = cards.compactMap { card -> MarkdownCardConfig? in
            guard case let .markdown(config) = card else {
                return nil
            }
            return config
        }
        XCTAssertTrue(markdownCards.first?.content?.contains("input_number.kettle_run_duration") == true)

        let historyCards = cards.compactMap { card -> HistoryGraphCardConfig? in
            guard case let .historyGraph(config) = card else {
                return nil
            }
            return config
        }
        XCTAssertTrue(historyCards.contains { $0.title == "Temp/Humidity" && $0.hoursToShow == 1 })
        XCTAssertTrue(historyCards.contains { $0.hoursToShow == 3 })
        XCTAssertTrue(historyCards.contains { $0.hoursToShow == 12 })

        let heaterHistory = historyCards.first {
            $0.entities.first?.entity == "binary_sensor.heater_active" && $0.hoursToShow == 1
        }
        XCTAssertEqual(heaterHistory?.refreshInterval, 0)
        XCTAssertEqual(heaterHistory?.raw.objectValue?["refresh_interval"], .integer(0))

        let sensorEntities = cards.compactMap { card -> EntitiesCardConfig? in
            guard case let .entities(config) = card, config.title == "Sensor" else {
                return nil
            }
            return config
        }.first
        XCTAssertEqual(sensorEntities?.entities.first { $0.entity == "sensor.sps30_pm1_0" }?.name, "PM1.0")
    }

    func testDecodesSectionsDashboardsAndTileFields() throws {
        let allDevicesRaw: LovelaceRawConfig = try decodeSnapshot("lovelace_config_all-devices")
        guard case let .config(allDevices) = allDevicesRaw else {
            XCTFail("Expected regular all-devices config.")
            return
        }

        let allDevicesView = try XCTUnwrap(allDevices.views.first)
        XCTAssertEqual(allDevicesView.layout, .sections)
        XCTAssertEqual(allDevicesView.sections.count, 3)
        XCTAssertEqual(allDevicesView.sections.map(\.type), ["grid", "grid", "grid"])

        guard case let .heading(firstHeading)? = allDevicesView.sections.first?.cards.first else {
            XCTFail("Expected section heading.")
            return
        }
        XCTAssertEqual(firstHeading.heading, "New section")

        guard case let .heading(bmeHeading)? = allDevicesView.sections[1].cards.first else {
            XCTFail("Expected BME688 heading.")
            return
        }
        XCTAssertEqual(bmeHeading.heading, "BME688")
        XCTAssertEqual(bmeHeading.headingStyle, "title")

        guard case let .historyGraph(bmeHistory)? = allDevicesView.sections[1].cards.dropFirst().first else {
            XCTFail("Expected BME688 history graph.")
            return
        }
        XCTAssertEqual(bmeHistory.title, "BME688")
        XCTAssertEqual(bmeHistory.hoursToShow, 1)
        XCTAssertEqual(bmeHistory.entities.count, 4)

        let ultrasonicRaw: LovelaceRawConfig = try decodeSnapshot("lovelace_config_dashboard-ultrasonic")
        guard case let .config(ultrasonic) = ultrasonicRaw else {
            XCTFail("Expected regular ultrasonic config.")
            return
        }

        let ultrasonicView = try XCTUnwrap(ultrasonic.views.first)
        XCTAssertEqual(ultrasonicView.type, "sections")
        XCTAssertEqual(ultrasonicView.layout, .sections)
        XCTAssertEqual(ultrasonicView.sections.count, 1)

        let tiles = ultrasonicView.sections[0].cards.compactMap { card -> TileCardConfig? in
            guard case let .tile(config) = card else {
                return nil
            }
            return config
        }
        XCTAssertEqual(tiles.count, 25)
        XCTAssertEqual(tiles.first?.entity, "sensor.cmpower_w1_7ac38d_11_xi_tong_yun_xing_shi_jian")
        XCTAssertTrue(tiles.contains { $0.entity == "button.cmpower_w1_7ac38d_45_xiao_zhun_dian_li_shu_ju" })
        XCTAssertTrue(tiles.contains { $0.entity == "switch.cmpower_w1_7ac38d_49_zhong_qi_xi_tong" })
    }

    func testDecodesStrategyResourcesAndInfoSnapshots() throws {
        let mapConfig: LovelaceRawConfig = try decodeSnapshot("lovelace_config_map")
        XCTAssertTrue(mapConfig.isStrategyDashboard)
        XCTAssertEqual(mapConfig.strategy?.type, "map")
        XCTAssertEqual(mapConfig.views.count, 0)

        let resources: [LovelaceResource] = try decodeSnapshot("lovelace_resources")
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.type, "module")
        XCTAssertEqual(resources.first?.url, "/hacsfiles/apexcharts-card/apexcharts-card.js?hacstag=331701152223")

        let info: LovelaceInfo = try decodeSnapshot("lovelace_info")
        XCTAssertEqual(info.resourceMode, "storage")
    }

    func testUnknownCardsAndKnownCardExtraKeysPreserveRawJSON() throws {
        let config: LovelaceRawConfig = try decodeInline("""
        {
          "views": [
            {
              "cards": [
                {
                  "type": "history-graph",
                  "entities": ["sensor.temperature"],
                  "refresh_interval": 0,
                  "future_option": {"enabled": true}
                },
                {
                  "type": "custom:apexcharts-card",
                  "entity": "sensor.temperature",
                  "nested": {"answer": 42}
                }
              ]
            }
          ]
        }
        """)

        let cards = allCards(in: config)
        guard case let .historyGraph(history)? = cards.first else {
            XCTFail("Expected typed history graph.")
            return
        }
        XCTAssertEqual(history.refreshInterval, 0)
        XCTAssertEqual(history.raw.objectValue?["future_option"]?.objectValue?["enabled"], .bool(true))

        guard case let .unknown(unknown)? = cards.dropFirst().first else {
            XCTFail("Expected unknown custom card.")
            return
        }
        XCTAssertEqual(unknown.type, "custom:apexcharts-card")
        XCTAssertEqual(unknown.raw.objectValue?["nested"]?.objectValue?["answer"], .integer(42))
    }

    func testLovelaceAPISendsExpectedWebSocketRequests() async throws {
        let client = MockLovelaceWebSocketClient(snapshotDirectory: snapshotDirectory)
        try client.enqueueSnapshot("lovelace_dashboards")
        try client.enqueueSnapshot("lovelace_config_map")
        try client.enqueueSnapshot("lovelace_resources")
        try client.enqueueSnapshot("lovelace_info")

        let api = LovelaceAPI(client: client)
        let dashboards = try await api.dashboards()
        let config = try await api.configuration(urlPath: "/map", force: true)
        let resources = try await api.resources()
        let info = try await api.info()

        XCTAssertEqual(dashboards.count, 4)
        XCTAssertEqual(config.strategy?.type, "map")
        XCTAssertEqual(resources.first?.type, "module")
        XCTAssertEqual(info.resourceMode, "storage")

        let requests = client.sentRequests()
        XCTAssertEqual(requests[0]["type"], .string("lovelace/dashboards/list"))
        XCTAssertEqual(requests[1]["type"], .string("lovelace/config"))
        XCTAssertEqual(requests[1]["url_path"], .string("map"))
        XCTAssertEqual(requests[1]["force"], .bool(true))
        XCTAssertEqual(requests[2]["type"], .string("lovelace/resources"))
        XCTAssertEqual(requests[3]["type"], .string("lovelace/info"))
    }

    func testProviderAdaptsTypedAPIToExistingAppProtocol() async throws {
        let client = MockLovelaceWebSocketClient(snapshotDirectory: snapshotDirectory)
        try client.enqueueSnapshot("lovelace_dashboards")
        try client.enqueueSnapshot("lovelace_config_lovelace")

        let provider = HALovelaceConfigProvider(client: client)
        let dashboards = try await provider.dashboardList()
        let configuration = try await provider.configuration(for: "/lovelace")

        XCTAssertEqual(dashboards.first { $0.path == "/lovelace" }?.title, "Overview")
        XCTAssertEqual(configuration.dashboardPath, "/lovelace")
        XCTAssertEqual(configuration.config?.views.count, 3)
        XCTAssertNotNil(configuration.rawJSON)

        let requests = client.sentRequests()
        XCTAssertEqual(requests[1]["type"], .string("lovelace/config"))
        XCTAssertEqual(requests[1]["url_path"], .string("lovelace"))
        XCTAssertEqual(requests[1]["force"], .bool(false))
    }

    private func decodeSnapshot<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func decodeInline<T: Decodable>(_ json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try decoder.decode(T.self, from: data)
    }

    private func allCards(in config: LovelaceConfig) -> [LovelaceCardConfig] {
        config.views.flatMap(allCards(in:))
    }

    private func allCards(in rawConfig: LovelaceRawConfig) -> [LovelaceCardConfig] {
        rawConfig.views.flatMap(allCards(in:))
    }

    private func allCards(in view: LovelaceViewConfig) -> [LovelaceCardConfig] {
        let directCards = view.cards + view.sections.flatMap(\.cards)
        return directCards.flatMap(expandStackCards)
    }

    private func expandStackCards(_ card: LovelaceCardConfig) -> [LovelaceCardConfig] {
        if case let .verticalStack(stack) = card {
            return [card] + stack.cards.flatMap(expandStackCards)
        }
        return [card]
    }
}

private final class MockLovelaceWebSocketClient: HAWebSocketClientProtocol {
    private let snapshotDirectory: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var requests: [[String: HAJSONValue]] = []
    private var responses: [HAJSONValue] = []

    init(snapshotDirectory: String) {
        self.snapshotDirectory = snapshotDirectory
    }

    func connect() async throws {}

    func disconnect() async {}

    func callWS<T: Decodable, Message: Encodable>(_ message: Message) async throws -> T {
        let requestData = try encoder.encode(message)
        requests.append(try decoder.decode([String: HAJSONValue].self, from: requestData))

        let response = responses.removeFirst()
        let responseData = try encoder.encode(response)
        return try decoder.decode(T.self, from: responseData)
    }

    func subscribe<T: Decodable, Message: Encodable>(
        _ message: Message,
        onEvent: @escaping (T) -> Void
    ) async throws -> HASubscription {
        throw HAWebSocketClientError.disconnected
    }

    func enqueueSnapshot(_ name: String) throws {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        let data = try Data(contentsOf: url)
        responses.append(try decoder.decode(HAJSONValue.self, from: data))
    }

    func sentRequests() -> [[String: HAJSONValue]] {
        requests
    }
}
