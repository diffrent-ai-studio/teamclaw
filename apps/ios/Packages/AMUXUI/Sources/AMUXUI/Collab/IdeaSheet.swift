import SwiftUI
import SwiftData
import AMUXCore
import AMUXSharedUI

#if os(iOS)

public struct IdeaSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pairing: PairingManager
    let teamclawService: TeamclawService?

    public init(pairing: PairingManager, teamclawService: TeamclawService? = nil) {
        self.pairing = pairing
        self.teamclawService = teamclawService
    }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Ideas Live In The Ideas Tab",
                systemImage: IdeaUIPresentation.systemImage,
                description: Text("Use the dedicated Ideas tab for Supabase-backed idea management.")
            )
            .navigationTitle(IdeaUIPresentation.pluralTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Hai-styled "New Idea" sheet. Mirrors the prototype: Pebble surface,
/// icon-only liquid-glass toolbar actions, large editorial title field
/// with a description textarea stacked underneath in a single Paper card,
/// followed by a Workspace section card.
enum CreateIdeaSheetToolbarPresentation {
    static let cancelSystemImage = "xmark"
    static let submitSystemImage = "checkmark"
    static let cancelAccessibilityLabel = "Cancel"
    static let submitAccessibilityLabel = "Post"
}

struct CreateIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppOnboardingCoordinator.self) private var coordinator: AppOnboardingCoordinator?

    @Bindable var ideaStore: IdeaStore
    let onCreated: () -> Void

    @Query(sort: \Workspace.displayName) private var workspaces: [Workspace]

    @State private var title = ""
    @State private var description = ""
    @State private var workspaceID: String = ""
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    private var workspaceLabel: String {
        if workspaceID.isEmpty { return "None" }
        return workspaces.first(where: { $0.workspaceId == workspaceID })?.displayName ?? "—"
    }

    private var teamName: String {
        coordinator?.currentContext?.team.name ?? "this team"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    composerCard
                    workspaceSection
                    if let errorMessage = ideaStore.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.amux.cinnabarDeep)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                    }
                    footerCaption
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Color.amux.pebble)
            .navigationTitle("New Idea")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: CreateIdeaSheetToolbarPresentation.cancelSystemImage)
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(CreateIdeaSheetToolbarPresentation.cancelAccessibilityLabel)
                    .glassButtonStyle()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: CreateIdeaSheetToolbarPresentation.submitSystemImage)
                                .fontWeight(.semibold)
                        }
                    }
                    .accessibilityLabel(CreateIdeaSheetToolbarPresentation.submitAccessibilityLabel)
                    .disabled(!canSave)
                    .glassProminentButtonStyle()
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { titleFocused = true }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Idea title", text: $title, axis: .vertical)
                .focused($titleFocused)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.amux.onyx)
                .lineLimit(1...3)

            TextField(
                "Add context — what's the constraint, what's the win?",
                text: $description,
                axis: .vertical
            )
            .font(.system(size: 15))
            .foregroundStyle(Color.amux.basalt)
            .lineLimit(3...10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.amux.paper)
        )
        .padding(.horizontal, 16)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            IdeaSectionLabel("Workspace")
            VStack(spacing: 0) {
                Menu {
                    Button("None") { workspaceID = "" }
                    if !workspaces.isEmpty {
                        Divider()
                        ForEach(workspaces, id: \.workspaceId) { ws in
                            Button(ws.displayName) { workspaceID = ws.workspaceId }
                        }
                    }
                } label: {
                    IdeaSheetRowLabel(
                        label: "Repository",
                        value: workspaceLabel,
                        valueIsMonospaced: !workspaceID.isEmpty,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.amux.paper)
            )
            .padding(.horizontal, 16)
        }
    }

    private var footerCaption: some View {
        Text(.init(
            "Posted to **Team · \(teamName)**. Anyone can submit progress."
        ))
        .font(.system(size: 12))
        .foregroundStyle(Color.amux.basalt.opacity(0.75))
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard !isSaving, canSave else { return }
        isSaving = true
        Task {
            let ok = await ideaStore.createIdea(
                title: title,
                description: description,
                workspaceID: workspaceID
            )
            isSaving = false
            if ok {
                onCreated()
                dismiss()
            }
        }
    }
}

/// Tiny header label used between Hai sheet cards. Matches the design's
/// `SectionLabel` (uppercased Basalt).
private struct IdeaSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.amux.basalt.opacity(0.7))
            .padding(.horizontal, 24)
    }
}

/// Reusable Hai sheet row body — left label, right value, optional
/// chevron. Plain layout (no surrounding card) so callers can stack
/// multiple in one Paper card with hairline dividers.
private struct IdeaSheetRowLabel: View {
    let label: String
    let value: String?
    let valueIsMonospaced: Bool
    let showsChevron: Bool

    init(label: String,
         value: String? = nil,
         valueIsMonospaced: Bool = false,
         showsChevron: Bool = false) {
        self.label = label
        self.value = value
        self.valueIsMonospaced = valueIsMonospaced
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.amux.onyx)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 14, design: valueIsMonospaced ? .monospaced : .default))
                    .foregroundStyle(Color.amux.basalt)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.amux.slate)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

struct EditIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var ideaStore: IdeaStore
    let idea: IdeaRecord

    @State private var title: String
    @State private var description: String
    @State private var status: String
    @State private var isSaving = false

    init(ideaStore: IdeaStore, idea: IdeaRecord) {
        self.ideaStore = ideaStore
        self.idea = idea
        _title = State(initialValue: idea.title)
        _description = State(initialValue: idea.description)
        _status = State(initialValue: idea.status)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Idea title", text: $title, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Description") {
                    TextField("Optional context", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Open").tag("open")
                        Text("In Progress").tag("in_progress")
                        Text("Done").tag("done")
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage = ideaStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.amux.cinnabarDeep)
                    }
                }
            }
            .navigationTitle("Edit Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let ok = await ideaStore.updateIdea(
                ideaID: idea.id,
                title: title,
                description: description,
                status: status,
                workspaceID: idea.workspaceID
            )
            isSaving = false
            if ok {
                dismiss()
            }
        }
    }
}

struct IdeaRow: View {
    let item: IdeaRecord
    var creator: CachedActor?
    var workspaceName: String?

    init(item: IdeaRecord, creator: CachedActor? = nil, workspaceName: String? = nil) {
        self.item = item
        self.creator = creator
        self.workspaceName = workspaceName
    }

    init(item: SessionIdea, creator: CachedActor? = nil, workspaceName: String? = nil) {
        self.item = IdeaRecord(
            id: item.ideaId,
            teamID: "",
            workspaceID: item.workspaceId,
            createdByActorID: item.createdBy,
            title: item.title,
            description: item.ideaDescription,
            status: item.status,
            archived: item.archived,
            createdAt: item.createdAt,
            updatedAt: item.createdAt
        )
        self.creator = creator
        self.workspaceName = workspaceName
    }

    /// Hai keeps the status pill quiet: only `Done` earns Sage; the other
    /// two states sit in Basalt on Pebble (no orange / blue from earlier
    /// rounds — that would have violated "spare the vermillion").
    private var pillForeground: Color {
        if item.isDone       { return Color.amux.sage }
        return Color.amux.basalt
    }

    private var pillBackground: Color {
        if item.isDone       { return Color.amux.sage.opacity(0.12) }
        return Color.amux.pebble
    }

    private var creatorInitial: String {
        guard let name = creator?.displayName, let first = name.first else { return "·" }
        return String(first).uppercased()
    }

    /// Deterministic placeholder while a real submissions aggregate lands —
    /// stable per idea so the UI doesn't reshuffle between rebuilds. The
    /// distribution leans toward 0/1 so the chip stays sparse.
    private var mockSubmissionCount: Int {
        let buckets = [0, 0, 0, 1, 1, 2, 3, 4]
        let h = abs(item.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return buckets[h % buckets.count]
    }

    /// All creator avatars sit in Hai grays — the previous rainbow palette
    /// is gone. Cinnabar is reserved for the active session, not for
    /// decorating creator chips.
    private var creatorAvatarColor: Color {
        guard let id = creator?.actorId, !id.isEmpty else { return Color.amux.slate }
        let palette: [Color] = [Color.amux.basalt, Color.amux.slate]
        let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                statusPill
                if let name = workspaceName, !name.isEmpty {
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if mockSubmissionCount > 0 {
                    submissionCountChip
                }
            }

            Text(item.displayTitle)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .strikethrough(item.isDone, color: .secondary)
                .lineLimit(2)

            if !item.description.isEmpty, item.description != item.displayTitle {
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let creator, !creator.displayName.isEmpty {
                creatorFooter(creator)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            statusGlyph
            Text(item.statusLabel.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(pillForeground)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(pillBackground))
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if item.isDone {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
        } else if item.isInProgress {
            ZStack {
                Circle()
                    .stroke(pillForeground.opacity(0.35), lineWidth: 1.4)
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(pillForeground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 8, height: 8)
        } else {
            Circle()
                .strokeBorder(pillForeground, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
    }

    private var submissionCountChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "tray.full")
                .font(.system(size: 10, weight: .medium))
            Text("\(mockSubmissionCount)")
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private func creatorFooter(_ creator: CachedActor) -> some View {
        HStack(spacing: 6) {
            Text("Created by")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                Circle().fill(creatorAvatarColor)
                Text(creatorInitial)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
            Text(creator.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }
}
#else
public struct IdeaSheet: View {
    public init(pairing: PairingManager, teamclawService: TeamclawService? = nil) {}

    public var body: some View {
        ContentUnavailableView("Ideas", systemImage: IdeaUIPresentation.systemImage)
    }
}

struct CreateIdeaSheet: View {
    @Bindable var ideaStore: IdeaStore
    let onCreated: () -> Void

    var body: some View {
        ContentUnavailableView("New Idea", systemImage: "plus")
    }
}

struct EditIdeaSheet: View {
    @Bindable var ideaStore: IdeaStore
    let idea: IdeaRecord

    var body: some View {
        ContentUnavailableView("Edit Idea", systemImage: "pencil")
    }
}

struct IdeaRow: View {
    let item: IdeaRecord
    var creatorName: String? = nil

    var body: some View {
        Text(item.displayTitle)
    }
}
#endif
