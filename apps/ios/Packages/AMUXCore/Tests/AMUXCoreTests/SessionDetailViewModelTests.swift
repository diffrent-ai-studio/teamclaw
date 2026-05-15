import XCTest
import SwiftData
@testable import AMUXCore

@MainActor
final class SessionDetailViewModelTests: XCTestCase {
    func testSessionPromptUsesSessionLiveTransportEvenWithPlaceholderRuntime() async throws {
        var published: [(String, Data, Bool)] = []
        let mqtt = MQTTService(
            subscribeHook: { _ in },
            unsubscribeHook: { _ in },
            publishHook: { topic, payload, retain in
                published.append((topic, payload, retain))
            }
        )
        let teamclawService = TeamclawService()
        let container = try ModelContainer(
            for: Session.self, Runtime.self, AgentEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        teamclawService.configureRuntimeForTesting(
            mqtt: mqtt,
            teamId: "team-1",
            peerId: "peer-1",
            modelContainer: container
        )
        teamclawService.setLocalMemberIdForTesting("human-1")

        let session = Session(sessionId: "session-1", teamId: "team-1")
        session.primaryAgentId = "agent-actor-1"
        let placeholder = Runtime(runtimeId: "agent-actor-1")
        placeholder.daemonDeviceId = "daemon-device-1"

        let viewModel = SessionDetailViewModel(
            runtime: placeholder,
            mqtt: mqtt,
            hub: MQTTMessageHub(mqtt: mqtt),
            teamID: "team-1",
            peerId: "peer-1",
            session: session,
            teamclawService: teamclawService
        )

        try await viewModel.sendPrompt("second turn")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(
            published.first?.0,
            MQTTTopics.sessionLive(teamID: "team-1", sessionID: "session-1")
        )
        XCTAssertFalse(published.first?.2 ?? true)
    }
}
