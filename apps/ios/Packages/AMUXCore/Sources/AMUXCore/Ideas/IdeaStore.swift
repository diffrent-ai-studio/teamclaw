import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class IdeaStore {
    public private(set) var ideas: [IdeaRecord] = []
    public private(set) var archivedIdeas: [IdeaRecord] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let teamID: String
    private let repository: any IdeaRepository
    private let modelContext: ModelContext

    public init(teamID: String, repository: any IdeaRepository, modelContext: ModelContext) {
        self.teamID = teamID
        self.repository = repository
        self.modelContext = modelContext
    }

    public func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let remoteIdeas = try await repository.listIdeas(teamID: teamID)
            apply(remoteIdeas)
            IdeaCacheSynchronizer.upsert(remoteIdeas, modelContext: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func createIdea(title: String, description: String, workspaceID: String) async -> Bool {
        do {
            let created = try await repository.createIdea(
                teamID: teamID,
                input: IdeaCreateInput(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    workspaceID: workspaceID
                )
            )
            merge(created)
            IdeaCacheSynchronizer.upsert(created, modelContext: modelContext)
            try? modelContext.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func updateIdea(
        ideaID: String,
        title: String,
        description: String,
        status: String,
        workspaceID: String
    ) async -> Bool {
        do {
            let updated = try await repository.updateIdea(
                ideaID: ideaID,
                input: IdeaUpdateInput(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: status,
                    workspaceID: workspaceID
                )
            )
            merge(updated)
            IdeaCacheSynchronizer.upsert(updated, modelContext: modelContext)
            try? modelContext.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func setArchived(ideaID: String, archived: Bool) async -> Bool {
        do {
            let updated = try await repository.setArchived(ideaID: ideaID, archived: archived)
            merge(updated)
            IdeaCacheSynchronizer.upsert(updated, modelContext: modelContext)
            try? modelContext.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func idea(id: String) -> IdeaRecord? {
        (ideas + archivedIdeas).first(where: { $0.id == id })
    }

    private func apply(_ records: [IdeaRecord]) {
        let sorted = sort(records)
        ideas = sorted.filter { !$0.archived }
        archivedIdeas = sorted.filter(\.archived)
    }

    private func merge(_ record: IdeaRecord) {
        var all = Dictionary(uniqueKeysWithValues: (ideas + archivedIdeas).map { ($0.id, $0) })
        all[record.id] = record
        apply(Array(all.values))
    }

    private func sort(_ records: [IdeaRecord]) -> [IdeaRecord] {
        records.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
