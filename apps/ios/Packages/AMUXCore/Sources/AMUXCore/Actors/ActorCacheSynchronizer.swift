import Foundation
import SwiftData

@MainActor
public enum ActorCacheSynchronizer {
    public static func upsert(_ records: [ActorRecord], modelContext: ModelContext) {
        for r in records { upsert(r, modelContext: modelContext) }
        try? modelContext.save()
    }

    public static func upsert(_ record: ActorRecord, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CachedActor>(
            predicate: #Predicate { $0.actorId == record.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.teamId           = record.teamID
            existing.actorType        = record.actorType
            existing.userId           = record.userID
            existing.invitedByActorId = record.invitedByActorID
            existing.displayName      = record.displayName
            existing.lastActiveAt     = record.lastActiveAt
            existing.createdAt        = record.createdAt
            existing.updatedAt        = record.updatedAt
            existing.memberStatus     = record.memberStatus
            existing.teamRole         = record.teamRole
            existing.agentKind        = record.agentKind
            existing.agentStatus      = record.agentStatus
        } else {
            modelContext.insert(CachedActor(
                actorId: record.id, teamId: record.teamID,
                actorType: record.actorType, userId: record.userID,
                invitedByActorId: record.invitedByActorID,
                displayName: record.displayName,
                lastActiveAt: record.lastActiveAt,
                createdAt: record.createdAt, updatedAt: record.updatedAt,
                memberStatus: record.memberStatus, teamRole: record.teamRole,
                agentKind: record.agentKind, agentStatus: record.agentStatus
            ))
        }
    }

    public static func deleteMissing(keeping ids: Set<String>, teamID: String,
                                     modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CachedActor>(
            predicate: #Predicate { $0.teamId == teamID }
        )
        guard let all = try? modelContext.fetch(descriptor) else { return }
        for row in all where !ids.contains(row.actorId) {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }
}
