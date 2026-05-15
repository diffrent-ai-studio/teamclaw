import Foundation
import Supabase

/// Snapshot of a Supabase `messages` row for the session-resume seed
/// path. Only the fields the iOS UI actually needs to render a past
/// turn (user prompt or finalized agent reply) are pulled — tool calls,
/// thinking deltas, and other intermediate ACP events are intentionally
/// not represented here.
public struct MessageRecord: Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let senderActorID: String
    public let kind: String
    public let content: String
    public let createdAt: Date
    /// Model id is currently stored inside `messages.metadata` JSON; not
    /// surfaced through the seed today. Left nil here until we add a typed
    /// metadata path.
    public let model: String?
    /// Daemon-assigned ACP turn correlation. Same value across rows the
    /// daemon flushed from one turn (ToolUse mid-stream causes a flush
    /// + a continuation flush at Active→Idle). The seed path uses this
    /// to merge those rows into a single bubble. nil for pre-turn_id
    /// rows or non-agent kinds.
    public let turnID: String?
}

/// Input shape for inserting a chat message into Supabase. iOS writes
/// human prompts here so collaborators on cold-launch get a complete
/// session history (the daemon only persists agent replies). RLS
/// `messages_insert_if_session_participant` gates on `sender_actor_id ==
/// app.current_actor_id()` and the caller's session-participant status.
public struct MessageInsertInput: Equatable, Sendable {
    public let id: String
    public let teamID: String
    public let sessionID: String
    public let senderActorID: String
    public let kind: String
    public let content: String
    /// Actor ids of chip-bar mentions. Stored in `messages.metadata` as
    /// `{"mention_actor_ids": [...]}` so the daemon can query historical
    /// routing context and the seed path can reconstruct directed vs
    /// broadcast turn groupings.
    public let mentionActorIDs: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        teamID: String,
        sessionID: String,
        senderActorID: String,
        kind: String = "text",
        content: String,
        mentionActorIDs: [String] = []
    ) {
        self.id = id
        self.teamID = teamID
        self.sessionID = sessionID
        self.senderActorID = senderActorID
        self.kind = kind
        self.content = content
        self.mentionActorIDs = mentionActorIDs
    }
}

public protocol MessagesRepository: Sendable {
    func listForSession(sessionID: String) async throws -> [MessageRecord]
    func insert(_ input: MessageInsertInput) async throws
}

public actor SupabaseMessagesRepository: MessagesRepository {
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

    public func insert(_ input: MessageInsertInput) async throws {
        // Build metadata JSON when mention ids are present. The daemon reads
        // `metadata->>'mention_actor_ids'` for historical routing context.
        let metadataJSON: String?
        if !input.mentionActorIDs.isEmpty,
           let data = try? JSONEncoder().encode(["mention_actor_ids": input.mentionActorIDs]),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = nil
        }
        try await client
            .from("messages")
            .insert(
                MessageInsertRow(
                    id: input.id,
                    teamID: input.teamID,
                    sessionID: input.sessionID,
                    senderActorID: input.senderActorID,
                    kind: input.kind,
                    content: input.content,
                    metadata: metadataJSON
                ),
                returning: .minimal
            )
            .execute()
    }

    public func listForSession(sessionID: String) async throws -> [MessageRecord] {
        let rows: [MessageRow] = try await client
            .from("messages")
            .select("id, session_id, sender_actor_id, kind, content, created_at, model, turn_id")
            .eq("session_id", value: sessionID)
            .order("created_at", ascending: true)
            .execute()
            .value

        return rows.map { row in
            MessageRecord(
                id: row.id,
                sessionID: row.sessionID,
                senderActorID: row.senderActorID,
                kind: row.kind,
                content: row.content,
                createdAt: row.createdAt,
                model: row.model,
                turnID: row.turnID
            )
        }
    }
}

private struct MessageInsertRow: Encodable, Sendable {
    let id: String
    let teamID: String
    let sessionID: String
    let senderActorID: String
    let kind: String
    let content: String
    /// Raw JSON string for the `metadata` JSONB column. Nil = omit the field
    /// entirely so Supabase uses the column default (null / {}).
    let metadata: String?

    enum CodingKeys: String, CodingKey {
        case id
        case teamID = "team_id"
        case sessionID = "session_id"
        case senderActorID = "sender_actor_id"
        case kind
        case content
        case metadata
    }
}

private struct MessageRow: Decodable, Sendable {
    let id: String
    let sessionID: String
    let senderActorID: String
    let kind: String
    let content: String
    let createdAt: Date
    let model: String?
    let turnID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case senderActorID = "sender_actor_id"
        case kind
        case content
        case createdAt = "created_at"
        case model
        case turnID = "turn_id"
    }
}
