import Foundation
import Supabase

/// Snapshot of one row in the Supabase `agent_runtimes` table. Cached locally
/// as `CachedAgentRuntime` so the session list can display backend type +
/// workspace even when the daemon's MQTT runtime topic is offline.
public struct AgentRuntimeRecord: Equatable, Sendable {
    public let id: String
    public let teamID: String
    public let agentID: String
    public let sessionID: String?
    public let workspaceID: String?
    public let backendType: String
    public let status: String
    public let backendSessionID: String?
    /// Daemon-side 8-char runtime id (the segment in the MQTT topic
    /// `runtime/{runtime_id}/state`). The bridge to the live SwiftData
    /// `Runtime` row — distinct from `backendSessionID`, which is the
    /// 36-char ACP session id used by the daemon to resume Claude Code.
    public let runtimeID: String?
    public let currentModel: String?
    public let lastSeenAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
}

public protocol AgentRuntimesRepository: Sendable {
    func listForTeam(teamID: String) async throws -> [AgentRuntimeRecord]
}

public actor SupabaseAgentRuntimesRepository: AgentRuntimesRepository {
    private let client: SupabaseClient

    public init(configuration: SupabaseProjectConfiguration) {
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    public init() throws {
        let configuration = try SupabaseProjectConfiguration.fromMainBundle()
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
    }

    public func listForTeam(teamID: String) async throws -> [AgentRuntimeRecord] {
        let rows: [AgentRuntimeRow] = try await client
            .from("agent_runtimes")
            .select(
                """
                id,
                team_id,
                agent_id,
                session_id,
                workspace_id,
                backend_type,
                status,
                backend_session_id,
                runtime_id,
                current_model,
                last_seen_at,
                created_at,
                updated_at
                """
            )
            .eq("team_id", value: teamID)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return rows.map { row in
            AgentRuntimeRecord(
                id: row.id,
                teamID: row.teamID,
                agentID: row.agentID,
                sessionID: row.sessionID,
                workspaceID: row.workspaceID,
                backendType: row.backendType,
                status: row.status,
                backendSessionID: row.backendSessionID,
                runtimeID: row.runtimeID,
                currentModel: row.currentModel,
                lastSeenAt: row.lastSeenAt,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
    }
}

private struct AgentRuntimeRow: Decodable, Sendable {
    let id: String
    let teamID: String
    let agentID: String
    let sessionID: String?
    let workspaceID: String?
    let backendType: String
    let status: String
    let backendSessionID: String?
    let runtimeID: String?
    let currentModel: String?
    let lastSeenAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case agentID = "agent_id"
        case sessionID = "session_id"
        case workspaceID = "workspace_id"
        case backendType = "backend_type"
        case status
        case backendSessionID = "backend_session_id"
        case runtimeID = "runtime_id"
        case currentModel = "current_model"
        case lastSeenAt = "last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
