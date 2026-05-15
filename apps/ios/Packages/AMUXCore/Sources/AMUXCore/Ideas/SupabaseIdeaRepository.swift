import Foundation
import Supabase

public enum IdeaRepositoryError: LocalizedError {
    case missingTitle
    case emptyResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Title is required."
        case .emptyResponse(let functionName):
            return "\(functionName) returned no rows."
        }
    }
}

public actor SupabaseIdeaRepository: IdeaRepository {
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

    public func listIdeas(teamID: String) async throws -> [IdeaRecord] {
        let rows: [IdeaRow] = try await client
            .from("ideas")
            .select(
                """
                id,
                team_id,
                workspace_id,
                created_by_actor_id,
                title,
                description,
                status,
                archived,
                created_at,
                updated_at
                """
            )
            .eq("team_id", value: teamID)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return rows.map(\.record)
    }

    public func createIdea(teamID: String, input: IdeaCreateInput) async throws -> IdeaRecord {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceID = normalizedWorkspaceID(input.workspaceID)

        guard !title.isEmpty else {
            throw IdeaRepositoryError.missingTitle
        }

        let rows: [IdeaRow] = try await client
            .rpc(
                "create_idea",
                params: CreateIdeaParams(
                    teamID: teamID,
                    workspaceID: workspaceID,
                    title: title,
                    description: input.description
                )
            )
            .execute()
            .value

        guard let row = rows.first else {
            throw IdeaRepositoryError.emptyResponse("create_idea")
        }

        return row.record
    }

    public func updateIdea(ideaID: String, input: IdeaUpdateInput) async throws -> IdeaRecord {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceID = normalizedWorkspaceID(input.workspaceID)

        guard !title.isEmpty else {
            throw IdeaRepositoryError.missingTitle
        }

        let rows: [IdeaRow] = try await client
            .rpc(
                "update_idea",
                params: UpdateIdeaParams(
                    ideaID: ideaID,
                    workspaceID: workspaceID,
                    title: title,
                    description: input.description,
                    status: input.status
                )
            )
            .execute()
            .value

        guard let row = rows.first else {
            throw IdeaRepositoryError.emptyResponse("update_idea")
        }

        return row.record
    }

    public func setArchived(ideaID: String, archived: Bool) async throws -> IdeaRecord {
        let rows: [IdeaRow] = try await client
            .rpc(
                "archive_idea",
                params: ArchiveIdeaParams(ideaID: ideaID, archived: archived)
            )
            .execute()
            .value

        guard let row = rows.first else {
            throw IdeaRepositoryError.emptyResponse("archive_idea")
        }

        return row.record
    }

    private func normalizedWorkspaceID(_ workspaceID: String) -> String? {
        let trimmed = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CreateIdeaParams: Encodable {
    let teamID: String
    let workspaceID: String?
    let title: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case teamID = "p_team_id"
        case workspaceID = "p_workspace_id"
        case title = "p_title"
        case description = "p_description"
    }
}

private struct UpdateIdeaParams: Encodable {
    let ideaID: String
    let workspaceID: String?
    let title: String
    let description: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case ideaID = "p_idea_id"
        case workspaceID = "p_workspace_id"
        case title = "p_title"
        case description = "p_description"
        case status = "p_status"
    }
}

private struct ArchiveIdeaParams: Encodable {
    let ideaID: String
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case ideaID = "p_idea_id"
        case archived = "p_archived"
    }
}

private struct IdeaRow: Decodable, Sendable {
    let id: String
    let teamID: String
    let workspaceID: String?
    let createdByActorID: String
    let title: String
    let description: String
    let status: String
    let archived: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case workspaceID = "workspace_id"
        case createdByActorID = "created_by_actor_id"
        case title
        case description
        case status
        case archived
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var record: IdeaRecord {
        IdeaRecord(
            id: id,
            teamID: teamID,
            workspaceID: workspaceID ?? "",
            createdByActorID: createdByActorID,
            title: title,
            description: description,
            status: status,
            archived: archived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
