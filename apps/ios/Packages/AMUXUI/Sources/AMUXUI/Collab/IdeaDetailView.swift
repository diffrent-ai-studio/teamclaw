import SwiftUI
import SwiftData
import AMUXCore
import AMUXSharedUI

public struct IdeaDetailView: View {
    let ideaID: String
    @Bindable var ideaStore: IdeaStore
    let sessionViewModel: SessionListViewModel
    let teamclawService: TeamclawService?
    let mqtt: MQTTService
    let hub: MQTTMessageHub
    let peerId: String
    @Binding var navigationPath: [String]

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedActor.displayName) private var allActors: [CachedActor]
    @Query(sort: \Session.lastMessageAt, order: .reverse)
    private var allSessions: [Session]
    @Query(sort: \Workspace.displayName) private var workspaces: [Workspace]

    @State private var localTitle: String = ""
    @State private var localDescription: String = ""
    @State private var showNewSession = false
    @State private var showArchiveConfirm = false
    @State private var isArchiving = false
    @State private var didSeedLocals = false
    @State private var composerText: String = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var descriptionFocused: Bool

    public init(
        ideaID: String,
        ideaStore: IdeaStore,
        sessionViewModel: SessionListViewModel,
        teamclawService: TeamclawService?,
        mqtt: MQTTService,
        hub: MQTTMessageHub,
        peerId: String,
        navigationPath: Binding<[String]>
    ) {
        self.ideaID = ideaID
        self.ideaStore = ideaStore
        self.sessionViewModel = sessionViewModel
        self.teamclawService = teamclawService
        self.mqtt = mqtt
        self.hub = hub
        self.peerId = peerId
        self._navigationPath = navigationPath
    }

    private var item: IdeaRecord? { ideaStore.idea(id: ideaID) }

    private var creator: CachedActor? {
        guard let item, !item.createdByActorID.isEmpty else { return nil }
        return allActors.first { $0.actorId == item.createdByActorID }
    }

    private var workspaceName: String? {
        guard let item, !item.workspaceID.isEmpty else { return nil }
        return workspaces.first { $0.workspaceId == item.workspaceID }?.displayName
    }

    private var relatedSessions: [Session] {
        allSessions.filter { $0.ideaId == ideaID }
    }

    /// Deterministic mock agent picked from the team's agents — used to
    /// populate the "Claimed by" card for `in_progress` ideas while a real
    /// claim aggregate doesn't exist yet.
    private var mockClaimedAgent: CachedActor? {
        let agents = allActors.filter(\.isAgent)
        guard !agents.isEmpty else { return nil }
        let hash = abs(ideaID.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return agents[hash % agents.count]
    }

    /// Deterministic placeholder submissions until a real submissions feed
    /// lands. Stable per idea so the list doesn't reshuffle.
    fileprivate struct MockSubmission: Identifiable {
        let id: Int
        let actor: CachedActor
        let when: Date
        let content: String
        let attachment: String?
    }

    fileprivate var mockSubmissions: [MockSubmission] {
        guard let item else { return [] }
        let pool = allActors
        guard !pool.isEmpty else { return [] }
        let h = abs(item.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let count = item.isOpen ? 0 : (item.isDone ? 4 : (h % 3 + 1))
        if count == 0 { return [] }

        let templates: [(String, String?)] = [
            ("Drafted the initial implementation. Opened a PR for review — feedback welcome.",
             "PR #214 · daemon/src/cron/sweep.rs"),
            ("Reviewed the proposal. The unsubscribe path needs to flush retained state before the broker drops the connection.",
             nil),
            ("Initial proposal: 24h idle threshold, 6h sweep cadence, configurable via daemon.toml. Will add a regression test.",
             nil),
            ("Sketched a quick prototype to validate the approach. Looks promising on the happy path.",
             nil),
        ]
        var out: [MockSubmission] = []
        for i in 0..<count {
            let actor = pool[(h &+ i) % pool.count]
            let template = templates[i % templates.count]
            let when = item.updatedAt.addingTimeInterval(-Double(i) * 3600)
            out.append(MockSubmission(
                id: i, actor: actor, when: when,
                content: template.0, attachment: template.1
            ))
        }
        return out
    }

    public var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                ContentUnavailableView("Idea Not Found", systemImage: IdeaUIPresentation.systemImage)
            }
        }
        .onAppear { seedLocals() }
        .onChange(of: ideaID) { _, _ in didSeedLocals = false; seedLocals() }
    }

    @ViewBuilder
    private func content(for item: IdeaRecord) -> some View {
        List {
            heroSection(item)
            if item.isInProgress, let agent = mockClaimedAgent {
                claimCardSection(agent: agent)
            }
            submissionsSection(item)
            sessionsSection(item)
            archiveSection(item)
            if let err = ideaStore.errorMessage {
                Section {
                    Text(err).font(.footnote).foregroundStyle(Color.amux.cinnabarDeep)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.amux.mist)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerCapsule
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle(IdeaUIPresentation.singularTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Tab-bar visibility hoisted to IdeasTab's NavigationStack root.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    titleFocused = false
                    descriptionFocused = false
                    showNewSession = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a session")
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet(
                mqtt: mqtt,
                peerId: peerId,
                teamclawService: teamclawService,
                viewModel: sessionViewModel,
                preselectedIdeaId: item.id,
                onSessionCreated: { sessionKey in
                    showNewSession = false
                    navigationPath.append(sessionKey)
                }
            )
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func heroSection(_ item: IdeaRecord) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                statusPillMenu(for: item)

                TextField("Title", text: $localTitle, axis: .vertical)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1...3)
                    .focused($titleFocused)
                    .onSubmit { commitTitle(for: item) }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle(for: item) }
                    }

                TextField("Add details…", text: $localDescription, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2...10)
                    .focused($descriptionFocused)
                    .onChange(of: descriptionFocused) { _, focused in
                        if !focused { commitDescription(for: item) }
                    }

                heroMetaStrip(item)
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
    }

    private func statusPillMenu(for item: IdeaRecord) -> some View {
        // Hai keeps the pill quiet: only `Done` earns Sage; the other states
        // sit in Basalt on Pebble. Cinnabar is reserved for active sessions.
        let fg: Color = item.isDone ? Color.amux.sage : Color.amux.basalt
        let bg: Color = item.isDone ? Color.amux.sage.opacity(0.12) : Color.amux.pebble
        return Menu {
            Picker("Status", selection: statusBinding(for: item)) {
                Text("Open").tag("open")
                Text("In Progress").tag("in_progress")
                Text("Done").tag("done")
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(fg)
                    .frame(width: 6, height: 6)
                    .modifier(BreathingDot(active: item.isInProgress))
                Text(item.statusLabel.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.3)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(bg))
        }
    }

    private func statusBinding(for item: IdeaRecord) -> Binding<String> {
        Binding(
            get: { item.status },
            set: { newValue in
                guard newValue != item.status else { return }
                Task {
                    await ideaStore.updateIdea(
                        ideaID: item.id,
                        title: item.title,
                        description: item.description,
                        status: newValue,
                        workspaceID: item.workspaceID
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func heroMetaStrip(_ item: IdeaRecord) -> some View {
        HStack(spacing: 6) {
            if let name = workspaceName, !name.isEmpty {
                Text(name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.systemFill)))
            }
            if let creator {
                Text("Created by \(creator.displayName) · \(item.createdAt.relativeShort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.systemFill)))
            } else {
                Text(item.createdAt.relativeShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    // MARK: Claim card

    @ViewBuilder
    private func claimCardSection(agent: CachedActor) -> some View {
        Section {
            HStack(spacing: 12) {
                AgentAvatar(actor: agent, size: 36, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(agentSubtitle(agent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showNewSession = true
                } label: {
                    Text("Open session")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.amux.cinnabar.opacity(0.10))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.amux.cinnabar)
                }
                .buttonStyle(.plain)
            }
        } header: {
            sectionHeader("Claimed by")
        }
    }

    private func agentSubtitle(_ a: CachedActor) -> String {
        let kind = a.agentKind?.capitalized ?? "Agent"
        if let s = a.agentStatus, !s.isEmpty {
            return "\(kind) · \(s)"
        }
        return kind
    }

    // MARK: Submissions

    @ViewBuilder
    private func submissionsSection(_ item: IdeaRecord) -> some View {
        let subs = mockSubmissions
        if subs.isEmpty {
            EmptyView()
        } else {
            Section {
                ForEach(subs) { s in
                    SubmissionRow(submission: s)
                }
            } header: {
                sectionHeader("Submissions · \(subs.count)")
            }
        }
    }

    // MARK: Sessions

    @ViewBuilder
    private func sessionsSection(_ item: IdeaRecord) -> some View {
        Section {
            if relatedSessions.isEmpty {
                Text("No sessions linked yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relatedSessions, id: \.sessionId) { session in
                    Button {
                        navigationPath.append("session:\(session.sessionId)")
                    } label: {
                        SessionLinkRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader("Sessions")
        }
    }

    // MARK: Archive

    @ViewBuilder
    private func archiveSection(_ item: IdeaRecord) -> some View {
        Section {
            Button(role: .destructive) {
                showArchiveConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if isArchiving {
                        ProgressView()
                    } else {
                        Text(item.archived ? "Unarchive" : "Archive")
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
            }
            .disabled(isArchiving)
            // Attach dialog to the button so iOS 26's popover-style
            // confirmation anchors at the tapped row, not at the top of
            // the screen where the body-level modifier was placed.
            .confirmationDialog(
                item.archived ? "Unarchive this idea?" : "Archive this idea?",
                isPresented: $showArchiveConfirm,
                titleVisibility: .visible
            ) {
                Button(item.archived ? "Unarchive" : "Archive",
                       role: item.archived ? .none : .destructive) {
                    performArchive(for: item)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(item.archived
                     ? "The idea will reappear in the main list."
                     : "Archived ideas are hidden from the main list but can be restored later.")
            }
        }
    }

    // MARK: Composer

    private var composerCapsule: some View {
        HStack(spacing: 8) {
            TextField("Submit progress, or @mention an agent…", text: $composerText, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)
                .padding(.leading, 14)
            Button {
                composerText = ""  // wire to a real submissions endpoint when available
            } label: {
                Text("Submit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.amux.mist)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.amux.onyx, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(Color.amux.hairline, lineWidth: 0.5)
        )
        .shadow(color: Color.amux.onyx.opacity(0.08), radius: 18, y: 6)
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(0.3)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func seedLocals() {
        guard !didSeedLocals, let item else { return }
        localTitle = item.title
        localDescription = item.description
        didSeedLocals = true
    }

    private func commitTitle(for item: IdeaRecord) {
        let trimmed = localTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else {
            if trimmed.isEmpty { localTitle = item.title }
            return
        }
        Task {
            await ideaStore.updateIdea(
                ideaID: item.id,
                title: trimmed,
                description: item.description,
                status: item.status,
                workspaceID: item.workspaceID
            )
        }
    }

    private func commitDescription(for item: IdeaRecord) {
        guard localDescription != item.description else { return }
        Task {
            await ideaStore.updateIdea(
                ideaID: item.id,
                title: item.title,
                description: localDescription,
                status: item.status,
                workspaceID: item.workspaceID
            )
        }
    }

    private func performArchive(for item: IdeaRecord) {
        guard !isArchiving else { return }
        isArchiving = true
        Task {
            let ok = await ideaStore.setArchived(ideaID: item.id, archived: !item.archived)
            await MainActor.run {
                isArchiving = false
                if ok, !item.archived {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Submission row

private struct SubmissionRow: View {
    let submission: IdeaDetailView.MockSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentAvatar(actor: submission.actor, size: 22, cornerRadius: 6)
                Text(submission.actor.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                if submission.actor.isAgent {
                    Text("AGENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(Color.amux.basalt)
                        .padding(.horizontal, 5)
                        .frame(height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.amux.pebble)
                        )
                }
                Spacer()
                Text(submission.when.relativeShort)
                    .font(.caption2)
                    .foregroundStyle(Color.amux.slate)
            }

            Text(submission.content)
                .font(.subheadline)
                .foregroundStyle(Color.amux.onyx.opacity(0.85))
                .lineLimit(nil)

            if let attach = submission.attachment {
                // Attachment chip uses Cinnabar so PRs/links read as the
                // single semantic accent of the design — Hai's "spare the
                // vermillion" allows it here because attachments are an
                // intentional, infrequent affordance.
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .medium))
                    Text(attach)
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(Color.amux.cinnabar)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.amux.cinnabar.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.amux.cinnabar.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session link row

private struct SessionLinkRow: View {
    let session: Session

    private var lastMessage: String {
        session.lastMessagePreview.isEmpty ? "No messages yet." : session.lastMessagePreview
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.primaryAgentId == nil ? "person.2.fill" : "cpu")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let at = session.lastMessageAt ?? Optional(session.createdAt) {
                Text(at, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Shared helpers used across detail surfaces

/// Avatar tile reused across detail surfaces. Mirrors the palette logic in
/// the Actors list so an actor reads as the "same" person across views.
struct AgentAvatar: View {
    let actor: CachedActor
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 10

    private var initials: String {
        let parts = actor.displayName
            .split(whereSeparator: { $0.isWhitespace || $0 == "·" })
            .prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return s.isEmpty ? String(actor.displayName.prefix(1)).uppercased() : s
    }

    private struct Style { let bg: Color; let fg: Color }

    private var style: Style {
        // Hai palette — every avatar background is Pebble. Foregrounds are
        // chosen from the ink-and-stone family: Cinnabar is rationed for a
        // single hash slot (one variant per actor stays warm, all others
        // sit in Basalt or Slate). The previous brand rainbow has been
        // retired per the "spare the vermillion" principle.
        let palette: [Color] = [
            Color.amux.basalt,
            Color.amux.slate,
            Color.amux.cinnabar,
            Color.amux.basalt,
        ]
        let h = abs(actor.actorId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return Style(bg: Color.amux.pebble, fg: palette[h % palette.count])
    }

    var body: some View {
        ZStack {
            if actor.isAgent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(style.bg)
            } else {
                Circle().fill(style.bg)
            }
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(style.fg)
        }
        .frame(width: size, height: size)
    }
}

/// Reusable breathing-opacity modifier so status dots and online rings stay
/// visually consistent across detail and list surfaces.
struct BreathingDot: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 0.4 : 1) : 1)
            .animation(active
                ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                : .default,
                value: on)
            .onAppear { if active { on = true } }
    }
}

private extension Date {
    /// Short relative date string ("2h", "3d", "now") — matches the listed
    /// Sessions row format so detail surfaces feel consistent.
    var relativeShort: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: .now)
    }
}
