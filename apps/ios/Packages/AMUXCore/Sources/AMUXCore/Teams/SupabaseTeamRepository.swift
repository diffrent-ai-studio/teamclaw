import Foundation
import Supabase

public struct TeamDetails: Equatable, Sendable {
    public let id: String
    public let name: String
    public let slug: String
    public let createdAt: Date
    public let ownerDisplayName: String?

    public init(id: String, name: String, slug: String,
                createdAt: Date, ownerDisplayName: String?) {
        self.id = id; self.name = name; self.slug = slug
        self.createdAt = createdAt
        self.ownerDisplayName = ownerDisplayName
    }
}

public protocol TeamRepository: Sendable {
    func loadDetails(teamID: String) async throws -> TeamDetails
}

public actor SupabaseTeamRepository: TeamRepository {
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

    public func loadDetails(teamID: String) async throws -> TeamDetails {
        let rows: [TeamRow] = try await client
            .from("teams")
            .select("id, name, slug, created_at")
            .eq("id", value: teamID)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else {
            throw NSError(domain: "SupabaseTeamRepository", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "team not found"])
        }

        // Find the earliest owner in this team, join to actor for display_name.
        let ownerRows: [OwnerRow] = try await client
            .from("team_members")
            .select("member_id, created_at")
            .eq("team_id", value: teamID)
            .eq("role", value: "owner")
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value

        var ownerName: String?
        if let ownerID = ownerRows.first?.memberID {
            let actorRows: [ActorNameRow] = try await client
                .from("actors")
                .select("id, display_name")
                .eq("id", value: ownerID)
                .limit(1)
                .execute()
                .value
            ownerName = actorRows.first?.displayName
        }

        return TeamDetails(
            id: row.id,
            name: row.name,
            slug: row.slug,
            createdAt: row.createdAt,
            ownerDisplayName: ownerName
        )
    }
}

private struct TeamRow: Decodable, Sendable {
    let id: String
    let name: String
    let slug: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case createdAt = "created_at"
    }
}

private struct OwnerRow: Decodable, Sendable {
    let memberID: String
    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
    }
}

private struct ActorNameRow: Decodable, Sendable {
    let id: String
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}
