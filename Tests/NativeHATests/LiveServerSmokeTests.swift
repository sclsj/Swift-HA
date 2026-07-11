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
        let entities = await MainActor.run { connection.registryStore.entities }
        let devices = await MainActor.run { connection.registryStore.devices }
        let entityRegistry = await MainActor.run { connection.registryStore.entityRegistry }
        let config = await MainActor.run { connection.stateStore.config }
        let panels = await MainActor.run { connection.stateStore.panels }
        let currentUser = await MainActor.run { connection.stateStore.currentUser }
        let storeSummary = await MainActor.run { connection.storeSummary }
        
        print("=== LIVE SERVER DATA ===")
        print("Loaded \(states.count) states")
        print("Loaded \(entities.count) registered entities")
        print("Loaded \(devices.count) devices")
        print("========================")
        
        XCTAssertGreaterThan(states.count, 0, "Should have loaded some states from live server")
        XCTAssertGreaterThan(entities.count, 0, "Should have loaded some registered entities")

        guard let client = connection.client else {
            XCTFail("Expected live connection to expose a WebSocket client.")
            return
        }

        let lovelaceStart = Date()
        let lovelaceProvider = HALovelaceConfigProvider(connection: connection)
        let dashboards = try await lovelaceProvider.dashboardList()
        XCTAssertFalse(dashboards.isEmpty)
        let dashboardPath = dashboards.first { $0.path == "/lovelace" }?.path
            ?? dashboards.first?.path
            ?? "/lovelace"
        let lovelaceConfiguration = try await lovelaceProvider.configuration(for: dashboardPath)
        let lovelaceElapsedMilliseconds = Date().timeIntervalSince(lovelaceStart) * 1_000
        switch lovelaceConfiguration.config {
        case let .config(config):
            let route = LovelaceRouter().route(
                dashboardPath: dashboardPath,
                config: config,
                userID: currentUser?.id
            )
            XCTAssertNotNil(route.selectedViewIndex)
            print(String(format: "Built Lovelace dashboard %@ with %d views in %.2f ms", dashboardPath, config.views.count, lovelaceElapsedMilliseconds))
        case let .strategy(strategy):
            print(String(format: "Loaded Lovelace strategy %@ for %@ in %.2f ms", strategy.strategy.type, dashboardPath, lovelaceElapsedMilliseconds))
        case .none:
            XCTFail("Expected live Lovelace configuration for \(dashboardPath).")
        }

        let settingsStart = Date()
        let settingsModel = SettingsDashboardModel(context: SettingsDashboardContext(
            serverURL: try? provider.credentials().serverURL,
            connectionState: .connected,
            stores: storeSummary,
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

        if let historyEntity = firstSafeHistoryEntity(
            states: states,
            entityRegistry: entityRegistry,
            devices: devices
        ) {
            let historyConfig = try historyGraphConfig(entityID: historyEntity.entityID)
            let displayContext = EntityDisplayContext(
                states: states,
                config: config,
                registryEntries: entities
            )
            let historyModel = HistoryGraphCardModel(config: historyConfig, displayContext: displayContext)
            let historyEnd = Date()
            let historyWindow = historyModel.fetchWindow(endingAt: historyEnd)
            let historyStart = Date()
            let history = try await HistoryAPI(client: client).fetchHistoryDuringPeriod(
                startTime: historyWindow.start,
                endTime: historyWindow.end,
                entityIDs: historyModel.entityIDs,
                currentStates: states,
                minimalResponse: true
            )
            let processedHistory = HistoryProcessor.computeHistory(
                stateHistory: history,
                entityIDs: historyModel.entityIDs,
                context: HistoryProcessingContext(
                    states: states,
                    config: config,
                    registryEntries: entities
                ),
                splitDeviceClasses: historyModel.splitDeviceClasses
            )
            let historyElapsedMilliseconds = Date().timeIntervalSince(historyStart) * 1_000
            let historyStateCount = history.values.reduce(0) { $0 + $1.count }
            print(String(format: "Built history graph model for %@ with %d raw states, %d line groups, %d timeline rows in %.2f ms", historyEntity.entityID, historyStateCount, processedHistory.line.count, processedHistory.timeline.count, historyElapsedMilliseconds))
        } else {
            print("No safe non-Midea entity available for live history graph smoke.")
        }

        let statisticsAPI = StatisticsAPI(client: client)
        let metadataStart = Date()
        let metadata = try await statisticsAPI.fetchStatisticMetadata()
        let safeStatisticIDs = Array(metadata
            .map(\.statisticID)
            .filter {
                isSafeStatisticID(
                    $0,
                    states: states,
                    entityRegistry: entityRegistry,
                    devices: devices
                )
            }
            .prefix(12))
        let metadataElapsedMilliseconds = Date().timeIntervalSince(metadataStart) * 1_000
        if !safeStatisticIDs.isEmpty {
            let probeEnd = Date()
            let probeStart = probeEnd.addingTimeInterval(-7 * 24 * 60 * 60)
            let probeStatistics = try await statisticsAPI.fetchStatisticsDuringPeriod(
                startTime: probeStart,
                endTime: probeEnd,
                statisticIDs: safeStatisticIDs,
                period: .hour,
                types: [.mean, .state, .sum, .change]
            )
            let statisticIDs = Array(safeStatisticIDs.filter {
                probeStatistics[$0]?.isEmpty == false
            }.prefix(3))
            if statisticIDs.isEmpty {
                print(String(format: "No recent safe non-Midea statistic samples found among %d candidates (metadata %.2f ms).", safeStatisticIDs.count, metadataElapsedMilliseconds))
            } else {
                let statisticsConfig = try statisticsGraphConfig(entityIDs: statisticIDs)
                let statisticsModel = StatisticsGraphCardModel(
                    config: statisticsConfig,
                    displayContext: EntityDisplayContext(
                        states: states,
                        config: config,
                        registryEntries: entities
                    )
                )
                let statisticsEnd = Date()
                let statisticsWindow = statisticsModel.fetchWindow(endingAt: statisticsEnd)
                let statisticsStart = Date()
                let statistics = try await statisticsAPI.fetchStatisticsDuringPeriod(
                    startTime: statisticsWindow.start,
                    endTime: statisticsWindow.end,
                    statisticIDs: statisticsModel.entityIDs,
                    period: statisticsModel.period,
                    types: statisticsModel.statTypes
                )
                let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.statisticID, $0) })
                let statisticsSeries = StatisticsSeriesBuilder.buildSeries(
                    statistics: statistics,
                    metadata: metadataByID,
                    statisticIDs: statisticsModel.entityIDs,
                    statTypes: statisticsModel.statTypes,
                    currentStates: states,
                    endTime: statisticsWindow.end.timeIntervalSince1970 * 1_000,
                    now: statisticsEnd.timeIntervalSince1970 * 1_000
                )
                let statisticsElapsedMilliseconds = Date().timeIntervalSince(statisticsStart) * 1_000
                let statisticSampleCount = statistics.values.reduce(0) { $0 + $1.count }
                XCTAssertFalse(statisticsSeries.series.isEmpty || statisticSampleCount == 0)
                print(String(format: "Built statistics graph model for %d statistic IDs with %d samples and %d series in %.2f ms (metadata %.2f ms)", statisticIDs.count, statisticSampleCount, statisticsSeries.series.count, statisticsElapsedMilliseconds, metadataElapsedMilliseconds))
            }
        } else {
            print(String(format: "No safe non-Midea statistic IDs available for live statistics smoke (metadata %.2f ms).", metadataElapsedMilliseconds))
        }

        let climateStates = states.values.filter {
            EntityIDParser.domain(from: $0.entityID) == "climate"
                && ($0.entityID == "climate.room_ac"
                    || isSafeEntity($0.entityID, states: states, entityRegistry: entityRegistry, devices: devices))
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

    private func firstSafeHistoryEntity(
        states: [EntityID: HassEntity],
        entityRegistry: [EntityID: HAEntityRegistryEntry],
        devices: [String: HADeviceRegistryEntry]
    ) -> HassEntity? {
        states.values
            .sorted { $0.entityID < $1.entityID }
            .first { entity in
                EntityIDParser.domain(from: entity.entityID) == "sensor"
                    && Double(entity.state) != nil
                    && !HAStateValue.isUnknownOrUnavailable(entity.state)
                    && isSafeEntity(entity.entityID, states: states, entityRegistry: entityRegistry, devices: devices)
            }
    }

    private func isSafeStatisticID(
        _ statisticID: String,
        states: [EntityID: HassEntity],
        entityRegistry: [EntityID: HAEntityRegistryEntry],
        devices: [String: HADeviceRegistryEntry]
    ) -> Bool {
        EntityIDParser.isValid(statisticID)
            && isSafeEntity(statisticID, states: states, entityRegistry: entityRegistry, devices: devices)
    }

    private func isSafeEntity(
        _ entityID: EntityID,
        states: [EntityID: HassEntity],
        entityRegistry: [EntityID: HAEntityRegistryEntry],
        devices: [String: HADeviceRegistryEntry]
    ) -> Bool {
        let registryEntry = entityRegistry[entityID]
        let device = registryEntry?.deviceID.flatMap { devices[$0] }
        let values = [
            entityID,
            states[entityID]?.friendlyName,
            registryEntry?.name,
            registryEntry?.originalName,
            registryEntry?.platform,
            device?.manufacturer,
            device?.model,
            device?.modelID,
            device?.name,
            device?.nameByUser
        ]
        let nestedValues = (device?.identifiers ?? []).flatMap { $0 }
            + (device?.connections ?? []).flatMap { $0 }
        return (values.compactMap { $0 } + nestedValues).allSatisfy {
            !$0.localizedCaseInsensitiveContains("midea")
        }
    }

    private func historyGraphConfig(entityID: EntityID) throws -> HistoryGraphCardConfig {
        guard case let .historyGraph(config) = try JSONDecoder().decode(
            LovelaceCardConfig.self,
            from: Data("""
            {
              "type": "history-graph",
              "hours_to_show": 1,
              "entities": ["\(entityID)"]
            }
            """.utf8)
        ) else {
            throw LiveSmokeError.unexpectedCardType
        }
        return config
    }

    private func statisticsGraphConfig(entityIDs: [EntityID]) throws -> StatisticsGraphCardConfig {
        let entitiesJSON = entityIDs.map { "\"\($0)\"" }.joined(separator: ",")
        guard case let .statisticsGraph(config) = try JSONDecoder().decode(
            LovelaceCardConfig.self,
            from: Data("""
            {
              "type": "statistics-graph",
              "days_to_show": 1,
              "period": "hour",
              "stat_types": ["mean", "state", "sum", "change"],
              "entities": [\(entitiesJSON)]
            }
            """.utf8)
        ) else {
            throw LiveSmokeError.unexpectedCardType
        }
        return config
    }
}

private enum LiveSmokeError: Error {
    case unexpectedCardType
}
