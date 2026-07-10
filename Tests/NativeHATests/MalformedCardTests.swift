import XCTest
@testable import NativeHA
@testable import NativeHACore

final class MalformedCardTests: XCTestCase {
    func testMalformedHistoryGraphCard() throws {
        let json = """
        {
          "type": "history-graph",
          "entities": "not_an_array"
        }
        """
        let decoder = JSONDecoder()
        let config = try decoder.decode(LovelaceCardConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.type, "history-graph")
    }
}
