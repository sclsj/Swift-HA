import XCTest
@testable import NativeHACore

final class EntityFormattingDomainLogicActionTests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"
    private let decoder = JSONDecoder()

    func testFormatsRepresentativeInventoryEntities() throws {
        let states = try stateMap()
        let registry = try registryMap()
        let config: HAConfig = try decode("get_config")

        let chipTemperature = try XCTUnwrap(states["sensor.cmpower_w1_7ac38d_19_xin_pian_wen_du"])
        XCTAssertEqual(EntityIDParser.domain(from: chipTemperature.entityID), "sensor")
        XCTAssertEqual(EntityIDParser.objectID(from: chipTemperature.entityID), "cmpower_w1_7ac38d_19_xin_pian_wen_du")
        XCTAssertEqual(HAEntityFormatting.displayName(for: chipTemperature), "Ultrasonic 19.芯片温度")
        XCTAssertEqual(
            HAEntityFormatting.stateDisplay(
                for: chipTemperature,
                registryEntry: registry[chipTemperature.entityID],
                config: config
            ),
            "53.7 °C"
        )

        let particulate = try XCTUnwrap(states["sensor.sps30_pm2_5"])
        XCTAssertEqual(
            HAEntityFormatting.stateDisplay(
                for: particulate,
                registryEntry: registry[particulate.entityID],
                config: config
            ),
            "13.51 μg/m³"
        )

        let unavailableTemperature = try XCTUnwrap(states["sensor.humidity_temp_temperature"])
        XCTAssertEqual(HAEntityFormatting.stateDisplay(for: unavailableTemperature), "unavailable")

        let runtimeSeconds = try XCTUnwrap(states["sensor.cmpower_w1_7ac38d_11_xi_tong_yun_xing_shi_jian"])
        XCTAssertEqual(
            HAEntityFormatting.stateDisplay(
                for: runtimeSeconds,
                registryEntry: registry[runtimeSeconds.entityID],
                config: config
            ),
            "14 d 18 h 12 min 54 s"
        )

        let runtimeHours = try XCTUnwrap(states["sensor.ultrasonic_30_fen_kong_lei_ji_yun_xing_shi_jian"])
        XCTAssertEqual(HAEntityFormatting.stateDisplay(for: runtimeHours, config: config), "39 min 56 s")

        let fan = try XCTUnwrap(states["fan.ac_unit_controller_ac_fan"])
        XCTAssertEqual(HAEntityFormatting.defaultStateContentDisplay(for: fan, config: config), "33%")

        let climate = try XCTUnwrap(states["climate.room_ac"])
        XCTAssertEqual(HAEntityFormatting.defaultStateContentDisplay(for: climate, config: config), "off · 28.3 °C")

        let weather = try XCTUnwrap(states["weather.forecast_wo_de_jia"])
        XCTAssertEqual(HAEntityFormatting.attributeDisplay(for: weather, attribute: "temperature", config: config), "27.1 °C")
        XCTAssertEqual(HAEntityFormatting.attributeDisplay(for: weather, attribute: "humidity", config: config), "80%")

        let fallback = makeEntity(entityID: "sensor.demo_sensor", state: "on", attributes: [:])
        XCTAssertEqual(HAEntityFormatting.displayName(for: fallback), "demo sensor")
    }

    func testActiveStateAndDeterministicStateColorsUseInventoryDomains() throws {
        let states = try stateMap()

        let activeSwitch = try XCTUnwrap(states["switch.cmpower_w1_7ac38d_32_zong_kong_kai_guan"])
        XCTAssertTrue(HADomainLogic.isActive(activeSwitch))
        XCTAssertEqual(HAStateColorResolver.color(for: activeSwitch), .init(name: "state-active", hex: "#fdd663"))

        let inactiveSwitch = try XCTUnwrap(states["switch.cmpower_w1_7ac38d_44_qi_yong_xia_mian_de_si_ge_cao_zuo"])
        XCTAssertFalse(HADomainLogic.isActive(inactiveSwitch))
        XCTAssertEqual(HAStateColorResolver.color(for: inactiveSwitch), .init(name: "state-inactive", hex: "#44739e"))

        let unavailableSwitch = try XCTUnwrap(states["switch.esp32_ultrasonic_ultrasonic"])
        XCTAssertFalse(HADomainLogic.isActive(unavailableSwitch))
        XCTAssertEqual(HAStateColorResolver.color(for: unavailableSwitch), .init(name: "state-unavailable", hex: "#bdbdbd"))

        let person = try XCTUnwrap(states["person.joy"])
        XCTAssertTrue(HADomainLogic.isActive(person))
        XCTAssertEqual(HAStateColorResolver.color(for: person), .init(name: "state-active-blue", hex: "#039be5"))

        let weather = try XCTUnwrap(states["weather.forecast_wo_de_jia"])
        XCTAssertTrue(HADomainLogic.isActive(weather))
        XCTAssertEqual(HAStateColorResolver.color(for: weather), .init(name: "state-active-blue", hex: "#039be5"))
    }

    func testVisibilityConditionsCoverStateAndNumericState() throws {
        let states = try stateMap()
        let context = LovelaceVisibilityContext(
            states: states,
            entityID: "switch.cmpower_w1_7ac38d_32_zong_kong_kai_guan"
        )

        XCTAssertTrue(LovelaceCardVisibility.isVisible(
            conditions: [
                .object([
                    "condition": .string("state"),
                    "state": .string("on")
                ])
            ],
            context: context
        ))

        XCTAssertFalse(LovelaceCardVisibility.isVisible(
            conditions: [
                .object([
                    "condition": .string("state"),
                    "state": .string("off")
                ])
            ],
            context: context
        ))

        XCTAssertTrue(LovelaceCardVisibility.isVisible(
            conditions: [
                .object([
                    "condition": .string("numeric_state"),
                    "entity": .string("sensor.cmpower_w1_7ac38d_19_xin_pian_wen_du"),
                    "above": .integer(50),
                    "below": .integer(60)
                ])
            ],
            context: context
        ))

        XCTAssertTrue(LovelaceCardVisibility.isVisible(
            conditions: [
                .object([
                    "condition": .string("numeric_state"),
                    "entity": .string("weather.forecast_wo_de_jia"),
                    "attribute": .string("humidity"),
                    "above": .integer(75),
                    "below": .integer(90)
                ])
            ],
            context: context
        ))

        XCTAssertFalse(LovelaceCardVisibility.isVisible(
            conditions: [
                .object([
                    "condition": .string("numeric_state"),
                    "entity": .string("sensor.cmpower_w1_7ac38d_19_xin_pian_wen_du"),
                    "below": .integer(40)
                ])
            ],
            context: context
        ))
    }

    func testActionResolutionDefaultsAndToggleServiceMapping() throws {
        var states = try stateMap()
        states["light.demo"] = makeEntity(entityID: "light.demo", state: "off", attributes: [:])

        let activeSwitchContext = LovelaceActionResolutionContext(
            entity: "switch.cmpower_w1_7ac38d_32_zong_kong_kai_guan",
            states: states
        )
        XCTAssertEqual(
            LovelaceActionResolver.resolve(LovelaceActionConfig(action: "toggle"), context: activeSwitchContext),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_off",
                serviceData: ["entity_id": .string("switch.cmpower_w1_7ac38d_32_zong_kong_kai_guan")]
            ))
        )

        let inactiveSwitchContext = LovelaceActionResolutionContext(
            entity: "switch.cmpower_w1_7ac38d_44_qi_yong_xia_mian_de_si_ge_cao_zuo",
            states: states
        )
        XCTAssertEqual(
            LovelaceActionResolver.resolve(LovelaceActionConfig(action: "toggle"), context: inactiveSwitchContext),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_on",
                serviceData: ["entity_id": .string("switch.cmpower_w1_7ac38d_44_qi_yong_xia_mian_de_si_ge_cao_zuo")]
            ))
        )

        let fanContext = LovelaceActionResolutionContext(entity: "fan.ac_unit_controller_ac_fan", states: states)
        XCTAssertEqual(
            LovelaceActionResolver.resolve(LovelaceActionConfig(action: "toggle"), context: fanContext),
            .callService(HAServiceCall(
                domain: "fan",
                service: "turn_on",
                serviceData: ["entity_id": .string("fan.ac_unit_controller_ac_fan")]
            ))
        )

        let buttonContext = LovelaceActionResolutionContext(
            entity: "button.cmpower_w1_7ac38d_45_xiao_zhun_dian_li_shu_ju",
            states: states
        )
        XCTAssertEqual(
            LovelaceActionResolver.resolveTileIconTap(explicitAction: nil, context: buttonContext),
            .callService(HAServiceCall(
                domain: "button",
                service: "press",
                serviceData: ["entity_id": .string("button.cmpower_w1_7ac38d_45_xiao_zhun_dian_li_shu_ju")]
            ))
        )

        let genericContext = LovelaceActionResolutionContext(entity: "light.demo", states: states)
        XCTAssertEqual(
            LovelaceActionResolver.resolve(LovelaceActionConfig(action: "toggle"), context: genericContext),
            .callService(HAServiceCall(
                domain: "light",
                service: "turn_on",
                serviceData: ["entity_id": .string("light.demo")]
            ))
        )

        XCTAssertEqual(
            LovelaceActionResolver.resolve(gesture: .tap, context: activeSwitchContext),
            .moreInfo(entityID: "switch.cmpower_w1_7ac38d_32_zong_kong_kai_guan")
        )

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                LovelaceActionConfig(action: "navigate", navigationPath: "/lovelace/ultrasonic", navigationReplace: true),
                context: activeSwitchContext
            ),
            .navigate(path: "/lovelace/ultrasonic", replace: true)
        )

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                LovelaceActionConfig(action: "url", urlPath: "https://example.test"),
                context: activeSwitchContext
            ),
            .openURL("https://example.test")
        )

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                LovelaceActionConfig(
                    action: "perform-action",
                    performAction: "switch.turn_on",
                    data: ["entity_id": .string("switch.demo")]
                ),
                context: activeSwitchContext
            ),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_on",
                serviceData: ["entity_id": .string("switch.demo")]
            ))
        )

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                LovelaceActionConfig(
                    action: "call-service",
                    service: "button.press",
                    serviceData: ["entity_id": .string("button.demo")]
                ),
                context: activeSwitchContext
            ),
            .callService(HAServiceCall(
                domain: "button",
                service: "press",
                serviceData: ["entity_id": .string("button.demo")]
            ))
        )
    }

    private func stateMap() throws -> [EntityID: HassEntity] {
        let states: [HassEntity] = try decode("get_states")
        return Dictionary(uniqueKeysWithValues: states.map { ($0.entityID, $0) })
    }

    private func registryMap() throws -> [EntityID: HAEntityRegistryDisplayEntry] {
        let response: HAEntityRegistryDisplayResponse = try decode("entity_registry_display")
        return response.expandedEntities
    }

    private func decode<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func makeEntity(
        entityID: EntityID,
        state: String,
        attributes: [String: HAJSONValue]
    ) -> HassEntity {
        HassEntity(
            entityID: entityID,
            state: state,
            attributes: attributes,
            lastChanged: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0),
            context: HAContext(id: "test")
        )
    }
}
