import Foundation
import SwiftData

@Model
public final class CachedActor {
    @Attribute(.unique) public var actorId: String
    public var teamId: String
    public var actorType: String
    public var userId: String?
    public var invitedByActorId: String?
    public var displayName: String
    public var lastActiveAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var memberStatus: String?
    public var teamRole: String?
    public var agentKind: String?
    public var agentStatus: String?

    public init(
        actorId: String, teamId: String, actorType: String,
        userId: String? = nil, invitedByActorId: String? = nil,
        displayName: String, lastActiveAt: Date? = nil,
        createdAt: Date = .now, updatedAt: Date = .now,
        memberStatus: String? = nil, teamRole: String? = nil,
        agentKind: String? = nil, agentStatus: String? = nil
    ) {
        self.actorId = actorId; self.teamId = teamId; self.actorType = actorType
        self.userId = userId; self.invitedByActorId = invitedByActorId
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
