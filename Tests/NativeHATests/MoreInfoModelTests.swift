import XCTest
@testable import NativeHA
@testable import NativeHACore

final class MoreInfoModelTests: XCTestCase {
    func testMoreInfoActionRoutesSelectedEntity() {
        var openedEntity: EntityID?
        let state = entity(
            "sensor.temperature",
            state: "21.5",
            attributes: [
                "friendly_name": .string("Room temperature"),
                "unit_of_measurement": .string("°C")
            ]
        )

        CardActionDispatcher(
            entityID: state.entityID,
            states: [state.entityID: state],
            onMoreInfo: { openedEntity = $0 },
            onServiceCall: { _ in XCTFail("More-info action should not call a service.") }
        )
        .perform()

        XCTAssertEqual(openedEntity, "sensor.temperature")
    }

    func testGenericMoreInfoModelDisplaysNameStateAndAttributes() {
        let state = entity(
            "sensor.temperature",
            state: "21.5",
            attributes: [
                "friendly_name": .string("Room temperature"),
                "unit_of_measurement": .string("°C"),
                "device_class": .string("temperature")
            ]
        )

        let model = MoreInfoModel.build(entityID: state.entityID, states: [state.entityID: state])

        XCTAssertEqual(model.name, "Room temperature")
        XCTAssertEqual(model.stateDisplay, "21.5 °C")
        XCTAssertEqual(model.domain, "sensor")
        XCTAssertFalse(model.isMissing)
        XCTAssertNil(model.climate)
        XCTAssertTrue(model.attributes.contains(MoreInfoAttributeRow(
            key: "device_class",
            label: "Device class",
            value: "temperature"
        )))
        XCTAssertNotNil(model.lastChangedDisplay)
        XCTAssertNotNil(model.lastUpdatedDisplay)
    }

    func testMissingEntityProducesSafeUnavailableState() {
        let model = MoreInfoModel.build(entityID: "sensor.missing", states: [:])

        XCTAssertEqual(model.entityID, "sensor.missing")
        XCTAssertEqual(model.name, "missing")
        XCTAssertEqual(model.stateDisplay, "missing")
        XCTAssertTrue(model.isMissing)
        XCTAssertTrue(model.isUnavailable)
        XCTAssertTrue(model.attributes.isEmpty)
    }

    func testStateUpdatesAreReflectedWhenModelIsRebuiltFromStoreState() {
        let oldState = entity(
            "sensor.temperature",
            state: "20",
            attributes: [
                "friendly_name": .string("Room temperature"),
                "unit_of_measurement": .string("°C")
            ]
        )
        let newState = entity(
            "sensor.temperature",
            state: "22",
            attributes: [
                "friendly_name": .string("Room temperature"),
                "unit_of_measurement": .string("°C")
            ]
        )

        XCTAssertEqual(
            MoreInfoModel.build(entityID: oldState.entityID, states: [oldState.entityID: oldState]).stateDisplay,
            "20 °C"
        )
        XCTAssertEqual(
            MoreInfoModel.build(entityID: newState.entityID, states: [newState.entityID: newState]).stateDisplay,
            "22 °C"
        )
    }

    func testUnsupportedDomainFallsBackToGenericModel() {
        let state = entity(
            "button.restart",
            state: "unknown",
            attributes: ["friendly_name": .string("Restart")]
        )

        let model = MoreInfoModel.build(entityID: state.entityID, states: [state.entityID: state])

        XCTAssertEqual(model.name, "Restart")
        XCTAssertEqual(model.stateDisplay, "unknown")
        XCTAssertNil(model.climate)
        XCTAssertFalse(model.isMissing)
    }
}

final class ClimateControlModelTests: XCTestCase {
    func testClimateTemperatureFormattingAndOptionsExtraction() throws {
        let model = try XCTUnwrap(ClimateControlModel(stateObj: climateEntity()))

        XCTAssertEqual(model.currentTemperatureDisplay, "26 °C")
        XCTAssertEqual(model.targetTemperatureDisplay, "26.5 °C")
        XCTAssertEqual(model.hvacMode, "cool")
        XCTAssertEqual(model.hvacModes, ["auto", "heat", "cool", "fan_only", "off"])
        XCTAssertEqual(model.presetMode, "eco")
        XCTAssertEqual(model.presetModes, ["none", "eco", "boost"])
        XCTAssertEqual(model.fanMode, "auto")
        XCTAssertEqual(model.fanModes, ["low", "medium", "high", "auto"])
        XCTAssertEqual(model.swingMode, "vertical")
        XCTAssertEqual(model.swingModes, ["off", "vertical", "both"])
        XCTAssertEqual(model.targetTemperatureStep, 0.5)
    }

    func testClimateServiceCallsUseHomeAssistantServicePayloads() throws {
        let model = try XCTUnwrap(ClimateControlModel(stateObj: climateEntity()))

        XCTAssertEqual(
            model.setTemperatureCall(27.5),
            HAServiceCall(
                domain: "climate",
                service: "set_temperature",
                serviceData: [
                    "entity_id": .string("climate.demo"),
                    "temperature": .double(27.5)
                ]
            )
        )

        XCTAssertEqual(
            model.setHVACModeCall("heat"),
            HAServiceCall(
                domain: "climate",
                service: "set_hvac_mode",
                serviceData: [
                    "entity_id": .string("climate.demo"),
                    "hvac_mode": .string("heat")
                ]
            )
        )

        XCTAssertEqual(
            model.setPresetModeCall("boost"),
            HAServiceCall(
                domain: "climate",
                service: "set_preset_mode",
                serviceData: [
                    "entity_id": .string("climate.demo"),
                    "preset_mode": .string("boost")
                ]
            )
        )
        XCTAssertEqual(
            model.setFanModeCall("high"),
            HAServiceCall(
                domain: "climate",
                service: "set_fan_mode",
                serviceData: [
                    "entity_id": .string("climate.demo"),
                    "fan_mode": .string("high")
                ]
            )
        )
        XCTAssertEqual(
            model.setSwingModeCall("both"),
            HAServiceCall(
                domain: "climate",
                service: "set_swing_mode",
                serviceData: [
                    "entity_id": .string("climate.demo"),
                    "swing_mode": .string("both")
                ]
            )
        )

        XCTAssertNil(model.setHVACModeCall("cool"), "Selecting the current mode should no-op.")
        XCTAssertNil(model.setPresetModeCall("missing"), "Unknown options should not produce service calls.")
    }

    func testClimateTemperatureStepAndPartialBoundsUseConfig() throws {
        let maxOnly = entity(
            "climate.partial_bounds",
            state: "heat",
            attributes: [
                "supported_features": .integer(1),
                "temperature": .integer(70),
                "max_temp": .integer(72)
            ]
        )
        let maxOnlyModel = try XCTUnwrap(ClimateControlModel(
            stateObj: maxOnly,
            config: config(temperatureUnit: "F")
        ))

        XCTAssertEqual(maxOnlyModel.targetTemperatureStep, 1)
        XCTAssertEqual(maxOnlyModel.steppedTemperature(75), 72)
        XCTAssertEqual(
            maxOnlyModel.setTemperatureCall(75)?.serviceData["temperature"],
            .double(72)
        )

        let minOnly = entity(
            "climate.partial_bounds",
            state: "heat",
            attributes: [
                "supported_features": .integer(1),
                "temperature": .integer(18),
                "min_temp": .integer(16),
                "target_temp_step": .double(0.5)
            ]
        )
        let minOnlyModel = try XCTUnwrap(ClimateControlModel(stateObj: minOnly))

        XCTAssertEqual(minOnlyModel.targetTemperatureStep, 0.5)
        XCTAssertEqual(minOnlyModel.steppedTemperature(10), 16)
        XCTAssertEqual(
            minOnlyModel.setTemperatureCall(10)?.serviceData["temperature"],
            .double(16)
        )
    }

    func testClimateMissingAttributesDoNotCrash() throws {
        let sparse = entity("climate.sparse", state: "off", attributes: [:])
        let model = try XCTUnwrap(ClimateControlModel(stateObj: sparse))

        XCTAssertEqual(model.hvacMode, "off")
        XCTAssertTrue(model.hvacModes.isEmpty)
        XCTAssertNil(model.currentTemperatureDisplay)
        XCTAssertNil(model.targetTemperature)
        XCTAssertNil(model.nextTemperature(delta: 1))
    }

    func testMalformedClimateAttributesDoNotCrash() throws {
        let malformed = entity(
            "climate.malformed",
            state: "cool",
            attributes: [
                "supported_features": .string("not-a-number"),
                "hvac_modes": .string("cool"),
                "temperature": .string("not-a-number"),
                "min_temp": .string("NaN"),
                "target_temp_step": .string("not-a-number"),
                "preset_modes": .array([.string("eco")]),
                "fan_modes": .array([.string("auto")]),
                "swing_modes": .array([.string("vertical")])
            ]
        )
        let model = try XCTUnwrap(ClimateControlModel(stateObj: malformed))

        XCTAssertTrue(model.hvacModes.isEmpty)
        XCTAssertNil(model.targetTemperature)
        XCTAssertEqual(model.targetTemperatureStep, 0.5)
        XCTAssertTrue(model.presetModes.isEmpty)
        XCTAssertTrue(model.fanModes.isEmpty)
        XCTAssertTrue(model.swingModes.isEmpty)
        XCTAssertEqual(model.steppedTemperature(22.2), 22)
    }

    func testUnavailableClimateSafelyNoOpsControls() throws {
        let unavailable = climateEntity(state: HAStateValue.unavailable)
        let model = try XCTUnwrap(ClimateControlModel(stateObj: unavailable))

        XCTAssertTrue(model.isUnavailable)
        XCTAssertNil(model.setTemperatureCall(25))
        XCTAssertNil(model.setHVACModeCall("cool"))
        XCTAssertNil(model.setPresetModeCall("boost"))
        XCTAssertNil(model.setFanModeCall("high"))
        XCTAssertNil(model.setSwingModeCall("both"))
    }

    func testUnknownClimateSafelyNoOpsControls() throws {
        let unknown = climateEntity(state: HAStateValue.unknown)
        let model = try XCTUnwrap(ClimateControlModel(stateObj: unknown))

        XCTAssertTrue(model.isUnavailable)
        XCTAssertNil(model.setTemperatureCall(25))
        XCTAssertNil(model.setHVACModeCall("cool"))
        XCTAssertNil(model.setPresetModeCall("boost"))
        XCTAssertNil(model.setFanModeCall("high"))
        XCTAssertNil(model.setSwingModeCall("both"))
    }

    func testServiceCallFailureReturnsFailureWithoutThrowing() async {
        let call = HAServiceCall(
            domain: "climate",
            service: "set_hvac_mode",
            serviceData: ["entity_id": .string("climate.demo")]
        )

        let result = await HAServiceCallExecution.execute(call) { _ in
            throw TestServiceError.failed
        }

        XCTAssertEqual(result, .failed)
    }
}

final class Module12TileActionTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testExplicitTileTapAndIconActionsPreserveLovelacePrecedence() throws {
        let config = try tileConfig("""
        {
          "type": "tile",
          "entity": "switch.power",
          "tap_action": {"action": "toggle"},
          "icon_tap_action": {"action": "more-info", "entity": "sensor.detail"}
        }
        """)
        let states = ["switch.power": entity("switch.power", state: "on", attributes: [:])]

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                gesture: .tap,
                tapAction: config.tapAction,
                context: LovelaceActionResolutionContext(entity: "switch.power", states: states)
            ),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_off",
                serviceData: ["entity_id": .string("switch.power")]
            ))
        )
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: config,
                entityID: "switch.power",
                states: states
            ),
            .moreInfo(entityID: "sensor.detail")
        )
    }

    func testClimateTileDefaultsToToggle() throws {
        let config = try tileConfig("""
        {"type": "tile", "entity": "climate.demo"}
        """)
        let states = ["climate.demo": climateEntity()]
        let context = LovelaceActionResolutionContext(entity: "climate.demo", states: states)

        XCTAssertEqual(
            LovelaceActionResolver.resolve(
                gesture: .tap,
                tapAction: config.tapAction,
                context: context
            ),
            .moreInfo(entityID: "climate.demo")
        )
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: config,
                entityID: "climate.demo",
                states: states
            ),
            .callService(HAServiceCall(
                domain: "climate",
                service: "turn_off",
                serviceData: ["entity_id": .string("climate.demo")]
            ))
        )
    }

    func testExistingSwitchFanAndButtonTileActionsDoNotRegress() throws {
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: try tileConfig(#"{"type": "tile", "entity": "switch.power"}"#),
                entityID: "switch.power",
                states: ["switch.power": entity("switch.power", state: "off", attributes: [:])]
            ),
            .callService(HAServiceCall(
                domain: "switch",
                service: "turn_on",
                serviceData: ["entity_id": .string("switch.power")]
            ))
        )
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: try tileConfig(#"{"type": "tile", "entity": "fan.air"}"#),
                entityID: "fan.air",
                states: ["fan.air": entity("fan.air", state: "on", attributes: [:])]
            ),
            .callService(HAServiceCall(
                domain: "fan",
                service: "turn_off",
                serviceData: ["entity_id": .string("fan.air")]
            ))
        )
        XCTAssertEqual(
            TileCardView.resolveIconTapAction(
                config: try tileConfig(#"{"type": "tile", "entity": "button.restart"}"#),
                entityID: "button.restart",
                states: ["button.restart": entity("button.restart", state: "unknown", attributes: [:])]
            ),
            .callService(HAServiceCall(
                domain: "button",
                service: "press",
                serviceData: ["entity_id": .string("button.restart")]
            ))
        )
    }

    func testUnknownCardFallbackUnchanged() throws {
        let card = try decoder.decode(LovelaceCardConfig.self, from: Data("""
        {"type": "custom:unknown-card", "entity": "sensor.demo"}
        """.utf8))

        XCTAssertEqual(LovelaceElementFactory.descriptor(for: card).renderKind, .fallback)
    }

    private func tileConfig(_ json: String) throws -> TileCardConfig {
        guard case let .tile(config) = try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8)) else {
            throw TestDecodeError.unexpectedCardType
        }
        return config
    }
}

private enum TestDecodeError: Error {
    case unexpectedCardType
}

private enum TestServiceError: Error {
    case failed
}

private func climateEntity(state: String = "cool") -> HassEntity {
    entity(
        "climate.demo",
        state: state,
        attributes: [
            "friendly_name": .string("Demo climate"),
            "supported_features": .integer(57),
            "hvac_modes": .array([
                .string("off"),
                .string("cool"),
                .string("heat"),
                .string("fan_only"),
                .string("auto")
            ]),
            "current_temperature": .integer(26),
            "temperature": .double(26.5),
            "min_temp": .integer(16),
            "max_temp": .integer(30),
            "target_temp_step": .double(0.5),
            "preset_mode": .string("eco"),
            "preset_modes": .array([.string("none"), .string("eco"), .string("boost")]),
            "fan_mode": .string("auto"),
            "fan_modes": .array([.string("low"), .string("medium"), .string("high"), .string("auto")]),
            "swing_mode": .string("vertical"),
            "swing_modes": .array([.string("off"), .string("vertical"), .string("both")])
        ]
    )
}

private func entity(
    _ entityID: EntityID,
    state: String,
    attributes: [String: HAJSONValue]
) -> HassEntity {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    return HassEntity(
        entityID: entityID,
        state: state,
        attributes: attributes,
        lastChanged: date,
        lastUpdated: date,
        context: HAContext(id: "module12-test")
    )
}

private func config(temperatureUnit: String = "°C") -> HAConfig {
    HAConfig(
        latitude: 0,
        longitude: 0,
        elevation: 0,
        locationName: "Home",
        timeZone: "UTC",
        unitSystem: ["temperature": temperatureUnit],
        version: "test",
        components: ["climate"],
        configDir: nil,
        configSource: nil,
        country: nil,
        currency: nil,
        language: "en",
        internalURL: nil,
        externalURL: nil,
        safeMode: false,
        recoveryMode: nil,
        state: nil
    )
}
