import SwiftUI
import AMUXCore
import AMUXSharedUI

struct SessionComposer: View {
    @Binding var promptText: String
    @Binding var selectedModelId: String?
    @Binding var attachments: [URL]

    let voiceRecorder: VoiceRecorder
    let runtime: Runtime?
    let availableCommands: [SlashCommand]
    let availableMentions: [MentionTarget]
    /// Resolved session id (from `SessionDetailViewModel.session?.sessionId`)
    /// or empty when the composer is hosted by the legacy runtime-only path.
    /// Empty disables uploads — the picker still lets the user attach files
    /// locally, but no Supabase Storage upload is triggered.
    let sessionID: String
    let teamID: String

    let onSend: () -> Void
    let onAgentMention: (MentionTarget) -> Void

    @State private var showDrawer = false
    @State private var slashCandidates: [SlashCommand] = []
    @State private var hasPendingSlashCommand = false
    @State private var mentionCandidates: [MentionTarget] = []
    @State private var uploadingAttachments: [String: AttachmentUpload] = [:]
    /// Lazily created on first sheet present; nil before the modelContext is
    /// available or when the SupabaseProjectConfiguration lookup fails (in
    /// which case the drawer falls back to no-op upload behavior).
    @State private var uploadManager: AttachmentUploadManager?
    @FocusState private var inputFocused: Bool
    @Environment(\.modelContext) private var modelContext

    private var hasText: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rightButton: ComposerRightButton {
        ComposerState.rightButton(
            hasText: hasText,
            voiceState: voiceRecorder.state
        )
    }

    private var inputMode: ComposerInputMode {
        ComposerState.inputMode(voiceState: voiceRecorder.state)
    }

    private var slashPrefix: String? {
        guard let first = promptText.first, first == "/" else { return nil }
        let rest = promptText.dropFirst()
        guard rest.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return String(rest)
    }

    private var matchesKnownCommand: Bool {
        guard promptText.hasPrefix("/") else { return false }
        let after = promptText.dropFirst()
        let head = after.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? String(after)
        guard !head.isEmpty else { return false }
        return availableCommands.contains(where: { $0.name == head })
    }

    /// Active `@<query>` token at the end of `promptText`, if any. Returns
    /// the substring after the trailing `@` (possibly empty), or nil if no
    /// in-progress mention is being typed. Anchored to end-of-string so the
    /// popup auto-closes once the user types whitespace or moves on.
    private var mentionQuery: String? {
        guard !promptText.isEmpty else { return nil }
        // Walk back from the end collecting word-token characters until we
        // hit either an `@` (mention starts) or anything else (no mention).
        var query = ""
        for ch in promptText.reversed() {
            if ch == "@" {
                let beforeIndex = promptText.index(promptText.endIndex, offsetBy: -(query.count + 1))
                if beforeIndex == promptText.startIndex { return query }
                let prev = promptText[promptText.index(before: beforeIndex)]
                if prev.isWhitespace || prev.isPunctuation || prev.isNewline { return query }
                return nil
            }
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." {
                query.insert(ch, at: query.startIndex)
                continue
            }
            return nil
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 6) {
            if !slashCandidates.isEmpty {
                SlashCommandsPopup(
                    candidates: slashCandidates,
                    onTap: { cmd in
                        promptText = "/\(cmd.name) "
                        slashCandidates = []
                        hasPendingSlashCommand = true
                    }
                )
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.15), value: slashCandidates)
            }
            if !mentionCandidates.isEmpty {
                MentionsPopup(
                    candidates: mentionCandidates,
                    onTap: { target in pickMention(target) }
                )
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.15), value: mentionCandidates)
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments, id: \.self) { url in
                            if let upload = uploadingAttachments[url.absoluteString] {
                                // Show upload progress
                                VStack(spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc")
                                            .font(.caption)
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        if upload.uploadState == .failed {
                                            Button {
                                                // Retry will be handled by AttachmentUploadManager.retryUpload
                                                // For now, show retry UI via context menu
                                            } label: {
                                                Image(systemName: "exclamationmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                            }
                                        } else {
                                            Button {
                                                attachments.removeAll { $0 == url }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    // Progress bar
                                    if upload.uploadState == .uploading {
                                        ProgressView(value: upload.progress)
                                            .frame(height: 3)
                                            .padding(.horizontal, 10)
                                    }
                                }
                                .liquidGlass(in: Capsule(), interactive: false)
                            } else {
                                // Fallback (attachment not yet tracked)
                                HStack(spacing: 4) {
                                    Image(systemName: "doc")
                                        .font(.caption)
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Button {
                                        attachments.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .liquidGlass(in: Capsule(), interactive: false)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if !uploadingAttachments.isEmpty {
                    Text("Files uploading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                }
            }

            HStack(spacing: 10) {
                Button { showDrawer = true } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .liquidGlass(in: Circle())
                .accessibilityIdentifier("composer.plusButton")

                pill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onChange(of: promptText) { _, _ in
            recomputeSlashCandidates()
            recomputeMentionCandidates()
        }
        .onChange(of: availableCommands) { _, _ in recomputeSlashCandidates() }
        .onChange(of: availableMentions) { _, _ in recomputeMentionCandidates() }
        .onChange(of: voiceRecorder.state) { _, newState in
            if newState == .done {
                let text = voiceRecorder.transcribedText ?? ""
                if !text.isEmpty {
                    promptText = text
                }
                voiceRecorder.reset()
            }
        }
        .sheet(isPresented: $showDrawer) {
            AttachmentDrawerSheet(
                attachments: $attachments,
                selectedModelId: $selectedModelId,
                runtime: runtime,
                uploadManager: ensureUploadManager(),
                sessionID: sessionID,
                teamID: teamID,
                onUploadStarted: { key, upload in
                    uploadingAttachments[key] = upload
                }
            )
            .presentationDetents([.fraction(0.4), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var pill: some View {
        HStack(spacing: 6) {
            Group {
                switch inputMode {
                case .textField:
                    TextField("Send a message…", text: $promptText, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .submitLabel(.return)
                        .accessibilityIdentifier("composer.textField")
                case .waveform:
                    RecordingWaveform(level: voiceRecorder.audioLevel)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 14)
            .padding(.vertical, 8)

            rightButtonView
                .padding(.trailing, 6)
        }
        .liquidGlass(in: Capsule())
    }

    @ViewBuilder
    private var rightButtonView: some View {
        switch rightButton {
        case .stopRecording:
            Button {
                voiceRecorder.stopRecording()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.amux.cinnabarDeep)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composer.stopRecordingButton")

        case .send:
            let hasFailedAttachments = uploadingAttachments.values.contains { $0.uploadState == .failed }
            let hasUploadingAttachments = uploadingAttachments.values.contains { $0.uploadState == .uploading }

            Button {
                if !hasUploadingAttachments {
                    onSend()
                    hasPendingSlashCommand = false
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        hasUploadingAttachments || hasFailedAttachments
                            ? Color.amux.mist
                            : Color.amux.onyx
                    )
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(hasUploadingAttachments)
            .modifier(SendButtonGlassModifier(
                emphasized: hasPendingSlashCommand && !hasUploadingAttachments
            ))
            .accessibilityIdentifier("composer.sendButton")

        case .mic:
            Button {
                voiceRecorder.startRecording()
            } label: {
                Image(systemName: "mic")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("composer.micButton")
        }
    }

    /// Returns a cached AttachmentUploadManager, building one on first call
    /// from `Bundle.main`'s Supabase config. Returns nil when sessionID is
    /// empty (legacy runtime-only flow has no session to upload against) or
    /// when the Supabase config can't be resolved — drawer falls back to
    /// no-op upload behavior in either case.
    private func ensureUploadManager() -> AttachmentUploadManager? {
        guard !sessionID.isEmpty else { return nil }
        if let existing = uploadManager { return existing }
        guard let mgr = try? AttachmentUploadManager.fromMainBundle(modelContext: modelContext) else {
            return nil
        }
        uploadManager = mgr
        return mgr
    }

    private func recomputeSlashCandidates() {
        if let prefix = slashPrefix {
            let lower = prefix.lowercased()
            slashCandidates = Array(
                availableCommands
                    .filter { $0.name.lowercased().hasPrefix(lower) }
                    .prefix(5)
            )
        } else {
            slashCandidates = []
        }
        hasPendingSlashCommand = matchesKnownCommand
    }

    private func recomputeMentionCandidates() {
        guard let query = mentionQuery else {
            mentionCandidates = []
            return
        }
        let lower = query.lowercased()
        mentionCandidates = Array(
            availableMentions
                .filter { lower.isEmpty || $0.displayName.lowercased().contains(lower) }
                .prefix(5)
        )
    }

    private func pickMention(_ target: MentionTarget) {
        guard let query = mentionQuery else { return }
        let dropCount = query.count + 1   // +1 for the `@`
        let head = String(promptText.dropLast(dropCount))
        switch target.kind {
        case .member:
            // Inline body token — survives in the message text and visible
            // to the human collaborator's eyes while typing.
            promptText = head + "@\(target.displayName) "
        case .agent:
            // Drop the `@<query>` trigger from the visible input. The chip
            // card above the composer is the in-flight routing indicator;
            // the body text is auto-prepended with `@<displayName> ` at
            // send time (composeBodyWithMentions in the viewmodel) so the
            // sent bubble preserves the mention without cluttering the
            // typing surface.
            promptText = head
            onAgentMention(target)
        }
        mentionCandidates = []
    }
}

private struct SendButtonGlassModifier: ViewModifier {
    let emphasized: Bool
    func body(content: Content) -> some View {
        if emphasized {
            content.liquidGlass(in: Circle(), tint: .accentColor)
        } else {
            content.liquidGlass(in: Circle())
        }
    }
}
