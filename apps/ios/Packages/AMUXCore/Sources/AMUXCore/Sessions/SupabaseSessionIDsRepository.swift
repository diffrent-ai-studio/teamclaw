import Foundation
import Supabase

/// Fetches the canonical set of session IDs for a team from Supabase.
/// Used to filter out stale MQTT-era rows that still live in local SwiftData
/// but no longer exist in the authoritative backend.
public protocol SessionIDsRepository: Sendable {
    func listSessionIDs(teamID: String) async throws -> Set<String>
}

public actor SupabaseSessionIDsRepository: SessionIDsRepository {
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

    public func listSessionIDs(teamID: String) async throws -> Set<String> {
        let rows: [IDRow] = try await client
            .from("sessions")
            .select("id")
            .eq("team_id", value: teamID)
            .execute()
            .value
        return Set(rows.map(\.id))
    }
}

private struct IDRow: Decodable, Sendable {
    let id: String
}
