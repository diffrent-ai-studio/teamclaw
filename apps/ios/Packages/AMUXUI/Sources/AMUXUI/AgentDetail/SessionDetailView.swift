import SwiftUI
import SwiftData
import AMUXCore
import AMUXSharedUI

// MARK: - SessionDetailView (iMessage-style chat detail)

public struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SessionDetailViewModel
    @State private var promptText = ""
    @State private var selectedModelId: String?
    @State private var attachments: [URL] = []
    @State private var voiceRecorder = VoiceRecorder(contextualStrings: [
        "Claude", "Claude Code", "Sonnet", "Opus", "Haiku",
        "MQTT", "protobuf", "SwiftUI", "SwiftData",
        "agent", "daemon", "worktree", "workspace",
        "commit", "push", "merge", "pull request",
        "API", "JSON", "YAML", "REST", "gRPC",
    ])
    @State private var isMemberSheetPresented: Bool = false
    @State private var isAddAgentSheetPresented: Bool = false
    @State private var isAddMemberSheetPresented: Bool = false
    /// Cached TeamclawService used to lazily build the OutboxSender once
    /// the modelContext (and therefore its container) is available.
    private let pendingTeamclawService: TeamclawService?

    let connectedAgentsStore: ConnectedAgentsStore?

    public init(runtime: Runtime, mqtt: MQTTService, hub: MQTTMessageHub, peerId: String,
                connectedAgentsStore: ConnectedAgentsStore? = nil) {
        _viewModel = State(initialValue: SessionDetailViewModel(
            runtime: runtime, mqtt: mqtt, hub: hub, peerId: peerId,
            connectedAgentsStore: connectedAgentsStore))
        self.connectedAgentsStore = connectedAgentsStore
        self.pendingTeamclawService = nil
    }

    public init(session: Session, mqtt: MQTTService, hub: MQTTMessageHub, peerId: String,
                teamclawService: TeamclawService?,
                connectedAgentsStore: ConnectedAgentsStore? = nil) {
        _viewModel = State(initialValue: SessionDetailViewModel(
            runtime: nil, mqtt: mqtt, hub: hub, teamID: session.teamId,
            peerId: peerId, session: session,
            teamclawService: teamclawService,
            connectedAgentsStore: connectedAgentsStore))
        self.connectedAgentsStore = connectedAgentsStore
        self.pendingTeamclawService = teamclawService
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isDaemonOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.caption)
                    Text("Daemon offline").font(.caption).fontWeight(.medium)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .liquidGlass(in: Capsule(), tint: .orange, interactive: false)
                .padding(.vertical, 4)
            }
            if let sendError = viewModel.sendErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                    Text(sendError).font(.caption).fontWeight(.medium)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .liquidGlass(in: Capsule(), tint: .red, interactive: false)
                .padding(.vertical, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.events.isEmpty && viewModel.streamingAgentSet.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.quaternary)
                                Text("No messages yet")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }

                        ForEach(viewModel.feedItems) { item in
                            feedItemRow(item)
                                .id(item.id)
                        }

                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.top, 8)
                }
                // Any scroll on the chat surface dismisses the keyboard.
                // .interactively (iMessage-style finger-tracks-keyboard)
                // got swallowed by the composer's nested TextField scroll
                // and the SafeAreaInset hosting it; .immediately is more
                // robust and matches the user's expectation that pulling
                // the chat reveals more chat.
                .scrollDismissesKeyboard(.immediately)
                // Anchor first layout at the bottom natively so a session
                // with hundreds of messages doesn't visibly scroll through
                // the whole history on appear. Previously we called
                // `proxy.scrollTo("bottom")` in `.onAppear`, which animated
                // a scroll across the entire LazyVStack while rows were
                // still being realized — felt frantic. `defaultScrollAnchor`
                // (iOS 17+) skips that traversal: layout starts pinned to
                // the bottom and content above is reachable by dragging up.
                .defaultScrollAnchor(.bottom)
                .onChange(of: viewModel.feedItems.count) {
                    // New user prompts, new agent replies, and new active
                    // stream cards all change feedItems.count — that's the
                    // signal the feed visually grew and we should follow
                    // the bottom. Per-token updates to a live card don't
                    // need scroll-following at this level (the card itself
                    // stays put; the detail view handles the per-token
                    // scroll when the user opens it).
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .navigationTitle(viewModel.sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isMemberSheetPresented = true
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Members")
            }
        }
        // Tab-bar visibility is hoisted to the parent NavigationStack
        // (SessionsTab / IdeasTab), driven by `navigationPath.isEmpty`.
        // Keeping it here meant the modifier was alive until this view
        // fully unmounted on pop, so the bar only animated back after
        // the pop transition finished — a multi-beat lag.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                AgentChipBar(
                    chips: viewModel.memberSheetAgents.map { a in
                        AgentChipBar.AgentChip(
                            id: a.id,
                            displayName: a.displayName,
                            runtimeState: AgentChipBar.RuntimeChipState.fromCore(a.runtimeState)
                        )
                    },
                    selection: Binding(
                        get: { viewModel.agentChipSelection },
                        set: { viewModel.setAgentChipSelection($0) }
                    ),
                    streamingAgentIDs: viewModel.streamingAgentIDs,
                    onInterrupt: { agentID in
                        viewModel.interruptAgent(agentID)
                    }
                )
                Divider().opacity(0.4)
                SessionComposer(
                    promptText: $promptText,
                    selectedModelId: $selectedModelId,
                    attachments: $attachments,
                    voiceRecorder: voiceRecorder,
                    runtime: viewModel.runtime,
                    availableCommands: viewModel.availableCommands,
                    availableMentions: mentionTargets(),
                    sessionID: viewModel.session?.sessionId ?? "",
                    teamID: viewModel.teamIDRef,
                    onSend: {
                        let text = promptText
                        let modelId = resolvedModelId
                        promptText = ""
                        attachments = []
                        Task {
                            try? await viewModel.sendPrompt(text, modelId: modelId, modelContext: modelContext)
                        }
                    },
                    onAgentMention: { target in
                        viewModel.lightAgentChip(target.id)
                    }
                )
            }
        }
        .sheet(isPresented: $isMemberSheetPresented) {
            SessionMemberSheet(
                humans: viewModel.memberSheetHumans.map { h in
                    SessionMemberSheet.HumanRow(
                        id: h.id,
                        displayName: h.displayName,
                        isOnline: h.isOnline,
                        canRemove: h.canRemove
                    )
                },
                agents: viewModel.memberSheetAgents.map { row in
                    SessionMemberSheet.AgentRow(
                        id: row.id,
                        displayName: row.displayName,
                        workspacePath: row.workspacePath,
                        agentType: row.agentType,
                        runtimeState: AgentChipBar.RuntimeChipState.fromCore(row.runtimeState),
                        availableModels: row.availableModels,
                        currentModel: row.currentModel
                    )
                },
                onRemoveHuman: { viewModel.removeHuman($0) },
                onRestartRuntime: { viewModel.restartRuntime(forAgent: $0) },
                onChangeModel: { viewModel.setModel(forAgent: $0, model: $1) },
                onRemoveAgent: { viewModel.removeAgent($0) },
                onAddAgent: { isAddAgentSheetPresented = true },
                onAddMember: { isAddMemberSheetPresented = true }
            )
            .task { await viewModel.refreshMemberSheet() }
            .sheet(isPresented: $isAddAgentSheetPresented) {
                AddAgentSheet(
                    candidates: viewModel.candidatesForAddAgent(),
                    teamID: viewModel.teamIDRef
                ) { actorID, workspaceID, workspacePath, agentType in
                    Task {
                        await viewModel.addAgent(
                            actorID: actorID,
                            workspaceID: workspaceID,
                            worktreePath: workspacePath,
                            agentType: agentType.asAmuxAgentType
                        )
                    }
                }
            }
            .sheet(isPresented: $isAddMemberSheetPresented) {
                AddMemberSheet(
                    excludedActorIDs: viewModel.existingParticipantActorIDs,
                    accessibleAgentIDs: Set(connectedAgentsStore?.agents.map(\.id) ?? []),
                    currentActorID: viewModel.currentHumanActorIDRef
                ) { humanActorIDs in
                    Task { await viewModel.addMembers(humanActorIDs) }
                }
            }
        }
        .task {
            // Build & start the outbox sender once the modelContext (and
            // its container) is available. Idempotent — `OutboxSender.start`
            // bails if a loop task is already running, so re-entry from
            // re-task does not spawn duplicates.
            if viewModel.outboxSender == nil, let svc = pendingTeamclawService {
                let sender = OutboxSender(
                    teamclaw: svc,
                    modelContainer: modelContext.container
                )
                viewModel.outboxSender = sender
            }
            await viewModel.outboxSender?.start()
            viewModel.start(modelContext: modelContext)
            await viewModel.refreshMemberSheet()
        }
        .onChange(of: viewModel.runtime?.status) { _, _ in
            // Bound-runtime lifecycle just transitioned (spawning →
            // running → idle / stopped / etc.). Re-pull agent_runtimes
            // so the member-sheet row dot color tracks reality. The
            // status string lives on Supabase and is one-shot fetched,
            // so without this onChange the snapshot goes stale.
            Task { await viewModel.refreshMemberSheet() }
        }
        .onChange(of: viewModel.isStreaming) { _, newValue in
            // First ACP event arrived — the runtime is definitely up
            // even if the SwiftData Runtime entity's status field hasn't
            // propagated through @Observable yet (a known limitation
            // when SwiftData mutations don't re-evaluate computed nested
            // optionals). Refresh so the chip flips spawning → active
            // and the member sheet row's "loading" turns into the
            // current model picker.
            if newValue {
                Task { await viewModel.refreshMemberSheet() }
            }
        }
        .onChange(of: viewModel.isActive) { _, newValue in
            // isActive covers thinking + tool_use windows ahead of any
            // raw text output. Refresh on the rising edge too so the
            // chip's stop icon appears as soon as the agent starts
            // working, not only when text begins streaming.
            if newValue {
                Task { await viewModel.refreshMemberSheet() }
            }
        }
        .onChange(of: viewModel.isAgentWorking) { _, newValue in
            if newValue {
                Task { await viewModel.refreshMemberSheet() }
            }
        }
        .onDisappear {
            // Do NOT call viewModel.stop() here. SwiftUI fires this hook
            // both when this view is being popped out of the nav stack
            // (true exit) AND when a destination is pushed on top of it
            // (we're still in the back-stack). The two are indistinguishable
            // at this hook, but the cost of treating "push" as "exit" is
            // brutal: cancelling the MQTT task drops every ACP envelope
            // that arrives while StreamingDetailView (or any destination)
            // is on top, so the live-stream view freezes on whatever
            // events it had at push time and the bubbles only appear after
            // popping back triggers incremental sync replay.
            //
            // Lifetime is now owned by the VM itself: its `deinit`
            // cancels the task, which fires when the owning view (the
            // ancestor that holds the VM via @State / @Bindable) drops
            // its last reference. The task captures `self` weakly so
            // the retain cycle that would otherwise prevent deinit is
            // broken.
        }
    }

    private var resolvedModelId: String? {
        if let selectedModelId, !selectedModelId.isEmpty { return selectedModelId }
        if let current = viewModel.runtime?.currentModel, !current.isEmpty { return current }
        return nil
    }

    /// Resolve an agent actor id to a member-sheet display name. Falls
    /// back to a truncated id so an unmapped sender still has a label.
    private func agentDisplayName(for agentID: String) -> String {
        viewModel.memberSheetAgents.first(where: { $0.id == agentID })?.displayName
            ?? String(agentID.prefix(8))
    }

    /// Pick the best single-line summary for the active-stream card.
    /// Priority: live streaming text → most recent thinking/output text
    /// → most recent tool name → "Working…". The card truncates further
    /// at the view layer.
    private func activeStreamLastLine(agentID: String, runtimeEvents: [AgentEvent]) -> String {
        let live = viewModel.streamingTextByAgent[agentID] ?? ""
        if !live.isEmpty { return live.replacingOccurrences(of: "\n", with: " ") }
        if let last = runtimeEvents.reversed().first(where: { e in
            (e.eventType == "output" || e.eventType == "thinking") && !(e.text ?? "").isEmpty
        }) {
            return (last.text ?? "").replacingOccurrences(of: "\n", with: " ")
        }
        if let lastTool = runtimeEvents.reversed().first(where: { $0.eventType == "tool_use" }) {
            return lastTool.toolName.map { "Running \($0)…" } ?? "Working…"
        }
        return "Working…"
    }

    @ViewBuilder
    private func feedItemRow(_ item: FeedItem) -> some View {
        switch item {
        case .userMessage(let event), .permission(let event), .todo(let event), .error(let event):
            EventBubbleView(
                event: event,
                runtime: viewModel.runtime,
                onGrant: { id in Task { try? await viewModel.grantPermission(requestId: id) } },
                onDeny: { id in Task { try? await viewModel.denyPermission(requestId: id) } },
                onRetryOutbox: { msgID in
                    if let sender = viewModel.outboxSender {
                        Task { await sender.retry(messageID: msgID) }
                    }
                }
            )
        case .activeStream(_, let agentID, let runtimeEvents):
            // NavigationLink(destination:) instead of value-based push
            // because the parent NavigationStack uses a `[String]`-typed
            // path (SessionsTab / IdeasTab) — value-based pushes of
            // `TurnRoute` would be silently dropped by SwiftUI when the
            // type doesn't match the path's element type.
            NavigationLink(
                destination: StreamingDetailView(
                    route: TurnRoute(agentID: agentID, frozenTurnID: nil),
                    viewModel: viewModel
                )
            ) {
                ActiveStreamCardView(
                    agentName: agentDisplayName(for: agentID),
                    lastLine: activeStreamLastLine(agentID: agentID, runtimeEvents: runtimeEvents)
                )
            }
            .buttonStyle(.plain)
        case .completedTurn(let id, let agentID, let final, let runtimeEvents):
            CompletedTurnBubbleView(
                finalEvent: final,
                runtime: viewModel.runtime,
                agentName: agentDisplayName(for: agentID),
                detailIcon: {
                    if !runtimeEvents.isEmpty {
                        NavigationLink(
                            destination: StreamingDetailView(
                                route: TurnRoute(agentID: agentID, frozenTurnID: id),
                                viewModel: viewModel
                            )
                        ) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show streaming detail")
                    }
                }
            )
        }
    }

    private func mentionTargets() -> [MentionTarget] {
        let members = viewModel.memberSheetHumans.map { h in
            MentionTarget(id: h.id, displayName: h.displayName, subtitle: "Member", kind: .member)
        }
        let agents = viewModel.memberSheetAgents.map { a in
            // Subtitle shows the agent type only — the lifecycle state is
            // sourced from the agent_runtimes snapshot which is fetched
            // once on sheet open and goes stale fast (e.g. shows "spawning"
            // long after spawn). The chip bar above the composer carries
            // the live state via MQTT-pushed Runtime entities.
            MentionTarget(id: a.id, displayName: a.displayName, subtitle: a.agentType, kind: .agent)
        }
        return agents + members
    }
}

// MARK: - AgentChipBar.RuntimeChipState translation

extension AgentChipBar.RuntimeChipState {
    static func fromCore(_ s: AgentRuntimeChipState) -> AgentChipBar.RuntimeChipState {
        switch s {
        case .spawning: .spawning
        case .ready: .ready
        case .idle: .idle
        case .active: .active
        case .stopped: .stopped
        case .error: .error
        }
    }
}
