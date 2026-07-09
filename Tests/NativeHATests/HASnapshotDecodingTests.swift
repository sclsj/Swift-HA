import XCTest
@testable import NativeHACore

final class HASnapshotDecodingTests: XCTestCase {
    private let snapshotDirectory = "/Users/jin/Documents/HA/ha_frontend_spec/snapshots"
    private let decoder = JSONDecoder()

    func testDecodesCoreRuntimeSnapshots() throws {
        let config: HAConfig = try decode("get_config")
        XCTAssertFalse(config.locationName.isEmpty)
        XCTAssertEqual(config.timeZone, "Asia/Shanghai")
        XCTAssertTrue(config.components.contains("lovelace"))

        let states: [HassEntity] = try decode("get_states")
        XCTAssertGreaterThan(states.count, 200)
        XCTAssertEqual(states.first?.entityID, "conversation.home_assistant")
        XCTAssertNotNil(states.first?.lastReported)

        let services: HAServices = try decode("get_services")
        XCTAssertNotNil(services["homeassistant"]?["turn_on"])
        XCTAssertNotNil(services["frontend"]?["set_theme"])

        let panels: HAPanels = try decode("get_panels")
        XCTAssertEqual(panels["lovelace"]?.componentName, "lovelace")
        XCTAssertEqual(panels["dashboard-ultrasonic"]?.title, "Ultrasonic")
    }

    func testDecodesRegistryAndFrontendSnapshots() throws {
        let displayResponse: HAEntityRegistryDisplayResponse = try decode("entity_registry_display")
        XCTAssertGreaterThan(displayResponse.entities.count, 200)
        XCTAssertEqual(displayResponse.entityCategories["0"], .config)
        XCTAssertEqual(displayResponse.entityCategories["1"], .diagnostic)
        XCTAssertNotNil(displayResponse.expandedEntities["sensor.sun_next_dawn"])

        let entityRegistry: [HAEntityRegistryEntry] = try decode("entity_registry")
        XCTAssertGreaterThan(entityRegistry.count, 400)
        XCTAssertEqual(entityRegistry.first?.entityID, "binary_sensor.sun_solar_rising")

        let devices: [HADeviceRegistryEntry] = try decode("device_registry")
        XCTAssertGreaterThan(devices.count, 50)
        XCTAssertEqual(devices.first?.name, "Sun")

        let areas: [HAAreaRegistryEntry] = try decode("area_registry")
        XCTAssertEqual(areas.count, 4)
        XCTAssertNotNil(areas.first { $0.areaID == "wo_shi" })

        let floors: [HAFloorRegistryEntry] = try decode("floor_registry")
        XCTAssertEqual(floors.count, 0)

        let userData: HAFrontendDataResponse = try decode("frontend_user_core")
        XCTAssertEqual(userData.value?["showAdvanced"], .bool(false))

        let systemData: HAFrontendDataResponse = try decode("frontend_system_core")
        XCTAssertEqual(systemData.value?["default_panel"], .string("lovelace"))
    }

    @MainActor
    func testStoresApplySnapshotModels() throws {
        let states: [HassEntity] = try decode("get_states")
        let services: HAServices = try decode("get_services")
        let panels: HAPanels = try decode("get_panels")
        let displayResponse: HAEntityRegistryDisplayResponse = try decode("entity_registry_display")
        let devices: [HADeviceRegistryEntry] = try decode("device_registry")
        let areas: [HAAreaRegistryEntry] = try decode("area_registry")
        let floors: [HAFloorRegistryEntry] = try decode("floor_registry")

        let stateStore = HAStateStore()
        stateStore.apply(states: states, services: services, panels: panels)

        XCTAssertEqual(stateStore.states.count, states.count)
        XCTAssertEqual(stateStore.services.count, services.count)
        XCTAssertEqual(stateStore.panels.count, panels.count)

        let registryStore = HARegistryStore()
        registryStore.apply(displayResponse: displayResponse, devices: devices, areas: areas, floors: floors)

        XCTAssertEqual(registryStore.entities.count, displayResponse.entities.count)
        XCTAssertEqual(registryStore.devices.count, devices.count)
        XCTAssertEqual(registryStore.areas.count, areas.count)
        XCTAssertEqual(registryStore.floors.count, floors.count)
    }

    private func decode<T: Decodable>(_ name: String) throws -> T {
        let url = URL(fileURLWithPath: "\(snapshotDirectory)/\(name).json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }
}
