import SwiftUI
import AMUXCore

// MARK: - AddAgentSheet

/// Two-step picker presented from `SessionDetailView` when the user taps
/// "Add agent" in the session member sheet:
///
///   1. List of `ConnectedAgent` candidates (already filtered to exclude
///      agents currently in the session).
///   2. Tap a row → `AgentConfigSheet` to choose workspace + agent type.
///   3. On confirm, hand the chosen `(actorID, workspaceID, workspacePath,
///      agentType)` back to the parent which calls `addAgent` on the VM.
///
/// Workspace loading mirrors `NewSessionSheet`: a `WorkspaceStore` is spun
/// up on `task`, then we filter to workspaces owned by the chosen agent
/// (falling back to all workspaces if none match).
public struct AddAgentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let candidates: [ConnectedAgent]
    let teamID: String
    let onConfirm: (_ actorID: String,
                    _ workspaceID: String,
                    _ workspacePath: String,
                    _ agentType: AgentConfigSheet.AgentType) -> Void

    @State private var workspaceStore: WorkspaceStore?
    @State private var pendingAgent: ConnectedAgent?

    public init(candidates: [ConnectedAgent],
                teamID: String,
                onConfirm: @escaping (_ actorID: String,
                                      _ workspaceID: String,
                                      _ workspacePath: String,
                                      _ agentType: AgentConfigSheet.AgentType) -> Void) {
        self.candidates = candidates
        self.teamID = teamID
        self.onConfirm = onConfirm
    }

    private var workspaces: [WorkspaceRecord] { workspaceStore?.workspaces ?? [] }

    public var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No agents available",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("All connected agents are already in this session, or no agents are reachable.")
                    )
                } else {
                    ForEach(candidates) { agent in
                        Button {
                            pendingAgent = agent
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(agent.isOnline ? .green : .gray.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.displayName).font(.body)
                                    if !agent.agentKind.isEmpty {
                                        Text(agent.agentKind.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Add Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $pendingAgent) { agent in
            // Match NewSessionSheet pattern: prefer workspaces owned by the
            // chosen agent; fall back to all workspaces if none match.
            let agentWorkspaces = workspaces
                .filter { $0.agentID == agent.id }
                .map { WorkspaceRef(id: $0.id, path: $0.displayName.isEmpty ? $0.path : $0.displayName) }
            let allWorkspaceRefs = agentWorkspaces.isEmpty
                ? workspaces.map { WorkspaceRef(id: $0.id, path: $0.displayName.isEmpty ? $0.path : $0.displayName) }
                : agentWorkspaces

            AgentConfigSheet(
                actorDisplayName: agent.displayName,
                workspaces: allWorkspaceRefs,
                onConfirm: { sel in
                    // Resolve the chosen workspace's real filesystem path
                    // (NewSessionSheet uses .path here, not displayName, so
                    // the daemon spawns in the right cwd).
                    let wsPath = workspaces.first(where: { $0.id == sel.workspaceID })?.path ?? ""
                    onConfirm(agent.id, sel.workspaceID, wsPath, sel.agentType)
                    pendingAgent = nil
                    dismiss()
                },
                onCancel: {
                    pendingAgent = nil
                }
            )
        }
        .task {
            guard workspaceStore == nil, !teamID.isEmpty else { return }
            if let repository = try? SupabaseWorkspaceRepository() {
                workspaceStore = WorkspaceStore(teamID: teamID, repository: repository)
                await workspaceStore?.reload(agentID: nil)
            }
        }
    }
}
