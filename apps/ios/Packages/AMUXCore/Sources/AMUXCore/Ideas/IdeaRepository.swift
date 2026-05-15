import Foundation

public protocol IdeaRepository: Sendable {
    func listIdeas(teamID: String) async throws -> [IdeaRecord]
    func createIdea(teamID: String, input: IdeaCreateInput) async throws -> IdeaRecord
    func updateIdea(ideaID: String, input: IdeaUpdateInput) async throws -> IdeaRecord
    func setArchived(ideaID: String, archived: Bool) async throws -> IdeaRecord
}
