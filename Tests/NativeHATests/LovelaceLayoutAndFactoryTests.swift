import XCTest
@testable import NativeHA
@testable import NativeHACore

final class LovelaceLayoutAndFactoryTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"

    func testFactoryClassifiesNativeAndFallbackCards() throws {
        let entities = try decodeCard("""
        {
          "type": "entities",
          "title": "Kitchen",
          "entities": ["sensor.temperature"]
        }
        """)
        let entitiesDescriptor = LovelaceElementFactory.descriptor(for: entities)

        XCTAssertEqual(entitiesDescriptor.renderKind, .nativePlaceholder)
        XCTAssertEqual(entitiesDescriptor.type, "entities")
        XCTAssertEqual(entitiesDescriptor.title, "Kitchen")
        XCTAssertEqual(entitiesDescriptor.entityID, "sensor.temperature")

        let unknown = try decodeCard("""
        {
          "type": "custom:apexcharts-card",
          "entity": "sensor.temperature",
          "title": "Temperature",
          "graph_span": "12h"
        }
        """)
        let unknownDescriptor = LovelaceElementFactory.descriptor(for: unknown)

        XCTAssertEqual(unknownDescriptor.renderKind, .fallback)
        XCTAssertTrue(unknownDescriptor.debugHints.contains("type: custom:apexcharts-card"))
        XCTAssertTrue(unknownDescriptor.debugHints.contains("title: Temperature"))
        XCTAssertTrue(unknownDescriptor.debugHints.contains("entity: sensor.temperature"))
        XCTAssertTrue(unknownDescriptor.rawSummary.contains("graph_span"))
    }

    func testCapturedDashboardCardsCanProduceRenderDescriptors() throws {
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

            let descriptors = allCards(in: config).map(LovelaceElementFactory.descriptor(for:))
            XCTAssertFalse(descriptors.isEmpty, "Expected cards in \(snapshotName).")
            XCTAssertFalse(
                descriptors.contains { $0.renderKind == .error },
                "No captured card should have an invalid type in \(snapshotName)."
            )
        }
    }

    func testMasonrySizingUsesHomeAssistantLikeBreakpointsAndPlacement() {
        XCTAssertEqual(CardGridSizing.masonryColumnCount(for: 299), 1)
        XCTAssertEqual(CardGridSizing.masonryColumnCount(for: 600), 2)
        XCTAssertEqual(CardGridSizing.masonryColumnCount(for: 1_200), 4)

        let assignments = CardGridSizing.masonryColumnAssignments(
            cardSizes: [4, 3, 2, 1, 5],
            columnCount: 2
        )
        XCTAssertEqual(assignments, [[0, 1], [2, 3, 4]])
    }

    func testGridSizingMigratesLayoutOptionsAndClampsGridOptions() throws {
        let gridCard = try decodeCard("""
        {
          "type": "entities",
          "entities": ["sensor.temperature"],
          "grid_options": {
            "columns": 16,
            "max_columns": 12,
            "rows": 6,
            "max_rows": 4
          }
        }
        """)
        XCTAssertEqual(
            CardGridSizing.gridSize(for: gridCard),
            LovelaceCardGridSize(rows: .count(4), columns: .count(12))
        )

        let layoutCard = try decodeCard("""
        {
          "type": "entities",
          "entities": ["sensor.temperature"],
          "layout_options": {
            "grid_columns": 2,
            "grid_max_columns": 3,
            "grid_rows": 4
          }
        }
        """)
        XCTAssertEqual(
            CardGridSizing.gridSize(for: layoutCard),
            LovelaceCardGridSize(rows: .count(4), columns: .count(6))
        )

        let heading = try decodeCard("""
        {
          "type": "heading",
          "heading": "BME688"
        }
        """)
        XCTAssertEqual(
            CardGridSizing.gridSize(for: heading),
            LovelaceCardGridSize(rows: .count(1), columns: .full)
        )
    }

    func testVisibilityFiltersCardsWithoutMutatingConfigState() throws {
        let visible = try decodeCard("""
        {
          "type": "entities",
          "entities": ["sensor.visible"],
          "visibility": [
            {"condition": "state", "entity": "sensor.mode", "state": "on"}
          ]
        }
        """)
        let hiddenByState = try decodeCard("""
        {
          "type": "entities",
          "entities": ["sensor.hidden"],
          "visibility": [
            {"condition": "state", "entity": "sensor.mode", "state": "off"}
          ]
        }
        """)
        let disabled = try decodeCard("""
        {
          "type": "tile",
          "entity": "switch.disabled",
          "disabled": true
        }
        """)

        let cards = [visible, hiddenByState, disabled]
        let states = ["sensor.mode": entity("sensor.mode", state: "on")]
        let filtered = LovelaceElementFactory.visibleCards(
            cards,
            states: states,
            maxColumns: 2
        )

        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(LovelaceElementFactory.primaryEntityID(for: filtered[0]), "sensor.visible")
    }

    private func decodeCard(_ json: String) throws -> LovelaceCardConfig {
        try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8))
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

private extension Optional where Wrapped == [LovelaceCardConfig] {
    var orEmpty: [LovelaceCardConfig] {
        self ?? []
    }
}
