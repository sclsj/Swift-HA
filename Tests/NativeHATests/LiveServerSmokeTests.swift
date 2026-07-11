import XCTest
@testable import NativeHACore
@testable import NativeHA

final class LiveServerSmokeTests: XCTestCase {
    
    func testLiveServerSmokeConnectionAndDataLoad() async throws {
        // Look for the real credentials
        let serverPath = "/Users/jin/Documents/HA/ha_server.txt"
        let tokenPath = "/Users/jin/Documents/HA/ha_apikey.txt"
        
        guard FileManager.default.fileExists(atPath: serverPath) && FileManager.default.fileExists(atPath: tokenPath) else {
            throw XCTSkip("Skipping live server test because credentials files are missing.")
        }
        
        let provider = FileCredentialProvider(serverFilePath: serverPath, tokenFilePath: tokenPath)
        
        let connection = HAConnection(credentialProvider: provider)
        
        // Connect and wait for the initial sync
        print("Connecting to actual server...")
        try await connection.connect()
        
        // Retrieve stores
        let states = await MainActor.run { connection.stateStore.states }
        let entities = connection.registryStore.entities
        let devices = connection.registryStore.devices
        let entityRegistry = connection.registryStore.entityRegistry
        let config = await MainActor.run { connection.stateStore.config }
        let panels = await MainActor.run { connection.stateStore.panels }
        let currentUser = await MainActor.run { connection.stateStore.currentUser }
        
        print("=== LIVE SERVER DATA ===")
        print("Loaded \(states.count) states")
        print("Loaded \(entities.count) registered entities")
        print("Loaded \(devices.count) devices")
        print("========================")
        
        XCTAssertGreaterThan(states.count, 0, "Should have loaded some states from live server")
        XCTAssertGreaterThan(entities.count, 0, "Should have loaded some registered entities")

        let settingsStart = Date()
        let settingsModel = SettingsDashboardModel(context: SettingsDashboardContext(
            serverURL: try? provider.credentials().serverURL,
            connectionState: .connected,
            stores: connection.storeSummary,
            config: config,
            currentUser: currentUser,
            states: states,
            panels: panels,
            registryEntries: entities,
            entityRegistryEntries: entityRegistry,
            devices: devices
        ))
        let settingsElapsedMilliseconds = Date().timeIntervalSince(settingsStart) * 1_000
        XCTAssertFalse(settingsModel.summary.title.isEmpty)
        if currentUser?.isAdmin == true {
            XCTAssertFalse(settingsModel.sections.isEmpty)
        }
        print(String(format: "Built settings dashboard model with %d sections in %.2f ms", settingsModel.sections.count, settingsElapsedMilliseconds))

        let climateStates = states.values.filter {
            EntityIDParser.domain(from: $0.entityID) == "climate"
        }
        print("Climate entities available: \(climateStates.count)")
        if let climateState = climateStates.first {
            let start = Date()
            let model = MoreInfoModel.build(
                entityID: climateState.entityID,
                states: states,
                registryEntries: entities,
                config: await MainActor.run { connection.stateStore.config }
            )
            let elapsedMilliseconds = Date().timeIntervalSince(start) * 1_000
            XCTAssertEqual(model.domain, "climate")
            XCTAssertNotNil(model.climate)
            print(String(format: "Built climate more-info model in %.2f ms", elapsedMilliseconds))
        }
        
        // Wait 3 seconds to let some events flow in
        print("Waiting for events...")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        let updatedStates = await MainActor.run { connection.stateStore.states }
        print("States count after 3 seconds: \(updatedStates.count)")
        
        // Disconnect cleanly
        print("Disconnecting...")
        await connection.client?.disconnect()
    }

    func testLiveWriteRoomAC() async throws {
        let serverPath = "/Users/jin/Documents/HA/ha_server.txt"
        let tokenPath = "/Users/jin/Documents/HA/ha_apikey.txt"
        
        guard FileManager.default.fileExists(atPath: serverPath) && FileManager.default.fileExists(atPath: tokenPath) else {
            throw XCTSkip("Skipping live server test because credentials files are missing.")
        }
        
        let provider = FileCredentialProvider(serverFilePath: serverPath, tokenFilePath: tokenPath)
        let connection = HAConnection(credentialProvider: provider)
        
        print("Connecting to actual server for write test...")
        try await connection.connect()
        
        let states = await MainActor.run { connection.stateStore.states }
        guard let roomAC = states["climate.room_ac"] else {
            print("climate.room_ac not found, skipping write test")
            await connection.client?.disconnect()
            throw XCTSkip("climate.room_ac not found")
        }
        
        let hvacMode = roomAC.state
        let temperature = roomAC.attributes["temperature"]?.haNumberValue
        let targetTempHigh = roomAC.attributes["target_temp_high"]?.haNumberValue
        let targetTempLow = roomAC.attributes["target_temp_low"]?.haNumberValue
        let presetMode = roomAC.attributes["preset_mode"]?.haScalarStringValue
        let fanMode = roomAC.attributes["fan_mode"]?.haScalarStringValue
        let swingMode = roomAC.attributes["swing_mode"]?.haScalarStringValue
        
        print("--- Original State ---")
        print("hvacMode: \(hvacMode)")
        print("temperature: \(String(describing: temperature))")
        print("targetTempHigh: \(String(describing: targetTempHigh))")
        print("targetTempLow: \(String(describing: targetTempLow))")
        print("presetMode: \(String(describing: presetMode))")
        print("fanMode: \(String(describing: fanMode))")
        print("swingMode: \(String(describing: swingMode))")
        print("----------------------")
        
        guard hvacMode != "unavailable" && hvacMode != "unknown" else {
            print("climate.room_ac is unavailable, skipping write test")
            await connection.client?.disconnect()
            throw XCTSkip("climate.room_ac is unavailable")
        }

        let model = ClimateControlModel(stateObj: roomAC)!
        
        // Write test
        var callSucceeded = false
        if let _ = temperature, let nextTemp = model.nextTemperature(delta: model.targetTemperatureStep) {
            print("Writing next temp: \(nextTemp)")
            if let call = model.setTemperatureCall(nextTemp) {
                let result = try? await connection.serviceClient?.callService(
                    domain: call.domain,
                    service: call.service,
                    serviceData: call.serviceData
                )
                if result != nil {
                    callSucceeded = true
                    print("set_temperature succeeded")
                } else {
                    print("set_temperature failed: \(String(describing: result))")
                }
            }
        }
        
        // Restore
        print("Restoring...")
        if let temp = temperature, callSucceeded {
            let result = try? await connection.serviceClient?.callService(
                domain: "climate",
                service: "set_temperature",
                serviceData: ["entity_id": .string("climate.room_ac"), "temperature": .double(temp)]
            )
            print("restore set_temperature result: \(String(describing: result))")
        }

        // Wait a bit
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let finalStates = await MainActor.run { connection.stateStore.states }
        let finalAC = finalStates["climate.room_ac"]
        print("Final temperature: \(String(describing: finalAC?.attributes["temperature"]?.haNumberValue))")
        
        await connection.client?.disconnect()
    }
}
