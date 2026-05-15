import Foundation
import SwiftData

@Model
public final class Session {
    @Attribute(.unique) public var sessionId: String
    public var teamId: String
    public var title: String
    public var createdBy: String
    public var createdAt: Date
    public var summary: String
    public var participantCount: Int
    public var lastMessagePreview: String
    public var lastMessageAt: Date?
    public var ideaId: String
    public var primaryAgentId: String?
    /// User-pinned: floats to the top "Pinned" group in the session list.
    /// Local-only (not synced to Supabase yet).
    public var isPinned: Bool = false
    /// User-archived: hidden from the main session list. Soft-delete only;
    /// no unarchive UI yet. Local-only.
    public var isArchived: Bool = false
    /// Set by NewSessionSheet to the first user message, cleared once the
    /// session/live publish succeeds. The detail view treats this as a
    /// "loading" gate: composer disabled while non-nil so the user can't
    /// race in a second message before the first one has been delivered.
    public var pendingFirstMessage: String?

    public init(
        sessionId: String,
        teamId: String = "",
        title: String = "",
        createdBy: String = "",
        createdAt: Date = .now,
        summary: String = "",
        participantCount: Int = 0,
        lastMessagePreview: String = "",
        lastMessageAt: Date? = nil,
        ideaId: String = "",
        isPinned: Bool = false,
        isArchived: Bool = false,
        pendingFirstMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.teamId = teamId
        self.title = title
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.summary = summary
        self.participantCount = participantCount
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.ideaId = ideaId
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.pendingFirstMessage = pendingFirstMessage
    }
}
