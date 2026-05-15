import Foundation
import SwiftData
import Testing
@testable import AMUXCore

@Suite("IdeaStore")
struct IdeaStoreTests {

    @MainActor
    @Test("reload partitions active and archived ideas and mirrors them locally")
    func reloadPartitionsAndMirrorsIdeas() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repository = InMemoryIdeaRepository(
            ideas: [
                IdeaRecord(
                    id: "idea-open",
                    teamID: "team-1",
                    workspaceID: "workspace-1",
                    createdByActorID: "member-1",
                    title: "Open idea",
                    description: "Ship the open idea",
                    status: "open",
                    archived: false,
                    createdAt: .distantPast,
                    updatedAt: .distantPast
                ),
                IdeaRecord(
                    id: "idea-archived",
                    teamID: "team-1",
                    workspaceID: "workspace-2",
                    createdByActorID: "member-2",
                    title: "Archived idea",
                    description: "Already done",
                    status: "done",
                    archived: true,
                    createdAt: .now,
                    updatedAt: .now
                ),
            ]
        )
        let store = IdeaStore(teamID: "team-1", repository: repository, modelContext: context)

        await store.reload()

        #expect(store.ideas.map(\.id) == ["idea-open"])
        #expect(store.archivedIdeas.map(\.id) == ["idea-archived"])

        let cached = try context.fetch(FetchDescriptor<SessionIdea>(sortBy: [SortDescriptor(\.ideaId)]))
        #expect(cached.map(\.ideaId) == ["idea-archived", "idea-open"])
        #expect(cached.first(where: { $0.ideaId == "idea-open" })?.title == "Open idea")
        #expect(cached.first(where: { $0.ideaId == "idea-archived" })?.archived == true)
    }

    @MainActor
    @Test("create update and archive keep remote state and local cache aligned")
    func createUpdateAndArchiveStayAligned() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repository = InMemoryIdeaRepository(ideas: [])
        let store = IdeaStore(teamID: "team-1", repository: repository, modelContext: context)

        await store.createIdea(
            title: "First idea",
            description: "Initial description",
            workspaceID: "workspace-1"
        )

        #expect(store.ideas.map(\.title) == ["First idea"])
        #expect(await repository.recordedCreatedInputs().map(\.title) == ["First idea"])

        let createdID = try #require(store.ideas.first?.id)

        await store.updateIdea(
            ideaID: createdID,
            title: "Renamed idea",
            description: "Edited description",
            status: "in_progress",
            workspaceID: "workspace-2"
        )

        let updated = try #require(store.ideas.first)
        #expect(updated.title == "Renamed idea")
        #expect(updated.description == "Edited description")
        #expect(updated.status == "in_progress")
        #expect(updated.workspaceID == "workspace-2")

        await store.setArchived(ideaID: createdID, archived: true)

        #expect(store.ideas.isEmpty)
        #expect(store.archivedIdeas.map(\.id) == [createdID])
        let archiveInputs = await repository.recordedArchiveInputs()
        #expect(archiveInputs.count == 1)
        #expect(archiveInputs.first?.0 == createdID)
        #expect(archiveInputs.first?.1 == true)

        let cached = try context.fetch(FetchDescriptor<SessionIdea>())
        #expect(cached.count == 1)
        #expect(cached.first?.ideaId == createdID)
        #expect(cached.first?.archived == true)
        #expect(cached.first?.workspaceId == "workspace-2")
    }

    @MainActor
    @Test("general workspace stays empty in idea records")
    func generalWorkspaceStaysEmpty() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repository = InMemoryIdeaRepository(ideas: [])
        let store = IdeaStore(teamID: "team-1", repository: repository, modelContext: context)

        await store.createIdea(
            title: "General idea",
            description: "No explicit workspace",
            workspaceID: ""
        )

        let created = try #require(store.ideas.first)
        #expect(created.workspaceID.isEmpty)
        #expect(await repository.recordedCreatedInputs().first?.workspaceID == "")
    }
}

private actor InMemoryIdeaRepository: IdeaRepository {
    private var ideasByID: [String: IdeaRecord]
    private var createdInputs: [IdeaCreateInput] = []
    private var archiveInputs: [(String, Bool)] = []

    init(ideas: [IdeaRecord]) {
        self.ideasByID = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id, $0) })
    }

    func listIdeas(teamID: String) async throws -> [IdeaRecord] {
        ideasByID.values
            .filter { $0.teamID == teamID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func createIdea(teamID: String, input: IdeaCreateInput) async throws -> IdeaRecord {
        createdInputs.append(input)
        let idea = IdeaRecord(
            id: "idea-\(createdInputs.count)",
            teamID: teamID,
            workspaceID: input.workspaceID,
            createdByActorID: "member-1",
            title: input.title,
            description: input.description,
            status: "open",
            archived: false,
            createdAt: .now,
            updatedAt: .now
        )
        ideasByID[idea.id] = idea
        return idea
    }

    func updateIdea(ideaID: String, input: IdeaUpdateInput) async throws -> IdeaRecord {
        guard var existing = ideasByID[ideaID] else {
            throw InMemoryError.missingIdea
        }
        existing.workspaceID = input.workspaceID
        existing.title = input.title
        existing.description = input.description
        existing.status = input.status
        existing.updatedAt = .now
        ideasByID[ideaID] = existing
        return existing
    }

    func setArchived(ideaID: String, archived: Bool) async throws -> IdeaRecord {
        archiveInputs.append((ideaID, archived))
        guard var existing = ideasByID[ideaID] else {
            throw InMemoryError.missingIdea
        }
        existing.archived = archived
        existing.updatedAt = .now
        ideasByID[ideaID] = existing
        return existing
    }

    func recordedCreatedInputs() -> [IdeaCreateInput] {
        createdInputs
    }

    func recordedArchiveInputs() -> [(String, Bool)] {
        archiveInputs
    }

    enum InMemoryError: Error {
        case missingIdea
    }
}

@MainActor
private func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: AMUXSchemaV1.self)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: configuration)
}
