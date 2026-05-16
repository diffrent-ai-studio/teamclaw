import SwiftUI
import SwiftData
import AMUXCore
import AMUXSharedUI

// MARK: - EventBubbleView

public struct EventBubbleView: View {
    let event: AgentEvent
    let runtime: Runtime?
    let onGrant: ((String) -> Void)?
    let onDeny: ((String) -> Void)?
    /// Tap handler invoked when the user taps a `.failed` outbox dot on
    /// their own bubble. Hooked to `OutboxSender.retry` by the parent.
    let onRetryOutbox: ((String) -> Void)?
    /// When false the assistant bubble suppresses its "{Agent} · {Model}"
    /// caption. Used by `StreamingDetailView`, where the same identity is
    /// already painted into the nav-bar title for the whole turn so the
    /// per-bubble caption would just be redundant.
    let showsAssistantHeader: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Resolves AgentEvent.senderActorID into a display name. Local user
    /// renders as "You"; everyone else gets the matching CachedActor row's
    /// displayName, falling back to the truncated actor id when the
    /// directory hasn't synced yet.
    @Query(sort: \CachedActor.displayName) private var cachedActors: [CachedActor]

    public init(event: AgentEvent, runtime: Runtime? = nil,
                onGrant: ((String) -> Void)? = nil,
                onDeny: ((String) -> Void)? = nil,
                onRetryOutbox: ((String) -> Void)? = nil,
                showsAssistantHeader: Bool = true) {
        self.event = event
        self.runtime = runtime
        self.onGrant = onGrant
        self.onDeny = onDeny
        self.onRetryOutbox = onRetryOutbox
        self.showsAssistantHeader = showsAssistantHeader
    }

    /// True when this event was produced by an actor other than the
    /// signed-in user. Drives the "You / @other" label and bubble alignment
    /// for user-prompt rows.
    private var isFromOtherUser: Bool {
        guard let senderID = event.senderActorID, !senderID.isEmpty else { return false }
        return senderID != currentActorID
    }

    private var currentActorID: String? {
        // The detail surface lives inside RootTabView's scope, which
        // installs the AppOnboardingCoordinator into the environment.
        // We pull the active actor id directly from there so the bubble
        // identity question — "did I send this?" — has a single source
        // of truth that matches the rest of the app.
        coordinator?.currentContext?.memberActorID
    }

    @Environment(AppOnboardingCoordinator.self) private var coordinator: AppOnboardingCoordinator?

    private var senderDisplayName: String {
        guard let senderID = event.senderActorID, !senderID.isEmpty else { return "You" }
        if senderID == currentActorID { return "You" }
        if let actor = cachedActors.first(where: { $0.actorId == senderID }) {
            return actor.displayName
        }
        return String(senderID.prefix(8))
    }

    /// Display name for the model that produced this event (assistant reply
    /// types only). Returns nil for non-stamped events or when no runtime is
    /// available to resolve the display name.
    private var modelDisplayName: String? {
        guard let runtime else { return nil }
        return event.modelDisplayName(via: runtime)
    }

    /// Header label shown above an assistant bubble: "{Agent name} · {Model}"
    /// when both are resolvable, the agent name alone when the model isn't
    /// stamped, the model alone when the agent identity can't be resolved
    /// (e.g. event was stamped with a runtime_id before the runtime→actor
    /// mapping was available), nil when neither resolves. Caption-style at
    /// the call site.
    private var assistantHeaderLabel: String? {
        let agent = senderDisplayName.isEmpty ? nil : senderDisplayName
        let model = modelDisplayName
        switch (agent, model) {
        case let (.some(a), .some(m)): return "\(a) · \(m)"
        case let (.some(a), .none): return a
        case let (.none, .some(m)): return m
        case (.none, .none): return nil
        }
    }

    public var body: some View {
        switch event.eventType {
        case "user_prompt":
            userBubble
        case "output":
            assistantBubble
        case "thinking":
            thinkingBlock
        case "tool_use":
            toolUseBlock
        case "tool_result":
            EmptyView()
        case "error":
            errorBlock
        case "permission_request":
            PermissionBannerView(
                toolName: event.toolName ?? "",
                description: event.text ?? "",
                requestId: event.toolId ?? "",
                isResolved: event.isComplete == true,
                wasGranted: event.success,
                onGrant: event.isComplete == true ? nil : onGrant,
                onDeny: event.isComplete == true ? nil : onDeny
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        case "todo_update":
            TodoListView(text: event.text ?? "")
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        default:
            EmptyView()
        }
    }

    // MARK: - User Bubble
    //
    // Local user → right-aligned, Cinnabar-tinted glass with "You" label.
    // Another collaborator → left-aligned plain glass with their display
    // name. Mirrors the iMessage convention where outgoing and incoming
    // bubbles read at opposite edges of the canvas.

    private var userBubble: some View {
        if isFromOtherUser {
            return AnyView(otherUserBubble)
        } else {
            return AnyView(selfUserBubble)
        }
    }

    private var selfUserBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("You")
                .font(.caption)
                .foregroundStyle(Color.amux.basalt)
                .padding(.trailing, 4)

            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 0)
                // Wrap dot + bubble in an inner HStack that hugs its
                // intrinsic width, so the dot stays adjacent to the
                // bubble's left edge regardless of the bubble's
                // (variable) frame width.
                HStack(alignment: .bottom, spacing: 6) {
                    if let outboxID = event.outboxMessageID {
                        OutboxStatusDot(outboxMessageID: outboxID, onRetry: onRetryOutbox)
                    }
                    Text(event.text ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Color.amux.mist)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 18),
                                     tint: Color.amux.cinnabar,
                                     interactive: false)
                        .contextMenu {
                            MessageContextMenu(text: event.text ?? "")
                        }
                }
                .frame(maxWidth: sizeClass == .regular ? 500 : 260, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var otherUserBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(senderDisplayName)
                .font(.caption)
                .foregroundStyle(Color.amux.basalt)
                .padding(.leading, 4)

            HStack {
                Text(event.text ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Color.amux.onyx)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 18), interactive: false)
                    .frame(maxWidth: sizeClass == .regular ? 500 : 260, alignment: .leading)
                    .contextMenu {
                        MessageContextMenu(text: event.text ?? "")
                    }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Assistant Bubble (gray, left-aligned, markdown)

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsAssistantHeader, let header = assistantHeaderLabel {
                Text(header)
                    .font(.caption)
                    .foregroundStyle(Color.amux.basalt)
                    .padding(.leading, 4)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownRenderer(content: event.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18), interactive: false)
                .contextMenu {
                    MessageContextMenu(text: event.text ?? "")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Thinking Block

    private var thinkingBlock: some View {
        ThinkingBlockView(text: event.text ?? "")
            .contextMenu {
                MessageContextMenu(text: event.text ?? "")
            }
    }

    // MARK: - Tool Use

    private var toolUseBlock: some View {
        Group {
            if event.isComplete == true {
                CompactToolLine(event: event)
            } else {
                ToolCallView(
                    toolName: event.toolName ?? "Unknown",
                    toolId: event.toolId ?? "",
                    description: event.text ?? "",
                    status: "running"
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .contextMenu {
            MessageContextMenu(text: event.text ?? "")
        }
    }

    // MARK: - Error

    private var errorBlock: some View {
        ErrorBlockView(message: event.text ?? "Unknown error")
    }
}

// MARK: - ActiveStreamCardView
//
// Compact full-width card rendered for an agent whose runtime is still
// producing output. Replaces the live thinking/tool/output stream that
// used to clutter the main feed when multiple agents work in parallel.
// Tap routes to `StreamingDetailView` for the full event timeline.

public struct ActiveStreamCardView: View {
    public let agentName: String
    /// Latest single-line text drawn from (in priority): live streaming
    /// text buffer, the most recent runtime event's text, or "Working…"
    /// when nothing readable has arrived yet.
    public let lastLine: String

    @State private var pulse = false

    public init(agentName: String, lastLine: String) {
        self.agentName = agentName
        self.lastLine = lastLine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(agentName)
                .font(.caption)
                .foregroundStyle(Color.amux.basalt)
                .padding(.leading, 4)

            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.amux.cinnabar)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(pulse ? 0.55 : 1.0)

                Text(lastLine.isEmpty ? "Working…" : lastLine)
                    .font(.subheadline)
                    .foregroundStyle(Color.amux.onyx)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18), interactive: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }
}

// MARK: - CompletedTurnBubbleView
//
// Final assistant bubble for a completed turn. Same look as
// `EventBubbleView.assistantBubble` (gray glass, markdown, model caption)
// but with an extra detail-icon overlay top-right that pushes the
// streaming detail when the turn produced any thinking / tool runs the
// user might want to inspect.

public struct CompletedTurnBubbleView<DetailIcon: View>: View {
    public let finalEvent: AgentEvent
    public let runtime: Runtime?
    public let agentName: String?
    /// Optional content slot rendered top-right of the bubble. Used to
    /// host a `NavigationLink(value:)` so taps push the streaming detail
    /// — kept generic here so this view doesn't depend on the navigation
    /// route type defined in `StreamingDetailView.swift`.
    @ViewBuilder public let detailIcon: () -> DetailIcon

    public init(finalEvent: AgentEvent,
                runtime: Runtime?,
                agentName: String?,
                @ViewBuilder detailIcon: @escaping () -> DetailIcon = { EmptyView() }) {
        self.finalEvent = finalEvent
        self.runtime = runtime
        self.agentName = agentName
        self.detailIcon = detailIcon
    }

    private var modelDisplayName: String? {
        guard let runtime else { return nil }
        return finalEvent.modelDisplayName(via: runtime)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let agentName, !agentName.isEmpty {
                Text(agentName)
                    .font(.caption)
                    .foregroundStyle(Color.amux.basalt)
                    .padding(.leading, 4)
            }

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownRenderer(content: finalEvent.text ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18), interactive: false)
                .contextMenu {
                    MessageContextMenu(text: finalEvent.text ?? "")
                }

                detailIcon()
            }

            if let modelName = modelDisplayName {
                Text(modelName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - ThinkingBlockView

struct ThinkingBlockView: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .font(.caption2)
                    }
                    .frame(width: 14)
                    Image(systemName: "brain")
                        .font(.caption)
                        .frame(width: 16)
                    Text("Thinking")
                        .font(.caption)
                        .fontWeight(.medium)
                    if !isExpanded {
                        Text(text.prefix(60) + (text.count > 60 ? "…" : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 10), interactive: false)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - ErrorBlockView

struct ErrorBlockView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.amux.cinnabarDeep)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.amux.cinnabarDeep)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12),
                     tint: Color.amux.cinnabarDeep,
                     interactive: false)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contextMenu {
            MessageContextMenu(text: message)
        }
    }
}

// MARK: - TypingIndicatorView

struct TypingIndicatorView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.amux.slate)
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotScale(for: i))
                    .opacity(dotOpacity(for: i))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18), interactive: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotScale(for index: Int) -> Double {
        let offset = Double(index) * 0.15
        let value = sin((phase + offset) * .pi)
        return 0.6 + 0.4 * value
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.15
        let value = sin((phase + offset) * .pi)
        return 0.4 + 0.6 * value
    }
}

// MARK: - OutboxStatusDot

/// Tiny accessory rendered to the right of a self-authored user_prompt
/// bubble showing the OutboxMessage row's lifecycle state. Reads via a
/// targeted `@Query` filtered by `messageID` so updates to a single row
/// do not invalidate the whole bubble list. Tap on `.failed` calls back
/// into the parent's `OutboxSender.retry` handler.
struct OutboxStatusDot: View {
    let outboxMessageID: String
    let onRetry: ((String) -> Void)?

    @Query private var rows: [OutboxMessage]

    init(outboxMessageID: String, onRetry: ((String) -> Void)?) {
        self.outboxMessageID = outboxMessageID
        self.onRetry = onRetry
        let id = outboxMessageID
        _rows = Query(filter: #Predicate<OutboxMessage> { $0.messageID == id })
    }

    private var state: OutboxState? { rows.first?.state }

    var body: some View {
        Group {
            switch state {
            case .pending, .inFlight:
                Image(systemName: "circle.dashed")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.amux.basalt)
                    .accessibilityLabel("Sending")
            case .delivered:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.amux.basalt.opacity(0.5))
                    .accessibilityLabel("Delivered")
            case .failed:
                Button {
                    onRetry?(outboxMessageID)
                } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.amux.cinnabarDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sending message")
            case nil:
                EmptyView()
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - MessageContextMenu

struct MessageContextMenu: View {
    let text: String

    var body: some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if let url = URL(string: text), UIApplication.shared.canOpenURL(url) {
            Button {
                UIApplication.shared.open(url)
            } label: {
                Label("Open Link", systemImage: "safari")
            }
        }

        ShareLink(item: text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}
