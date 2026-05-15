import Foundation
import Supabase

public protocol AgentAccessRepository: Sendable {
    /// Every agent the *current* auth user has a row in `agent_member_access` for,
    /// scoped to a specific team.
    func listConnectedAgents(teamID: String) async throws -> [ConnectedAgent]

    /// Every human actor authorized on `agentID`, with their permission level.
    func listAuthorizedHumans(agentID: String) async throws -> [AgentAuthorizedHuman]

    /// Whether the current auth user can manage agent-member access for a team.
    func canManageAuthorizedHumans(teamID: String) async throws -> Bool

    /// Grant access for a member on an agent, upserting if the relationship already exists.
    func grantAuthorizedHuman(agentID: String, memberID: String, permissionLevel: String) async throws

    /// Resolve the current daemon device for a specific agent.
    func deviceID(for agentID: String) async throws -> String?

    /// Total number of agent actors in this team (regardless of which member
    /// has access). Used to decide whether to show the "add the team's first
    /// agent" reminder.
    func teamAgentCount(teamID: String) async throws -> Int
}

public actor SupabaseAgentAccessRepository: AgentAccessRepository {
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

    public func listConnectedAgents(teamID: String) async throws -> [ConnectedAgent] {
        guard let myActorID = try await currentMemberRow(teamID: teamID)?.id else { return [] }

        let accessRows: [AccessRow] = try await client
            .from("agent_member_access")
            .select("agent_id, permission_level")
            .eq("member_id", value: myActorID)
            .execute()
            .value
        let agentIDs = accessRows.map(\.agentID)
        if agentIDs.isEmpty { return [] }

        async let actorRowsTask: [AgentActorRow] = client
            .from("actors")
            .select("id, display_name, last_active_at")
            .in("id", values: agentIDs)
            .eq("team_id", value: teamID)
            .execute()
            .value
        async let agentRowsTask: [AgentKindRow] = client
            .from("agents")
            .select("id, agent_kind, device_id")
            .in("id", values: agentIDs)
            .execute()
            .value
        let actorRows = try await actorRowsTask
        let agentRows = try await agentRowsTask

        let actorByID = Dictionary(uniqueKeysWithValues: actorRows.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: agentRows.map { ($0.id, $0) })

        return accessRows.compactMap { row in
            guard let actor = actorByID[row.agentID] else { return nil }
            let agent = agentByID[row.agentID]
            return ConnectedAgent(
                id: row.agentID,
                displayName: actor.displayName,
                agentKind: agent?.agentKind ?? "",
                permissionLevel: row.permissionLevel,
                lastActiveAt: actor.lastActiveAt,
                deviceID: agent?.deviceID
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func listAuthorizedHumans(agentID: String) async throws -> [AgentAuthorizedHuman] {
        let accessRows: [AccessDetailRow] = try await client
            .from("agent_member_access")
            .select("member_id, permission_level, granted_by_member_id")
            .eq("agent_id", value: agentID)
            .execute()
            .value
        let memberIDs = accessRows.map(\.memberID)
        if memberIDs.isEmpty { return [] }

        let actorRows: [HumanActorRow] = try await client
            .from("actors")
            .select("id, display_name, last_active_at, actor_type")
            .in("id", values: memberIDs)
            .execute()
            .value
        let byID = Dictionary(uniqueKeysWithValues: actorRows.map { ($0.id, $0) })

        return accessRows.compactMap { row in
            guard let actor = byID[row.memberID], actor.actorType == "member"
            else { return nil }
            return AgentAuthorizedHuman(
                id: row.memberID,
                displayName: actor.displayName,
                permissionLevel: row.permissionLevel,
                grantedByActorID: row.grantedByActorID,
                lastActiveAt: actor.lastActiveAt
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func canManageAuthorizedHumans(teamID: String) async throws -> Bool {
        guard let member = try await currentMemberRow(teamID: teamID) else { return false }
        return member.teamRole == "owner" || member.teamRole == "admin"
    }

    public func grantAuthorizedHuman(agentID: String, memberID: String, permissionLevel: String) async throws {
        guard let currentMemberID = try await currentMemberRow(teamID: nil)?.id else {
            throw AgentAccessRepositoryError.missingCurrentMember
        }

        _ = try await client
            .from("agent_member_access")
            .upsert(
                AgentMemberAccessWriteRow(
                    agentID: agentID,
                    memberID: memberID,
                    permissionLevel: permissionLevel,
                    grantedByMemberID: currentMemberID
                ),
                onConflict: "agent_id,member_id"
            )
            .execute()
    }

    public func deviceID(for agentID: String) async throws -> String? {
        let rows: [AgentKindRow] = try await client
            .from("agents")
            .select("id, agent_kind, device_id")
            .eq("id", value: agentID)
            .execute()
            .value
        return rows.first?.deviceID
    }

    public func teamAgentCount(teamID: String) async throws -> Int {
        let rows: [AgentIDOnlyRow] = try await client
            .from("actors")
            .select("id")
            .eq("team_id", value: teamID)
            .eq("actor_type", value: "agent")
            .execute()
            .value
        return rows.count
    }

    private func currentMemberRow(teamID: String?) async throws -> CurrentMemberRow? {
        let session = try await client.auth.session
        let userID = session.user.id.uuidString.lowercased()

        var query = client
            .from("actor_directory")
            .select("id, team_role")
            .eq("user_id", value: userID)
            .eq("actor_type", value: "member")

        if let teamID {
            query = query.eq("team_id", value: teamID)
        }

        let rows: [CurrentMemberRow] = try await query.execute().value
        return rows.first
    }
}

public enum AgentAccessRepositoryError: LocalizedError {
    case missingCurrentMember

    public var errorDescription: String? {
        switch self {
        case .missingCurrentMember:
            return "Current member actor was not found."
        }
    }
}

// MARK: - Wire types

private struct MyActorRow: Decodable, Sendable {
    let id: String
}

private struct CurrentMemberRow: Decodable, Sendable {
    let id: String
    let teamRole: String?

    enum CodingKeys: String, CodingKey {
        case id
        case teamRole = "team_role"
    }
}

private struct AccessRow: Decodable, Sendable {
    let agentID: String
    let permissionLevel: String
    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case permissionLevel = "permission_level"
    }
}

private struct AccessDetailRow: Decodable, Sendable {
    let memberID: String
    let permissionLevel: String
    let grantedByActorID: String?
    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case permissionLevel = "permission_level"
        case grantedByActorID = "granted_by_member_id"
    }
}

private struct AgentActorRow: Decodable, Sendable {
    let id: String
    let displayName: String
    let lastActiveAt: Date?
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case lastActiveAt = "last_active_at"
    }
}

private struct AgentKindRow: Decodable, Sendable {
    let id: String
    let agentKind: String
    let deviceID: String?
    enum CodingKeys: String, CodingKey {
        case id
        case agentKind = "agent_kind"
        case deviceID = "device_id"
    }
}

private struct AgentIDOnlyRow: Decodable, Sendable {
    let id: String
}

private struct HumanActorRow: Decodable, Sendable {
    let id: String
    let displayName: String
    let lastActiveAt: Date?
    let actorType: String
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case lastActiveAt = "last_active_at"
        case actorType = "actor_type"
    }
}

private struct AgentMemberAccessWriteRow: Encodable, Sendable {
    let agentID: String
    let memberID: String
    let permissionLevel: String
    let grantedByMemberID: String

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case memberID = "member_id"
        case permissionLevel = "permission_level"
        case grantedByMemberID = "granted_by_member_id"
    }
}
