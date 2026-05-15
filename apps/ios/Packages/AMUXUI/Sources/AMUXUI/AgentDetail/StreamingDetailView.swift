import SwiftUI
import SwiftData
import AMUXCore
import AMUXSharedUI

/// Hashable handle for `.navigationDestination(for:)`. The active vs.
/// completed distinction is implicit — the destination view inspects the
/// view-model's current `feedItems` and renders whichever turn matches:
/// active stream takes priority, otherwise the most recent completed
/// turn for that agent. `frozenTurnID` lets a tap on a specific
/// completed-turn icon point back to that exact turn even when the
/// agent has run multiple later turns since.
public struct TurnRoute: Hashable {
    public let agentID: String
    /// Set when navigating from a completed-turn icon to pin to that
    /// specific turn id. Nil when navigating from an active stream — the
    /// destination resolves dynamically.
    public let frozenTurnID: String?

    public init(agentID: String, frozenTurnID: String? = nil) {
        self.agentID = agentID
        self.frozenTurnID = frozenTurnID
    }
}

/// Per-turn streaming detail view pushed from the chat list. Shows the
/// thinking / tool_use / tool_result events that produced the agent's
/// reply, plus the live streaming text when the turn is still in flight.
/// Top-right toolbar holds a stop button while streaming; back is the
/// NavigationStack default.
public struct StreamingDetailView: View {
    let route: TurnRoute
    @Bindable var viewModel: SessionDetailViewModel

    public init(route: TurnRoute, viewModel: SessionDetailViewModel) {
        self.route = route
        self.viewModel = viewModel
    }

    /// Resolved turn data. We re-derive on every render from the
    /// view-model's `feedItems` so streaming deltas + final-event arrival
    /// reflect immediately. Returns events + isActive flag.
    private var resolved: (events: [AgentEvent], isActive: Bool, agentName: String) {
        // Look for a frozen completed turn first — the user explicitly
        // pinned this when they tapped the bubble's detail icon.
        if let pinned = route.frozenTurnID {
            for item in viewModel.feedItems {
                if case .completedTurn(let id, let agentID, let final, let runtime) = item,
                   id == pinned {
                    let all = runtime + [final]
                    return (all, false, agentNameFor(agentID))
                }
            }
        }
        // Active stream wins next — user navigated from a live card.
        for item in viewModel.feedItems {
            if case .activeStream(_, let agentID, let runtime) = item,
               agentID == route.agentID {
                return (runtime, true, agentNameFor(agentID))
            }
        }
        // Fallback: the most recent completed turn for this agent (e.g.
        // the active stream finalized while the user was reading).
        for item in viewModel.feedItems.reversed() {
            if case .completedTurn(_, let agentID, let final, let runtime) = item,
               agentID == route.agentID {
                let all = runtime + [final]
                return (all, false, agentNameFor(agentID))
            }
        }
        return ([], false, agentNameFor(route.agentID))
    }

    private func agentNameFor(_ agentID: String) -> String {
        viewModel.memberSheetAgents.first(where: { $0.id == agentID })?.displayName
            ?? String(agentID.prefix(8))
    }

    /// Model display name for this turn — the model stamped on the
    /// latest event in the resolved snapshot that has one. Tool / status
    /// events are not model-attributable so we walk backward to find the
    /// most recent reply/thinking with a non-empty model id. nil if no
    /// event in the turn has a model (legacy rows, or the daemon hasn't
    /// stamped current_model yet).
    private func modelDisplayName(for events: [AgentEvent]) -> String? {
        guard let runtime = viewModel.runtime else { return nil }
        for event in events.reversed() {
            if let name = event.modelDisplayName(via: runtime) {
                return name
            }
        }
        return nil
    }

    public var body: some View {
        let snapshot = resolved
        let liveText = viewModel.streamingTextByAgent[route.agentID] ?? ""
        let stillStreaming = viewModel.streamingAgentSet.contains(route.agentID)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if snapshot.events.isEmpty && liveText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 36))
                                .foregroundStyle(.quaternary)
                            Text("Waiting for the agent…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }

                    ForEach(snapshot.events, id: \.id) { event in
                        EventBubbleView(
                            event: event,
                            runtime: viewModel.runtime,
                            onGrant: { id in Task { try? await viewModel.grantPermission(requestId: id) } },
                            onDeny: { id in Task { try? await viewModel.denyPermission(requestId: id) } },
                            // The nav-bar title already shows
                            // "{agent} · {model}" for the whole turn;
                            // suppressing the per-bubble caption keeps
                            // this view's left margin clean and avoids
                            // repeating identity on every assistant row.
                            showsAssistantHeader: false
                        )
                        .id(event.id)
                    }

                    if stillStreaming, !liveText.isEmpty {
                        StreamingTextView(content: liveText)
                            .id("detail-streaming")
                    }

                    if snapshot.isActive || stillStreaming {
                        TypingIndicatorView()
                            .id("detail-typing")
                    }

                    Color.clear.frame(height: 16).id("detail-bottom")
                }
                .padding(.top, 8)
            }
            // Anchor first layout at the bottom natively (iOS 17+) so a
            // turn with many tool-use / thinking rows doesn't animate a
            // scroll through the whole turn on appear. The previous
            // `.onAppear { proxy.scrollTo(...) }` traversed the LazyVStack
            // while rows were still realizing — looked frantic.
            .defaultScrollAnchor(.bottom)
            .onChange(of: snapshot.events.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("detail-bottom", anchor: .bottom) }
            }
            .onChange(of: liveText) {
                if stillStreaming {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("detail-bottom", anchor: .bottom) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Center-stack: agent name on the headline line, model
            // underneath as a caption. Replaces the old single-line
            // `.navigationTitle(agentName)` so the model is visible
            // for the whole detail view without re-printing per bubble.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(snapshot.agentName)
                        .font(.headline)
                        .lineLimit(1)
                    if let model = modelDisplayName(for: snapshot.events) {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if snapshot.isActive || stillStreaming {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        viewModel.interruptAgent(route.agentID)
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(Color.amux.cinnabarDeep)
                    }
                    .accessibilityLabel("Interrupt agent")
                }
            }
        }
    }
}
