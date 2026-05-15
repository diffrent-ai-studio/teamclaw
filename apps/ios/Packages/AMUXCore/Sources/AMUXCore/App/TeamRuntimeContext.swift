import Foundation

/// Team-scoped runtime state — the bundle of repositories and observable
/// stores tied to the currently active team.
///
/// Built once per active-team transition by `AppOnboardingCoordinator`,
/// replaced atomically when the active team changes, nilled on sign-out.
/// Pass this into `RootTabView` instead of having the view construct
/// repositories itself; that keeps composition out of view bodies and
/// makes team switching a single observable change.
///
/// Repository slots are optional because their initializers can throw
/// (missing Supabase configuration). Callers that absolutely need a
/// repository should still guard for nil — Phase 1 preserves the
/// existing graceful-degradation behavior.
@MainActor
public struct TeamRuntimeContext {
    public let team: TeamSummary
    public let memberActorID: String

    public let actorStore: ActorStore
    public let connectedAgentsStore: ConnectedAgentsStore

    public let sessionIDsRepo: SupabaseSessionIDsRepository?
    public let sessionsRepo: SupabaseSessionsRepository?
    public let agentRuntimesRepo: SupabaseAgentRuntimesRepository?
    public let workspacesRepo: SupabaseWorkspaceRepository?
    public let agentAccessRepo: SupabaseAgentAccessRepository?

    public init(
        team: TeamSummary,
        memberActorID: String,
        actorStore: ActorStore,
        connectedAgentsStore: ConnectedAgentsStore,
        sessionIDsRepo: SupabaseSessionIDsRepository?,
        sessionsRepo: SupabaseSessionsRepository?,
        agentRuntimesRepo: SupabaseAgentRuntimesRepository?,
        workspacesRepo: SupabaseWorkspaceRepository?,
        agentAccessRepo: SupabaseAgentAccessRepository?
    ) {
        self.team = team
        self.memberActorID = memberActorID
        self.actorStore = actorStore
        self.connectedAgentsStore = connectedAgentsStore
        self.sessionIDsRepo = sessionIDsRepo
        self.sessionsRepo = sessionsRepo
        self.agentRuntimesRepo = agentRuntimesRepo
        self.workspacesRepo = workspacesRepo
        self.agentAccessRepo = agentAccessRepo
    }
}
