import SwiftUI
import AMUXSharedUI
import SwiftData
import AMUXCore

public struct InviteSheet: View {
    let session: Session
    let teamclawService: TeamclawService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var members: [CachedActor] = []
    @State private var selectedIds: Set<String> = []
    @State private var isSending = false

    public init(session: Session, teamclawService: TeamclawService) {
        self.session = session
        self.teamclawService = teamclawService
    }

    public var body: some View {
        NavigationStack {
            List(members, id: \.actorId) { member in
                HStack {
                    Text(member.displayName)
                    Spacer()
                    if selectedIds.contains(member.actorId) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.amux.cinnabar)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedIds.contains(member.actorId) {
                        selectedIds.remove(member.actorId)
                    } else {
                        selectedIds.insert(member.actorId)
                    }
                }
            }
            .navigationTitle("Invite to Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { sendInvites() } label: {
                        Text("Invite")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .liquidGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIds.isEmpty || isSending)
                    .opacity(selectedIds.isEmpty || isSending ? 0.4 : 1)
                }
            }
            .task { loadMembers() }
        }
    }

    private func loadMembers() {
        let descriptor = FetchDescriptor<CachedActor>(
            predicate: #Predicate { $0.actorType == "member" },
            sortBy: [SortDescriptor(\.displayName)]
        )
        members = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func sendInvites() {
        isSending = true

        Task {
            do {
                let repository = try SupabaseSessionRepository()
                try await repository.addParticipants(
                    sessionID: session.sessionId,
                    actorIDs: Array(selectedIds)
                )
                await MainActor.run {
                    isSending = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                }
            }
        }
    }
}
