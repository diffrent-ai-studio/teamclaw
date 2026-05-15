import SwiftUI
import AMUXCore

public struct SessionMemberSheet: View {
    public struct HumanRow: Identifiable, Equatable {
        public let id: String
        public let displayName: String
        public let isOnline: Bool
        public let canRemove: Bool
    }
    public struct AgentRow: Identifiable, Equatable {
        public let id: String                 // agent_id
        public let displayName: String
        public let workspacePath: String
        public let agentType: String          // "Claude" / "OpenCode" / "Codex"
        public let runtimeState: AgentChipBar.RuntimeChipState
        public let availableModels: [String]
        public let currentModel: String?
    }

    let humans: [HumanRow]
    let agents: [AgentRow]
    let onRemoveHuman: (String) -> Void
    let onRestartRuntime: (String) -> Void
    let onChangeModel: (String, String) -> Void
    let onRemoveAgent: (String) -> Void
    let onAddAgent: () -> Void
    let onAddMember: () -> Void

    public init(humans: [HumanRow], agents: [AgentRow],
                onRemoveHuman: @escaping (String) -> Void,
                onRestartRuntime: @escaping (String) -> Void,
                onChangeModel: @escaping (String, String) -> Void,
                onRemoveAgent: @escaping (String) -> Void,
                onAddAgent: @escaping () -> Void,
                onAddMember: @escaping () -> Void) {
        self.humans = humans; self.agents = agents
        self.onRemoveHuman = onRemoveHuman
        self.onRestartRuntime = onRestartRuntime
        self.onChangeModel = onChangeModel
        self.onRemoveAgent = onRemoveAgent
        self.onAddAgent = onAddAgent; self.onAddMember = onAddMember
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(humans) { h in
                        HStack {
                            Circle().fill(h.isOnline ? Color.amux.sage : Color.amux.slate).frame(width: 8, height: 8)
                            Text(h.displayName)
                            Spacer()
                            if h.canRemove {
                                Button(role: .destructive) { onRemoveHuman(h.id) } label: {
                                    Image(systemName: "xmark.circle")
                                }
                            }
                        }
                    }
                }
                Section("Agents") {
                    ForEach(agents) { a in
                        AgentMemberRow(
                            row: a,
                            onRestart: { onRestartRuntime(a.id) },
                            onChangeModel: { m in onChangeModel(a.id, m) },
                            onRemove: { onRemoveAgent(a.id) }
                        )
                    }
                }
            }
            .navigationTitle("Actors")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        topAddButton(systemImage: "person.badge.plus", action: onAddMember)
                            .accessibilityLabel("Add member")
                        topAddButton(systemImage: "sparkles", action: onAddAgent)
                            .accessibilityLabel("Add agent")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func topAddButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.amux.cinnabar)
                .frame(width: 36, height: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .liquidGlass(in: Capsule())
    }
}

private struct AgentMemberRow: View {
    let row: SessionMemberSheet.AgentRow
    let onRestart: () -> Void
    let onChangeModel: (String) -> Void
    let onRemove: () -> Void

    /// Whether tapping the row should open agent settings (model picker
    /// today, future expansion later). Disabled while spawning since
    /// nothing is configurable yet — and during stopped/error since the
    /// runtime can't accept a model change in those states.
    private var isInteractive: Bool {
        switch row.runtimeState {
        case .ready, .idle, .active: return true
        case .spawning, .stopped, .error: return false
        }
    }

    var body: some View {
        Group {
            if isInteractive {
                Menu {
                    ForEach(row.availableModels, id: \.self) { m in
                        Button(m) { onChangeModel(m) }
                    }
                } label: { rowContent }
            } else {
                rowContent
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onRemove() } label: { Label("Remove", systemImage: "xmark") }
            Button { onRestart() } label: { Label("Restart", systemImage: "arrow.clockwise") }
                .tint(.orange)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Circle().fill(row.runtimeState.color).frame(width: 8, height: 8)
            Text(row.displayName).fontWeight(.semibold).foregroundStyle(.primary)
            Text(row.agentType).foregroundStyle(.secondary).font(.caption)
            Spacer(minLength: 8)
            trailingLabel
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingLabel: some View {
        // While the runtime is still spawning, the model hasn't been
        // applied yet — showing "default" reads as a misleading model
        // pick. Surface a small spinner instead so the row's status
        // matches the chip dot. Once the runtime's running, fall back
        // to the model picker menu.
        switch row.runtimeState {
        case .spawning:
            ProgressView()
                .controlSize(.small)
        default:
            Text(row.currentModel ?? "default")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
