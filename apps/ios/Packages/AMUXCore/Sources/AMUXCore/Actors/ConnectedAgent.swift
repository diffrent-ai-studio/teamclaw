import Foundation

public struct ConnectedAgent: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let agentKind: String
    public let permissionLevel: String
    public let lastActiveAt: Date?
    /// The daemon's MQTT device identifier, taken from `agents.device_id`.
    /// Nil when the daemon hasn't registered one yet (old daemon or offline
    /// since before the column existed).
    public let deviceID: String?

    public init(id: String, displayName: String, agentKind: String,
                permissionLevel: String, lastActiveAt: Date?,
                deviceID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.agentKind = agentKind
        self.permissionLevel = permissionLevel
        self.lastActiveAt = lastActiveAt
        self.deviceID = deviceID
    }

    public var isOnline: Bool {
        guard let lastActiveAt else { return false }
        return Date().timeIntervalSince(lastActiveAt) < 120
    }
}

public struct AgentAuthorizedHuman: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let permissionLevel: String
    public let grantedByActorID: String?
    public let lastActiveAt: Date?

    public init(id: String, displayName: String, permissionLevel: String,
                grantedByActorID: String?, lastActiveAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.permissionLevel = permissionLevel
        self.grantedByActorID = grantedByActorID
        self.lastActiveAt = lastActiveAt
    }

    public var isOnline: Bool {
        guard let lastActiveAt else { return false }
        return Date().timeIntervalSince(lastActiveAt) < 120
    }
}
