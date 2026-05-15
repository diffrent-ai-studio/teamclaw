import Foundation
import Supabase

public actor SupabaseWorkspaceRepository: WorkspaceRepository {
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

    public func listWorkspaces(teamID: String, agentID: String?) async throws -> [WorkspaceRecord] {
        var query = client
            .from("workspaces")
            .select(
                """
                id,
                team_id,
                agent_id,
                path,
                name
                """
            )
            .eq("team_id", value: teamID)

        if let agentID, !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query = query.eq("agent_id", value: agentID)
        }

        let rows: [WorkspaceRow] = try await query
            .order("name", ascending: true)
            .execute()
            .value

        return rows.map(\.record)
    }
}

private struct WorkspaceRow: Decodable, Sendable {
    let id: String
    let teamID: String
    let agentID: String?
    let path: String?
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case agentID = "agent_id"
        case path
        case name
    }

    var record: WorkspaceRecord {
        WorkspaceRecord(
            id: id,
            teamID: teamID,
            agentID: agentID,
            path: path ?? "",
            displayName: name
        )
    }
}
