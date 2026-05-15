import Foundation

public struct ActorRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let teamID: String
    public let actorType: String
    public let userID: String?
    public let invitedByActorID: String?
    public let displayName: String
    public let lastActiveAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public let memberStatus: String?
    public let teamRole: String?

    public let agentKind: String?
    public let agentStatus: String?

    public init(
        id: String, teamID: String, actorType: String,
        userID: String?, invitedByActorID: String?,
        displayName: String, lastActiveAt: Date?,
        createdAt: Date, updatedAt: Date,
        memberStatus: String?, teamRole: String?,
        agentKind: String?, agentStatus: String?
    ) {
        self.id = id; self.teamID = teamID; self.actorType = actorType
        self.userID = userID; self.invitedByActorID = invitedByActorID
        self.displayName = displayName; self.lastActiveAt = lastActiveAt
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.memberStatus = memberStatus; self.teamRole = teamRole
        self.agentKind = agentKind; self.agentStatus = agentStatus
    }

    public var isMember: Bool { actorType == "member" }
    public var isAgent: Bool  { actorType == "agent" }
    public var isOwner: Bool  { teamRole == "owner" }

    public var isOnline: Bool {
        guard let last = lastActiveAt else { return false }
        return Date().timeIntervalSince(last) < 90
    }

    public var roleLabel: String {
        switch teamRole {
        case "owner":  return "Owner"
        case "admin":  return "Admin"
        case "member": return "Member"
        default:       return "—"
        }
    }
}
