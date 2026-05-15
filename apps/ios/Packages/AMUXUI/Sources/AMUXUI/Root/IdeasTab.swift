import SwiftUI
import SwiftData
import AMUXCore

public struct IdeasTab: View {
    let pairing: PairingManager
    let teamclawService: TeamclawService?
    let activeTeam: TeamSummary?
    let mqtt: MQTTService
    let hub: MQTTMessageHub
    let sessionViewModel: SessionListViewModel
    let connectedAgentsStore: ConnectedAgentsStore?

    @Environment(\.modelContext) private var modelContext

    @State private var showCreate = false
    @State private var navigationPath: [String] = []
    @State private var ideaStore: IdeaStore?
    @State private var ideaStoreTeamID: String?
    @State private var ideaSetupError: String?

    public init(
        mqtt: MQTTService,
        hub: MQTTMessageHub,
        pairing: PairingManager,
        teamclawService: TeamclawService?,
        activeTeam: TeamSummary?,
        sessionViewModel: SessionListViewModel,
        connectedAgentsStore: ConnectedAgentsStore? = nil
    ) {
        self.mqtt = mqtt
        self.hub = hub
        self.pairing = pairing
        self.teamclawService = teamclawService
        self.activeTeam = activeTeam
        self.sessionViewModel = sessionViewModel
        self.connectedAgentsStore = connectedAgentsStore
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle(IdeaUIPresentation.pluralTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if ideaStore != nil {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showCreate = true } label: {
                                Image(systemName: "plus").font(.title3).foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    if id.hasPrefix("idea:") {
                        let ideaID = String(id.dropFirst("idea:".count))
                        if let ideaStore {
                            IdeaDetailView(
                                ideaID: ideaID,
                                ideaStore: ideaStore,
                                sessionViewModel: sessionViewModel,
                                teamclawService: teamclawService,
                                mqtt: mqtt,
                                hub: hub,
                                peerId: "ios-\(pairing.authToken.prefix(6))",
                                navigationPath: $navigationPath
                            )
                        } else {
                            Text("Idea store unavailable")
                        }
                    } else if id.hasPrefix("session:") {
                        let sessionId = String(id.dropFirst("session:".count))
                        let descriptor = FetchDescriptor<Session>(
                            predicate: #Predicate { $0.sessionId == sessionId }
                        )
                        if let session = (try? modelContext.fetch(descriptor))?.first {
                            SessionDetailView(
                                session: session,
                                mqtt: mqtt,
                                hub: hub,
                                peerId: "ios-\(pairing.authToken.prefix(6))",
                                teamclawService: teamclawService,
                                connectedAgentsStore: connectedAgentsStore
                            )
                        } else {
                            Text("Session not found")
                        }
                    } else {
                        Text("Unknown destination")
                    }
                }
        }
        .task(id: activeTeam?.id) {
            await configureIdeaStore()
        }
        // Mirror SessionsTab: drive tab-bar visibility from the stack
        // root so the bar animates back in alongside the pop transition
        // instead of waiting for the destination view to fully unmount.
        .toolbarVisibility(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    @ViewBuilder
    private var content: some View {
        if activeTeam == nil {
            ContentUnavailableView(
                "No Team Selected",
                systemImage: "person.3",
                description: Text("Create or join a team to manage ideas.")
            )
        } else if let ideaSetupError {
            ContentUnavailableView(
                "Couldn’t Set Up Ideas",
                systemImage: "exclamationmark.triangle",
                description: Text(ideaSetupError)
            )
        } else if let ideaStore {
            IdeaListView(ideaStore: ideaStore, showCreate: $showCreate)
        } else {
            ProgressView("Loading ideas…")
        }
    }

    @MainActor
    private func configureIdeaStore() async {
        guard let activeTeam else {
            ideaStore = nil
            ideaStoreTeamID = nil
            ideaSetupError = nil
            return
        }

        if ideaStore == nil || ideaStoreTeamID != activeTeam.id {
            do {
                let repository = try SupabaseIdeaRepository()
                ideaStore = IdeaStore(
                    teamID: activeTeam.id,
                    repository: repository,
                    modelContext: modelContext
                )
                ideaStoreTeamID = activeTeam.id
                ideaSetupError = nil
            } catch {
                ideaStore = nil
                ideaStoreTeamID = nil
                ideaSetupError = error.localizedDescription
                return
            }
        }

        await ideaStore?.reload()
    }
}
