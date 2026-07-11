import XCTest
@testable import NativeHA
@testable import NativeHACore

final class BasicUsedCardViewTests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"
    private let decoder = JSONDecoder()

    func testEntitiesHeaderToggleHonorsExplicitFalseAndDefaultRule() throws {
        let explicitFalse = try entitiesConfig("""
        {
          "type": "entities",
          "title": "Kettle",
          "show_header_toggle": false,
          "entities": ["switch.kettle", "fan.cooling"]
        }
        """)
        XCTAssertFalse(EntitiesCardView.computeShowHeaderToggle(explicitFalse))

        let defaultWithTwoToggleableRows = try entitiesConfig("""
        {
          "type": "entities",
          "title": "Power",
          "entities": ["switch.one", "fan.two", "sensor.three"]
        }
        """)
        XCTAssertTrue(EntitiesCardView.computeShowHeaderToggle(defaultWithTwoToggleableRows))

        let noTitle = try entitiesConfig("""
        {
          "type": "entities",
          "entities": ["switch.one", "fan.two"]
        }
        """)
        XCTAssertFalse(EntitiesCardView.computeShowHeaderToggle(noTitle))
    }

    func testEntityRowsMapUsedDomainsToNativeRowKinds() throws {
        XCTAssertEqual(EntityRowView.kind(for: try row("\"sensor.temperature\"")), .sensor)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"switch.power\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"fan.air\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"light.room\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"humidifier.room\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"automation.script\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"input_boolean.test\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"script.run\"")), .toggle)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"button.restart\"")), .button)
        XCTAssertEqual(EntityRowView.kind(for: try row("\"person.joy\"")), .simple)

        let explicitButton = try row("""
        {"entity": "sensor.restart", "type": "button"}
        """)
        XCTAssertEqual(EntityRowView.kind(for: explicitButton), .button)
    }

    func testTileIconTapDefaultsUseActionResolver() throws {
        let sensor = try tileConfig("""
        {"type": "tile", "entity": "sensor.temperature"}
        """)
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: sensor,
                entityID: "sensor.temperature",
                states: ["sensor.temperature": entity("sensor.temperature", state: "21")]
            ),
            .none(reason: "No default icon action for sensor.")
        )

        let switchTile = try tileConfig("""
        {"type": "tile", "entity": "switch.power"}
        """)
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: switchTile,
                entityID: "switch.power",
                states: ["switch.power": entity("switch.power", state: "on")]
            ),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_off",
                serviceData: ["entity_id": .string("switch.power")]
            ))
        )

        let buttonTile = try tileConfig("""
        {"type": "tile", "entity": "button.restart"}
        """)
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: buttonTile,
                entityID: "button.restart",
                states: ["button.restart": entity("button.restart", state: "unknown")]
            ),
            .callService(HAServiceCall(
                domain: "button",
                service: "press",
                serviceData: ["entity_id": .string("button.restart")]
            ))
        )
    }

    func testEntityBadgeDisplayDefaultsMatchObjectAndStringConfigs() throws {
        let objectBadge = try badge("""
        {"type": "entity", "entity": "climate.room_ac"}
        """)
        guard case let .entity(objectConfig) = objectBadge else {
            return XCTFail("Expected entity badge")
        }
        XCTAssertEqual(
            EntityBadgeView.DisplayOptions(config: objectConfig),
            EntityBadgeView.DisplayOptions(showName: false, showState: true, showIcon: true)
        )

        let stringBadge = try badge("\"climate.room_ac\"")
        guard case let .entity(stringConfig) = stringBadge else {
            return XCTFail("Expected entity badge")
        }
        XCTAssertEqual(
            EntityBadgeView.DisplayOptions(config: stringConfig),
            EntityBadgeView.DisplayOptions(showName: true, showState: true, showIcon: true)
        )
    }

    func testCapturedDashboardNonHistoryCardsAreNativeNotFallback() throws {
        let snapshotNames = [
            "lovelace_config_lovelace",
            "lovelace_config_all-devices",
            "lovelace_config_dashboard-ultrasonic"
        ]

        for snapshotName in snapshotNames {
            let rawConfig: LovelaceRawConfig = try decodeSnapshot(snapshotName)
            guard case let .config(config) = rawConfig else {
                XCTFail("Expected regular config for \(snapshotName).")
                continue
            }

            let descriptors = allCards(in: config)
                .filter { $0.type != "history-graph" }
                .map(LovelaceElementFactory.descriptor(for:))

            XCTAssertFalse(
                descriptors.contains { $0.renderKind == .fallback },
                "Expected all non-history cards to render natively in \(snapshotName)."
            )
        }
    }

    private func entitiesConfig(_ json: String) throws -> EntitiesCardConfig {
        guard case let .entities(config) = try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8)) else {
            throw TestDecodeError.unexpectedCardType
        }
        return config
    }

    private func tileConfig(_ json: String) throws -> TileCardConfig {
        guard case let .tile(config) = try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8)) else {
            throw TestDecodeError.unexpectedCardType
        }
        return config
    }

    private func row(_ json: String) throws -> LovelaceEntityRowConfig {
        try decoder.decode(LovelaceEntityRowConfig.self, from: Data(json.utf8))
    }

    private func badge(_ json: String) throws -> LovelaceBadgeConfig {
        try decoder.decode(LovelaceBadgeConfig.self, from: Data(json.utf8))
    }

    private func decodeSnapshot<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func allCards(in config: LovelaceConfig) -> [LovelaceCardConfig] {
        config.views.flatMap { view in
            view.cards.flatMap(expandedCards)
                + view.sections.flatMap { section in
                    section.cards.flatMap(expandedCards)
                }
                + view.sidebar.map { sidebar in
                    sidebar.sections.flatMap { section in
                        section.cards.flatMap(expandedCards)
                    }
                }.orEmpty
        }
    }

    private func expandedCards(_ card: LovelaceCardConfig) -> [LovelaceCardConfig] {
        if case let .verticalStack(config) = card {
            return [card] + config.cards.flatMap(expandedCards)
        }
        return [card]
    }

    private func entity(_ entityID: EntityID, state: String) -> HassEntity {
        let date = Date(timeIntervalSince1970: 0)
        return HassEntity(
            entityID: entityID,
            state: state,
            attributes: ["friendly_name": .string(entityID)],
            lastChanged: date,
            lastUpdated: date,
            context: HAContext(id: "context")
        )
    }
}

private enum TestDecodeError: Error {
    case unexpectedCardType
}

private extension Optional where Wrapped == [LovelaceCardConfig] {
    var orEmpty: [LovelaceCardConfig] {
        self ?? []
    }
}
