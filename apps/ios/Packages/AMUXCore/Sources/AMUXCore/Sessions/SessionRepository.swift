import Foundation
import Supabase

public struct SessionParticipantInput: Equatable, Sendable {
    public let actorID: String
    public let role: String?

    public init(actorID: String, role: String? = nil) {
        self.actorID = actorID
        self.role = role
    }
}

public struct SessionCreateInput: Equatable, Sendable {
    public let id: String
    public let teamID: String
    public let ideaID: String?
    public let createdByActorID: String
    public let primaryAgentID: String?
    public let mode: String
    public let title: String
    public let summary: String
    public let participants: [SessionParticipantInput]

    public init(
        id: String,
        teamID: String,
        ideaID: String? = nil,
        createdByActorID: String,
        primaryAgentID: String? = nil,
        mode: String = "collab",
        title: String,
        summary: String,
        participants: [SessionParticipantInput]
    ) {
        self.id = id
        self.teamID = teamID
        self.ideaID = ideaID
        self.createdByActorID = createdByActorID
        self.primaryAgentID = primaryAgentID
        self.mode = mode
        self.title = title
        self.summary = summary
        self.participants = participants
    }
}

public struct SessionParticipantRecord: Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let actorID: String
    public let role: String?               // "human" | "agent" | nil
    public let displayName: String
    public let actorType: String           // "human" | "agent"

    public init(id: String, sessionID: String, actorID: String, role: String?,
                displayName: String, actorType: String) {
        self.id = id
        self.sessionID = sessionID
        self.actorID = actorID
        self.role = role
        self.displayName = displayName
        self.actorType = actorType
    }
}

public protocol SessionRepository: Sendable {
    func createSession(_ input: SessionCreateInput) async throws
    func addParticipants(sessionID: String, actorIDs: [String]) async throws
    func listSessionParticipants(sessionID: String) async throws -> [SessionParticipantRecord]
    func removeParticipant(sessionID: String, actorID: String) async throws
}

public enum SessionRepositoryError: LocalizedError {
    case missingTitle
    case missingParticipants

    public var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Session title is required."
        case .missingParticipants:
            return "Session participants are required."
        }
    }
}

public actor SupabaseSessionRepository: SessionRepository {
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

    public func createSession(_ input: SessionCreateInput) async throws {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SessionRepositoryError.missingTitle
        }
        guard !input.participants.isEmpty else {
            throw SessionRepositoryError.missingParticipants
        }

        try await client
            .from("sessions")
            .insert(
                SessionInsertRow(
                    id: input.id,
                    teamID: input.teamID,
                    ideaID: normalized(input.ideaID),
                    createdByActorID: input.createdByActorID,
                    primaryAgentID: normalized(input.primaryAgentID),
                    mode: input.mode,
                    title: title,
                    summary: input.summary
                ),
                returning: .minimal
            )
            .execute()

        try await client
            .from("session_participants")
            .insert(
                input.participants.map { participant in
                    SessionParticipantInsertRow(
                        id: UUID().uuidString.lowercased(),
                        sessionID: input.id,
                        actorID: participant.actorID,
                        role: participant.role
                    )
                },
                returning: .minimal
            )
            .execute()
    }

    public func listSessionParticipants(sessionID: String) async throws -> [SessionParticipantRecord] {
        let rows: [ParticipantJoinRow] = try await client
            .from("session_participants")
            .select("id, session_id, actor_id, role, actors!inner(display_name, actor_type)")
            .eq("session_id", value: sessionID)
            .execute()
            .value
        return rows.map {
            SessionParticipantRecord(
                id: $0.id,
                sessionID: $0.session_id,
                actorID: $0.actor_id,
                role: $0.role,
                displayName: $0.actors.display_name,
                actorType: $0.actors.actor_type
            )
        }
    }

    public func removeParticipant(sessionID: String, actorID: String) async throws {
        try await client
            .from("session_participants")
            .delete()
            .eq("session_id", value: sessionID)
            .eq("actor_id", value: actorID)
            .execute()
    }

    public func addParticipants(sessionID: String, actorIDs: [String]) async throws {
        let rows = actorIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                SessionParticipantInsertRow(
                    id: UUID().uuidString.lowercased(),
                    sessionID: sessionID,
                    actorID: $0,
                    role: nil
                )
            }
        guard !rows.isEmpty else { return }

        try await client
            .from("session_participants")
            .insert(rows, returning: .minimal)
            .execute()
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SessionInsertRow: Encodable, Sendable {
    let id: String
    let teamID: String
    let ideaID: String?
    let createdByActorID: String
    let primaryAgentID: String?
    let mode: String
    let title: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case ideaID = "idea_id"
        case createdByActorID = "created_by_actor_id"
        case primaryAgentID = "primary_agent_id"
        case mode
        case title
        case summary
    }
}

private struct ParticipantJoinRow: Decodable {
    let id: String
    let session_id: String
    let actor_id: String
    let role: String?
    let actors: ActorChild
    struct ActorChild: Decodable {
        let display_name: String
        let actor_type: String
    }
}

private struct SessionParticipantInsertRow: Encodable, Sendable {
    let id: String
    let sessionID: String
    let actorID: String
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case actorID = "actor_id"
        case role
    }
}
