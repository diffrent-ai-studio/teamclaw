import XCTest
@testable import AMUXCore

final class MQTTTopicsTests: XCTestCase {
    func testTeamclawRearchitectureTopics() {
        XCTAssertEqual(
            MQTTTopics.deviceRpcRequest(teamID: "team1", deviceID: "dev-a"),
            "amux/team1/device/dev-a/rpc/req"
        )
        XCTAssertEqual(
            MQTTTopics.deviceRpcResponse(teamID: "team1", deviceID: "dev-a"),
            "amux/team1/device/dev-a/rpc/res"
        )
        XCTAssertEqual(
            MQTTTopics.deviceNotify(teamID: "team1", deviceID: "dev-a"),
            "amux/team1/device/dev-a/notify"
        )
        XCTAssertEqual(
            MQTTTopics.sessionLive(teamID: "team1", sessionID: "sess-1"),
            "amux/team1/session/sess-1/live"
        )
    }
}
