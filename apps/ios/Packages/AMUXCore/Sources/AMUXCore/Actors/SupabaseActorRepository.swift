import Foundation
import Supabase

public enum ActorRepositoryError: LocalizedError {
    case missingDisplayName
    case missingAgentKind
    case missingTeamRole
    case emptyResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingDisplayName: return "Display name is required."
        case .missingAgentKind:   return "Agent kind is required."
        case .missingTeamRole:    return "Team role is required."
        case .emptyResponse(let fn): return "\(fn) returned no rows."
        }
    }
}

public actor SupabaseActorRepository: ActorRepository {
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

    public func listActors(teamID: String) async throws -> [ActorRecord] {
        let rows: [ActorDirectoryRow] = try await client
            .from("actor_directory")
            .select("""
                id, team_id, actor_type, user_id, invited_by_actor_id,
                display_name, last_active_at, created_at, updated_at,
                member_status, team_role, agent_kind, agent_status
            """)
            .eq("team_id", value: teamID)
            .order("display_name", ascending: true)
            .execute()
            .value
        return rows.map(\.record)
    }

    public func createInvite(teamID: String, input: InviteCreateInput) async throws -> InviteCreated {
        let displayName = input.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw ActorRepositoryError.missingDisplayName }
        if input.kind == .member, input.teamRole == nil {
            throw ActorRepositoryError.missingTeamRole
        }
        if input.kind == .agent,
           (input.agentKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ActorRepositoryError.missingAgentKind
        }

        let rows: [InviteCreatedRow] = try await client
            .rpc("create_team_invite", params: CreateInviteParams(
                teamID: teamID, kind: input.kind.rawValue,
                displayName: displayName,
                teamRole: input.teamRole?.rawValue,
                agentKind: input.agentKind,
                ttlSeconds: input.ttlSeconds,
                targetActorID: input.targetActorID))
            .execute()
            .value

        guard let row = rows.first else {
            throw ActorRepositoryError.emptyResponse("create_team_invite")
        }
        return row.asInviteCreated
    }

    public func claimInvite(token: String) async throws -> ClaimResult {
        let rows: [ClaimResultRow] = try await client
            .rpc("claim_team_invite", params: ClaimInviteParams(token: token))
            .execute()
            .value
        guard let row = rows.first else {
            throw ActorRepositoryError.emptyResponse("claim_team_invite")
        }
        return row.asClaimResult
    }

    public func heartbeat() async throws {
        _ = try await client.rpc("update_actor_last_active").execute()
    }

    public func removeActor(actorID: String) async throws {
        _ = try await client
            .rpc("remove_team_actor", params: RemoveActorParams(actorID: actorID))
            .execute()
    }
}

private struct RemoveActorParams: Encodable {
    let actorID: String
    enum CodingKeys: String, CodingKey { case actorID = "p_actor_id" }
}

// MARK: - Wire types

private struct CreateInviteParams: Encodable {
    let teamID: String; let kind: String; let displayName: String
    let teamRole: String?; let agentKind: String?; let ttlSeconds: Int
    let targetActorID: String?
    enum CodingKeys: String, CodingKey {
        case teamID = "p_team_id", kind = "p_kind", displayName = "p_display_name"
        case teamRole = "p_team_role", agentKind = "p_agent_kind", ttlSeconds = "p_ttl_seconds"
        case targetActorID = "p_target_actor_id"
    }
}

private struct ClaimInviteParams: Encodable {
    let token: String
    enum CodingKeys: String, CodingKey { case token = "p_token" }
}

private struct ActorDirectoryRow: Decodable, Sendable {
    let id: String; let teamID: String; let actorType: String
    let userID: String?; let invitedByActorID: String?
    let displayName: String; let lastActiveAt: Date?
    let createdAt: Date; let updatedAt: Date
    let memberStatus: String?; let teamRole: String?
    let agentKind: String?;   let agentStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id", actorType = "actor_type", userID = "user_id"
        case invitedByActorID = "invited_by_actor_id"
        case displayName = "display_name", lastActiveAt = "last_active_at"
        case createdAt = "created_at", updatedAt = "updated_at"
        case memberStatus = "member_status", teamRole = "team_role"
        case agentKind = "agent_kind", agentStatus = "agent_status"
    }
    var record: ActorRecord {
        ActorRecord(
            id: id, teamID: teamID, actorType: actorType,
            userID: userID, invitedByActorID: invitedByActorID,
            displayName: displayName, lastActiveAt: lastActiveAt,
            createdAt: createdAt, updatedAt: updatedAt,
            memberStatus: memberStatus, teamRole: teamRole,
            agentKind: agentKind, agentStatus: agentStatus
        )
    }
}

private struct InviteCreatedRow: Decodable, Sendable {
    let token: String; let expiresAt: Date; let deeplink: String
    enum CodingKeys: String, CodingKey {
        case token, expiresAt = "expires_at", deeplink
    }
    var asInviteCreated: InviteCreated {
        InviteCreated(token: token, expiresAt: expiresAt, deeplink: deeplink)
    }
}

private struct ClaimResultRow: Decodable, Sendable {
    let actorID: String; let teamID: String
    let actorType: String; let displayName: String
    let refreshToken: String?
    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id", teamID = "team_id"
        case actorType = "actor_type", displayName = "display_name"
        case refreshToken = "refresh_token"
    }
    var asClaimResult: ClaimResult {
        ClaimResult(
            actorID: actorID, teamID: teamID,
            actorType: actorType, displayName: displayName,
            refreshToken: refreshToken
        )
    }
}
