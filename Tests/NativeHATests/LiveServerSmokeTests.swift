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
        let entities = await connection.registryStore.entities
        let devices = await connection.registryStore.devices
        
        print("=== LIVE SERVER DATA ===")
        print("Loaded \(states.count) states")
        print("Loaded \(entities.count) registered entities")
        print("Loaded \(devices.count) devices")
        print("========================")
        
        XCTAssertGreaterThan(states.count, 0, "Should have loaded some states from live server")
        XCTAssertGreaterThan(entities.count, 0, "Should have loaded some registered entities")
        
        // Wait 3 seconds to let some events flow in
        print("Waiting for events...")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        let updatedStates = await MainActor.run { connection.stateStore.states }
        print("States count after 3 seconds: \(updatedStates.count)")
        
        // Disconnect cleanly
        print("Disconnecting...")
        await connection.client?.disconnect()
    }
}
