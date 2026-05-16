import Foundation
import Observation
import SwiftData

public struct SlashCommand: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let name: String
    public let description: String
    public let inputHint: String   // "" = no input required
    public var id: String { name }

    public init(name: String, description: String, inputHint: String) {
        self.name = name
        self.description = description
        self.inputHint = inputHint
    }
}

@Observable @MainActor
public final class SessionDetailViewModel {
    public var events: [AgentEvent] = []
    /// Slash commands announced by the attached runtime via
    /// ACP `AvailableCommandsUpdate`. Replaced wholesale on each push.
    /// In-memory only — not persisted to SwiftData.
    public var availableCommands: [SlashCommand] = []
    /// Memoised tool-run grouping over `events`. Views should iterate this
    /// instead of calling `groupEvents(vm.events)` in body, which previously
    /// made grouping O(n) on every streaming delta frame. Recomputed by
    /// `recomputeGroups()` at each mutation site.
    public private(set) var groupedEvents: [GroupedEvent] = []
    /// Higher-level feed grouping that hides per-turn runtime detail
    /// (thinking / tool_use / tool_result) behind active-stream cards or
    /// completed-turn bubbles. Source for the main chat list. Detail view
    /// reads `runtimeEvents` off each item to render the full turn.
    public private(set) var feedItems: [FeedItem] = []
    /// Per-agent streaming output buffer. Keyed by the agent actor id. An
    /// entry exists only between the first delta of an `output` stream and
    /// its `isComplete` event (or an idle status flush). Concurrent agents
    /// each get their own slot so multi-agent sessions don't smash a single
    /// buffer. Read for the active-stream card's last-line preview and the
    /// streaming detail view's full text. Empty string for "no active
    /// stream for this agent."
    public private(set) var streamingTextByAgent: [String: String] = [:]
    /// Per-agent model id stamped by the daemon on the most recent streaming
    /// `output` delta. Used so the synthesized event in stop()/idle flush
    /// carries the model that produced the partial text.
    private var streamingModelByAgent: [String: String] = [:]
    /// Set of agents whose `output` stream is in flight (first delta seen,
    /// no `isComplete` yet). Drives the active-stream-card visibility and
    /// the legacy `isStreaming` / `streamingText` shims.
    public private(set) var streamingAgentSet: Set<String> = []
    /// Backwards-compat shim for callers that haven't migrated to the
    /// per-agent map. True when ANY agent is streaming raw text. Most call
    /// sites should prefer `streamingAgentSet` for correct multi-agent
    /// behavior.
    public var isStreaming: Bool { !streamingAgentSet.isEmpty }
    /// Backwards-compat shim. Returns the streaming text of an arbitrary
    /// active agent — adequate for single-agent sessions; multi-agent UI
    /// must read `streamingTextByAgent[agentID]` directly.
    public var streamingText: String {
        guard let agentID = streamingAgentSet.first else { return "" }
        return streamingTextByAgent[agentID] ?? ""
    }
    public var isDaemonOnline = true

    // MARK: - Phase 4 reducer state
    //
    // `ChatTimelineReducer` is now the source of truth for entry
    // mutations. Inline handlers translate each event arrival into a
    // `TimelineInput`, apply the reducer, mirror the reducer's
    // streaming-buffer state into the VM's @Observable fields, then
    // project entries into the SwiftData-backed `events` array via
    // `TimelineSwiftDataSync.sync`. The view continues to read `events`
    // / `streamingTextByAgent` exactly as before.
    private var timelineState = TimelineState()
    /// User-visible transient error from the most recent send-prompt
    /// attempt. Set by `sendPrompt` when `TeamclawService.sendMessage`
    /// throws; auto-cleared after `errorMessageTTL` seconds. The UI binds
    /// to this for an inline banner so silent publish failures stop being
    /// invisible.
    public var sendErrorMessage: String?
    private var errorClearTask: Task<Void, Never>?
    private let errorMessageTTL: TimeInterval = 5
    public var runtime: Runtime?
    public let session: Session?
    private let mqtt: MQTTService
    private let hub: MQTTMessageHub
    private let teamID: String
    private let peerId: String
    private let teamclawService: TeamclawService?
    private let connectedAgentsStore: ConnectedAgentsStore?
    private let sessionsRepository: SessionRepository?
    private let agentRuntimesRepository: AgentRuntimesRepository?
    /// `nonisolated(unsafe)` so the deinit (which runs in a nonisolated
    /// context) can cancel the MQTT subscription task on VM teardown.
    /// Writes happen only from main-actor methods (`start`, `stop`); the
    /// deinit's read happens after all strong references are gone, so the
    /// data-race waiver here is safe in practice.
    nonisolated(unsafe) private var task: Task<Void, Never>?

    // MARK: - Chip-bar state
    /// Agent actors currently selected in the chip bar. Empty = no specific
    /// mention; all agents will receive the message (broadcast semantics on
    /// the daemon side). Populated by bootstrapChips / toggleAgentChip.
    public private(set) var agentChipSelection: Set<String> = []
    /// Once the user explicitly changes the chip bar or picks an @ mention,
    /// refreshes must preserve that choice. Otherwise the single-agent
    /// auto-light rule reselects the agent immediately after the user clears it.
    private var userEditedAgentChipSelection = false
    /// Ordered list of agent participants shown in the chip bar. Populated
    /// by bootstrapChips from the session's participant list + runtime states.
    public private(set) var agentChipParticipants: [AgentChipParticipant] = []

    // Expose for child views that need to pass these along
    public var mqttRef: MQTTService { mqtt }
    public var hubRef: MQTTMessageHub { hub }
    public var peerIdRef: String { peerId }
    public var teamIDRef: String { teamID }
    public var currentHumanActorIDRef: String? { teamclawService?.currentHumanActorId }
    /// Daemon device-id resolved from session/runtime context. Empty when
    /// no daemon mapping is available yet (e.g. ConnectedAgentsStore still
    /// loading and runtime row hasn't received state). Callers that need it
    /// for an MQTT publish should bail when empty.
    public var daemonDeviceIdRef: String { resolveDaemonDeviceId() }

    public var sessionTitle: String {
        if let runtime, !runtime.sessionTitle.isEmpty { return runtime.sessionTitle }
        if let runtime {
            let wt = runtime.worktree
            if !wt.isEmpty {
                let last = wt.split(separator: "/").last.map(String.init) ?? wt
                if last != "." { return last }
            }
            return runtime.runtimeId
        }
        if let session, !session.title.isEmpty { return session.title }
        return "Session"
    }

    public var isActive: Bool { runtime?.isActive ?? false }
    public var isIdle: Bool { runtime?.isIdle ?? true }

    /// Heartbeat-style "agent is currently doing something" flag. Source
    /// of truth for the chip-bar's stop button and any other UI that
    /// needs the full agent-busy window (thinking + tool_use + output).
    /// Why a separate flag: `runtime?.isActive` is unreliable for
    /// session-based detail views (often nil) and some ACP backends
    /// don't flip Active reliably between turns. `isStreaming` only
    /// covers raw text deltas and misses the thinking + tool_use phases.
    /// This flag flips on any ACP event arrival or sendPrompt, and
    /// clears on `statusChange:.idle` or after 10s of silence.
    public private(set) var isAgentWorking: Bool = false
    private var agentWorkingResetTask: Task<Void, Never>?
    public var participantCount: Int { session?.participantCount ?? 0 }
    public var hasRuntime: Bool { runtime != nil }

    /// Bucket key for AgentEvent storage. Multiple sessions sharing a single
    /// daemon agent identity (Runtime.runtimeId == daemon's Supabase actor_id
    /// — see resolveRuntime) would otherwise collide their event histories
    /// under one shared agentId, leaking session N-1's prompts/replies into
    /// session N's view. When a session is in scope we key by session_id;
    /// the legacy runtime-only path (no session) keeps using runtime.runtimeId.
    private var eventScopeKey: String {
        if let session, !session.sessionId.isEmpty { return session.sessionId }
        return runtime?.runtimeId ?? ""
    }

    /// Background sender that drains queued OutboxMessage rows. Injected
    /// by the view layer once it has both the live ModelContainer and a
    /// TeamclawService in scope. nil when this VM was constructed for a
    /// runtime-only legacy path (no session, no Teamclaw) where the
    /// outbox isn't applicable.
    public var outboxSender: OutboxSender?

    public init(runtime: Runtime?,
                mqtt: MQTTService,
                hub: MQTTMessageHub,
                teamID: String = "",
                peerId: String,
                session: Session? = nil,
                teamclawService: TeamclawService? = nil,
                connectedAgentsStore: ConnectedAgentsStore? = nil,
                sessionsRepository: SessionRepository? = nil,
                agentRuntimesRepository: AgentRuntimesRepository? = nil,
                outboxSender: OutboxSender? = nil) {
        self.runtime = runtime; self.mqtt = mqtt; self.hub = hub; self.teamID = teamID; self.peerId = peerId
        self.session = session; self.teamclawService = teamclawService
        self.connectedAgentsStore = connectedAgentsStore
        self.sessionsRepository = sessionsRepository
        self.agentRuntimesRepository = agentRuntimesRepository
        self.outboxSender = outboxSender
    }

    /// Resolves the daemon's MQTT device-id for the current runtime/session.
    /// Preference order:
    ///   1. ConnectedAgentsStore lookup keyed by `session.primaryAgentId` —
    ///      authoritative when the session is iOS-Supabase-created.
    ///   2. The runtime row's stored `daemonDeviceId` (populated by
    ///      SessionListVM from the topic path it received the state on).
    /// Returns an empty string when no daemon mapping is known yet — callers
    /// should treat that as "skip publish, retry later".
    private func resolveDaemonDeviceId() -> String {
        if let primary = session?.primaryAgentId,
           !primary.isEmpty,
           let agent = connectedAgentsStore?.agents.first(where: { $0.id == primary }),
           let id = agent.deviceID, !id.isEmpty {
            return id
        }
        if let runtime, !runtime.daemonDeviceId.isEmpty {
            return runtime.daemonDeviceId
        }
        return ""
    }

    /// Resolves the live `Runtime` row that backs this session. Delegates
    /// to `RuntimeResolver` (in AMUXCore/Runtimes) for the actual rule;
    /// this wrapper caches the result onto `self.runtime` so subsequent
    /// calls in the same view session return the same instance.
    private func resolveRuntime(modelContext: ModelContext) -> Runtime? {
        let resolved = RuntimeResolver.resolve(existing: runtime,
                                               session: session,
                                               modelContext: modelContext)
        if runtime == nil, let resolved {
            runtime = resolved
        }
        return resolved
    }

    /// Rebuilds `groupedEvents` from `events`. Call after any mutation that
    /// adds, removes, or reorders events, or changes the grouping-relevant
    /// fields on an existing event (eventType, isComplete, toolId).
    private func recomputeGroups() {
        groupedEvents = groupEvents(events)
        feedItems = buildFeedItems(events, streamingAgentIDs: streamingAgentSet)
    }

    private func sortEventsForDisplay() {
        events.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.id < $1.id
        }
        rebuildIndexes()
    }

    private func pruneDuplicateRuntimeEvents(modelContext: ModelContext) {
        struct Candidate {
            let index: Int
            let score: Int
        }

        var bestByKey: [String: Candidate] = [:]
        var duplicateIndexes = Set<Int>()

        for (index, event) in events.enumerated() {
            guard event.sequence > 0, event.eventType != "user_prompt" else { continue }
            let key = [
                String(event.sequence),
                event.eventType,
                event.senderActorID ?? "",
                event.toolId ?? "",
                event.text ?? ""
            ].joined(separator: "\u{1f}")
            let score = (event.supabaseMessageId == nil ? 0 : 4)
                + (event.isComplete ? 2 : 0)
                + (event.success == nil ? 0 : 1)

            if let current = bestByKey[key] {
                if score > current.score {
                    duplicateIndexes.insert(current.index)
                    bestByKey[key] = Candidate(index: index, score: score)
                } else {
                    duplicateIndexes.insert(index)
                }
            } else {
                bestByKey[key] = Candidate(index: index, score: score)
            }
        }

        guard !duplicateIndexes.isEmpty else { return }
        for index in duplicateIndexes.sorted(by: >) {
            modelContext.delete(events[index])
            events.remove(at: index)
        }
        try? modelContext.save()
    }

    // MARK: - Chip-bar bootstrap + selection

    /// Populate chip participants from the session's participant list and
    /// current runtime states. Call this after the session's participant
    /// rows have been resolved (e.g. from Supabase) and the connected-
    /// agents store has been queried for runtime state.
    ///
    /// Selection heuristic (Q7=c): if exactly one agent participates, pre-
    /// select it so the first send is automatically directed at that agent.
    /// Multi-agent sessions start with empty selection (broadcast mode).
    public func bootstrapChips(
        participants: [SessionParticipant],
        runtimeStates: [String: AgentRuntimeChipState],
        legacyPrimaryAgentID: String? = nil
    ) {
        var agents = participants.filter { $0.role == "agent" }

        // Compatibility: if the session has no agent participants but a legacy
        // primary_agent_id, synthesize one chip for that agent so the chat is
        // still routable.
        if agents.isEmpty, let primary = legacyPrimaryAgentID, !primary.isEmpty {
            agents = [SessionParticipant(actorID: primary, role: "agent", displayName: nil)]
        }

        self.agentChipParticipants = agents.map {
            AgentChipParticipant(
                id: $0.actorID,
                displayName: $0.displayName ?? String($0.actorID.prefix(8)),
                runtimeState: runtimeStates[$0.actorID] ?? .spawning
            )
        }
        // Q7=c default selection: lit if exactly one agent, else empty.
        self.agentChipSelection = (agents.count == 1)
            ? Set(agents.map(\.actorID))
            : []
    }

    /// Toggle the selected state of one chip. Called from the chip-bar tap handler.
    public func toggleAgentChip(_ agentID: String) {
        userEditedAgentChipSelection = true
        if agentChipSelection.contains(agentID) { agentChipSelection.remove(agentID) }
        else { agentChipSelection.insert(agentID) }
    }

    /// Ensure an agent's chip is lit. Idempotent — never unlights. Used by
    /// the @-mention picker so picking an agent always engages them; the
    /// chip-bar toolbar above the composer remains the surface for turning
    /// agents off.
    public func lightAgentChip(_ agentID: String) {
        userEditedAgentChipSelection = true
        agentChipSelection.insert(agentID)
    }

    /// Agent actor ids whose runtime is currently streaming a reply. Used
    /// by the chip bar to swap the chip's `×` button for a stop button.
    ///
    /// Today the detail view is anchored on either a bound runtime (legacy
    /// runtime-only init, where viewModel.runtime is non-nil) or a session
    /// (multi-agent init, where runtime is nil and the source of truth is
    /// memberSheetAgents). In the session case we currently lack per-agent
    /// streaming state, so when isStreaming is true we attribute it to the
    /// only agent in the session — adequate for single-agent sessions and
    /// gracefully degrades to the chip-bar's existing default-light rule.
    /// True per-agent streaming attribution is a future-work item that
    /// arrives with multi-agent ACP fanout.
    public var streamingAgentIDs: Set<String> {
        // `isAgentWorking` is the canonical busy signal — flips true on
        // any ACP event arrival (thinking, tool_use, output) and clears
        // on idle. `isActive`/`isStreaming` are kept as fallbacks so the
        // stop button stays up even if the heartbeat flag misses an
        // event for any reason.
        guard isAgentWorking || isActive || isStreaming else { return [] }
        if let boundRuntimeID = runtime?.runtimeId,
           let agent = memberSheetAgents.first(where: { $0.runtimeID == boundRuntimeID }) {
            return [agent.id]
        }
        // Session-based fallback: no bound runtime, so we can't disambiguate
        // among multiple agents. With exactly one agent, attribute the
        // busy state to it. With more, leave empty (chip stays as ×)
        // until per-agent attribution lands.
        if memberSheetAgents.count == 1, let only = memberSheetAgents.first {
            return [only.id]
        }
        return []
    }

    /// Cancel a specific agent's currently-running ACP turn. Today the
    /// app surfaces only the bound runtime in detail view, so this is a
    /// thin wrapper over the existing cancelTask. When the chip bar
    /// drives interrupts for non-bound runtimes we'll route via a
    /// per-runtime ACP cancel (and the routing rewrite arrives with
    /// that work).
    public func interruptAgent(_ agentActorID: String) {
        Task { try? await self.cancelTask() }
    }

    /// Prepend `@<displayName> ` for every lit chip whose token isn't
    /// already in the body. Lets the auto-light single-agent default
    /// produce a self-describing message (e.g. "@mini Top 10 news") even
    /// when the user typed only the prompt body. Manual @-picks are
    /// already inserted by the composer, so the contains() check skips
    /// them to avoid double-prepend.
    func composeBodyWithMentions(_ text: String) -> String {
        var body = text
        for agentID in agentChipSelection {
            guard let agent = memberSheetAgents.first(where: { $0.id == agentID }) else { continue }
            let token = "@\(agent.displayName)"
            if !body.localizedCaseInsensitiveContains(token) {
                body = body.isEmpty ? token : "\(token) \(body)"
            }
        }
        return body
    }

    /// Replace the entire chip selection. Used by Task 16 view integration.
    public func setAgentChipSelection(_ selection: Set<String>) {
        userEditedAgentChipSelection = true
        self.agentChipSelection = selection
    }

    // MARK: - Member sheet state
    //
    // Snapshot models (MemberSheetHuman / MemberSheetAgent) and the
    // loader/chipState/displayName helpers live in
    // AMUXCore/Sessions/SessionMemberSheetLoader.swift.

    public private(set) var memberSheetHumans: [MemberSheetHuman] = []
    public private(set) var memberSheetAgents: [MemberSheetAgent] = []

    /// Refreshes the member sheet data from Supabase. Called by the view
    /// each time the sheet opens. On failure keeps prior values.
    ///
    /// Loading / shaping logic lives in `SessionMemberSheetLoader`;
    /// this method binds the snapshot to the VM and runs the chip-bar
    /// auto-light cross-cutting rule.
    public func refreshMemberSheet() async {
        guard let session, !session.sessionId.isEmpty else { return }
        let loader = SessionMemberSheetLoader(
            sessionsRepository: sessionsRepository ?? (try? SupabaseSessionRepository()),
            agentRuntimesRepository: agentRuntimesRepository ?? (try? SupabaseAgentRuntimesRepository())
        )
        guard let snapshot = await loader.load(
            sessionID: session.sessionId,
            teamID: teamID,
            currentHumanActorID: teamclawService?.currentHumanActorId ?? "",
            availableModelsForAgent: { [weak self] actorID in
                self?.availableModels(forAgentActorID: actorID) ?? []
            }
        ) else {
            print("[RuntimeDetailVM] refreshMemberSheet: loader returned nil (no repo or fetch failed)")
            return
        }

        memberSheetHumans = snapshot.humans
        memberSheetAgents = snapshot.agents

        // Auto-light rule (Q7=c, lifted to refreshMemberSheet so the
        // chip bar's single-source-of-truth `memberSheetAgents` drives
        // chip selection). If the bar is currently empty AND there's
        // exactly one agent in the session, pre-engage them so the
        // first message routes without the user manually @-picking.
        if !userEditedAgentChipSelection,
           agentChipSelection.isEmpty,
           snapshot.agents.count == 1,
           let only = snapshot.agents.first {
            agentChipSelection = [only.id]
        }

        // memberSheet now provides runtime_id → actor_id mappings. Live
        // events that arrived before this load may have been stamped with
        // the raw runtime_id (bucketKey's `?? rid` fallback) and frozen
        // there by the resolution cache — see line ~1164. Supabase-seeded
        // history rows are stamped with the canonical actor_id directly,
        // so the two sources end up in two buckets for the same agent
        // and `buildFeedItems` produces duplicate bubbles / a phantom
        // trailing card. Reconcile here by retroactively rewriting the
        // raw stamps to the resolved actor_id.
        relabelRawRuntimeIDStampsToActorIDs()
    }

    /// Best-effort lookup of model ids for the chosen agent actor. Falls back
    /// to the bound `runtime.availableModels` (loaded by SessionListVM from the
    /// MQTT runtime/{id}/state retained topic) when it matches the agent.
    private func availableModels(forAgentActorID actorID: String) -> [String] {
        if let runtime, runtime.runtimeId == actorID || session?.primaryAgentId == actorID {
            return runtime.availableModels.map(\.id)
        }
        return []
    }

    /// Union of human + agent actor ids currently in the session, used by
    /// add-member / add-agent sheets to hide rows for participants already in.
    public var existingParticipantActorIDs: Set<String> {
        Set(memberSheetHumans.map(\.id)).union(memberSheetAgents.map(\.id))
    }

    /// Returns the ConnectedAgent rows the caller can pick from when adding a
    /// new agent to the session. Filters out the agents already participating
    /// so the picker shows only fresh candidates. Empty when the store hasn't
    /// loaded yet.
    public func candidatesForAddAgent() -> [ConnectedAgent] {
        let existing = existingParticipantActorIDs
        let agents = connectedAgentsStore?.agents ?? []
        return agents.filter { !existing.contains($0.id) }
    }

    /// Adds humans to the session via `session_participants`, then refreshes
    /// the member sheet so the new rows show up.
    public func addMembers(_ actorIDs: [String]) async {
        guard let session, !actorIDs.isEmpty else { return }
        let sessionID = session.sessionId
        guard !sessionID.isEmpty else { return }

        let sessionsRepo = self.sessionsRepository ?? (try? SupabaseSessionRepository())
        guard let sessionsRepo else {
            print("[RuntimeDetailVM] addMembers: no sessions repo available")
            return
        }
        do {
            try await sessionsRepo.addParticipants(sessionID: sessionID, actorIDs: actorIDs)
        } catch {
            print("[RuntimeDetailVM] addMembers: addParticipants failed: \(error)")
            // Fall through — refreshMemberSheet will still re-pull truth.
        }
        await refreshMemberSheet()
    }

    /// Adds an agent to the session and starts a runtime for it on the agent's
    /// daemon. Order matches NewSessionSheet's flow: insert participant first,
    /// then RPC into the daemon to spawn its runtime, then refresh the sheet.
    public func addAgent(actorID: String,
                         workspaceID: String,
                         worktreePath: String,
                         agentType: Amux_AgentType) async {
        guard let session else { return }
        let sessionID = session.sessionId
        guard !sessionID.isEmpty else { return }

        let sessionsRepo = self.sessionsRepository ?? (try? SupabaseSessionRepository())
        if let sessionsRepo {
            do {
                try await sessionsRepo.addParticipants(sessionID: sessionID, actorIDs: [actorID])
            } catch {
                print("[RuntimeDetailVM] addAgent: addParticipants failed: \(error)")
            }
        } else {
            print("[RuntimeDetailVM] addAgent: no sessions repo available")
        }

        // Resolve the daemon device id for this agent actor so the
        // runtime-start RPC reaches the right daemon. ConnectedAgentsStore
        // is the authoritative source — same lookup NewSessionSheet uses.
        guard let routeDevice = routeDeviceID(forAgentActorID: actorID), !routeDevice.isEmpty else {
            print("[RuntimeDetailVM] addAgent: no device id for agent actor \(actorID)")
            await refreshMemberSheet()
            return
        }

        if let teamclawService {
            let outcome = await teamclawService.runtimeStartRpc(
                targetDeviceID: routeDevice,
                agentType: agentType,
                workspaceId: workspaceID,
                worktree: worktreePath,
                sessionId: sessionID,
                initialPrompt: ""
            )
            if case .rejected(let reason) = outcome {
                print("[RuntimeDetailVM] addAgent: runtimeStart rejected: \(reason)")
            }
        } else {
            print("[RuntimeDetailVM] addAgent: no teamclawService configured")
        }

        await refreshMemberSheet()
    }

    /// Removes a human participant from this session.
    ///
    /// Supabase is the source of truth — delete the row first, then refresh
    /// the sheet so the UI reflects the new state. Peer realtime fanout to
    /// other clients is future work (open question: there's no obvious single
    /// daemon to RPC for human-only removal; the daemon's
    /// `handle_remove_participant` only updates its local cache + notify
    /// channel anyway, so for now we rely on each client's own Supabase poll).
    public func removeHuman(_ actorID: String) {
        Task { [weak self] in
            guard let self,
                  let sessionID = self.session?.sessionId,
                  !sessionID.isEmpty else { return }

            let sessionsRepo = self.sessionsRepository ?? (try? SupabaseSessionRepository())
            if let sessionsRepo {
                do {
                    try await sessionsRepo.removeParticipant(sessionID: sessionID, actorID: actorID)
                } catch {
                    print("[RuntimeDetailVM] removeHuman: removeParticipant failed: \(error)")
                }
            } else {
                print("[RuntimeDetailVM] removeHuman: no sessions repo available")
            }

            await self.refreshMemberSheet()
        }
    }

    /// Restarts an agent's runtime in the current session: best-effort Stop
    /// of the existing daemon subprocess followed by a fresh Start RPC in the
    /// same workspace + agent type. The daemon writes a new `agent_runtimes`
    /// row (or updates the existing one — its choice); `refreshMemberSheet`
    /// at the end re-pulls truth so the UI catches up.
    ///
    /// Edge cases:
    ///  - No `routeDeviceID` (agent's daemon offline): bail with a warning;
    ///    restart isn't possible without a live daemon.
    ///  - No `runtimeID` (runtime never spawned, or already stopped): skip
    ///    the Stop and go straight to Start.
    ///  - Empty / unresolvable worktree path: try Start anyway. The daemon
    ///    rejects with a clean error rather than us pre-validating.
    public func restartRuntime(forAgent actorID: String) {
        Task { [weak self] in
            guard let self,
                  let sessionID = self.session?.sessionId,
                  !sessionID.isEmpty,
                  let row = self.memberSheetAgents.first(where: { $0.id == actorID })
            else { return }

            guard let routeDeviceID = self.routeDeviceID(forAgentActorID: actorID),
                  !routeDeviceID.isEmpty
            else {
                print("[RuntimeDetailVM] restartRuntime: no device id for agent actor \(actorID); aborting")
                return
            }

            guard let teamclawService = self.teamclawService else {
                print("[RuntimeDetailVM] restartRuntime: no teamclawService configured")
                return
            }

            // 1. Stop existing runtime. Best-effort; if it's already gone the
            //    Start below will still do the right thing.
            if let runtimeID = self.runtimeID(forAgentActorID: actorID),
               !runtimeID.isEmpty {
                let (ok, err) = await teamclawService.runtimeStopRpc(
                    targetDeviceID: routeDeviceID,
                    runtimeID: runtimeID
                )
                if !ok {
                    print("[RuntimeDetailVM] restartRuntime: runtimeStop failed: \(err) — proceeding to start")
                }
            } else {
                print("[RuntimeDetailVM] restartRuntime: no runtime id for actor \(actorID); skipping stop")
            }

            // 2. Resolve the worktree filesystem path. `MemberSheetAgent`
            //    holds the workspace UUID (not a path) under both
            //    `workspaceID` and the legacy `workspacePath` field, so
            //    look it up against Supabase the same way `AddAgentSheet`
            //    does. Empty path falls through — the daemon rejects with
            //    a clean error.
            let workspaceID = row.workspaceID ?? row.workspacePath
            let worktreePath = await self.resolveWorkspacePath(
                workspaceID: workspaceID,
                agentActorID: actorID
            )

            // 3. Spawn a new runtime in the same workspace + same agent type.
            let agentType = Self.amuxAgentType(forBackendType: row.backendType)
            let outcome = await teamclawService.runtimeStartRpc(
                targetDeviceID: routeDeviceID,
                agentType: agentType,
                workspaceId: workspaceID,
                worktree: worktreePath,
                sessionId: sessionID,
                initialPrompt: ""
            )
            if case .rejected(let reason) = outcome {
                print("[RuntimeDetailVM] restartRuntime: runtimeStart rejected: \(reason)")
            }

            await self.refreshMemberSheet()
        }
    }

    /// Maps the `agent_runtimes.backend_type` string to the proto enum
    /// `runtimeStartRpc` expects. Mirrors the AMUXUI-side
    /// `AgentConfigSheet.AgentType.asAmuxAgentType` mapping; we duplicate it
    /// here because that helper lives in the UI package and can't be
    /// imported from AMUXCore.
    private static func amuxAgentType(forBackendType backendType: String?) -> Amux_AgentType {
        switch backendType {
        case "claude": return .claudeCode
        case "opencode": return .opencode
        case "codex": return .codex
        default: return .claudeCode
        }
    }

    /// Best-effort lookup of the worktree filesystem path for a workspace UUID.
    /// Uses Supabase via `SupabaseWorkspaceRepository`, narrowed to the agent's
    /// own workspaces first (matching `AddAgentSheet`'s default), then widened
    /// to all team workspaces if the agent-scoped query yielded nothing.
    /// Returns "" when the path can't be resolved — the daemon will reject
    /// with a clean error rather than us pre-validating here.
    private func resolveWorkspacePath(workspaceID: String, agentActorID: String) async -> String {
        guard !workspaceID.isEmpty, !teamID.isEmpty else { return "" }
        guard let repo = try? SupabaseWorkspaceRepository() else { return "" }

        if let agentScoped = try? await repo.listWorkspaces(teamID: teamID, agentID: agentActorID),
           let hit = agentScoped.first(where: { $0.id == workspaceID }) {
            return hit.path
        }
        if let allScoped = try? await repo.listWorkspaces(teamID: teamID, agentID: nil),
           let hit = allScoped.first(where: { $0.id == workspaceID }) {
            return hit.path
        }
        return ""
    }

    /// Switches the model for an agent's runtime. The daemon's SetModel RPC
    /// updates `current_model_per_agent` and re-publishes the runtime's
    /// retained state, so the member sheet refreshes via the normal state
    /// stream as well — but we still call `refreshMemberSheet` to pick up
    /// any participant-row deltas and to keep parity with the other write
    /// paths (`removeAgent`, `restartRuntime`).
    public func setModel(forAgent actorID: String, model: String) {
        Task { [weak self] in
            guard let self,
                  let teamclawService = self.teamclawService,
                  let routeDevice = self.routeDeviceID(forAgentActorID: actorID),
                  !routeDevice.isEmpty,
                  let runtimeID = self.runtimeID(forAgentActorID: actorID),
                  !runtimeID.isEmpty
            else {
                print("[RuntimeDetailVM] setModel: skipping — no resolvable route/runtime for actor=\(actorID)")
                return
            }
            let (ok, err) = await teamclawService.setModelRpc(
                targetDeviceID: routeDevice,
                runtimeID: runtimeID,
                modelID: model)
            if !ok {
                print("[RuntimeDetailVM] setModel RPC failed: \(err)")
            }
            await self.refreshMemberSheet()
        }
    }

    /// Removes an agent participant from this session.
    ///
    /// Three-step ordering:
    ///   1. Stop the agent's runtime (best-effort) so the Claude Code
    ///      subprocess actually exits — otherwise it keeps the worktree
    ///      busy and the session row in `agent_runtimes` stays "active"
    ///      until next daemon restart.
    ///   2. RPC the daemon to drop the agent from its in-memory session
    ///      participant cache + sessions.toml, and fan a notify event so
    ///      other connected clients re-pull. Best-effort; the Supabase
    ///      delete below is authoritative.
    ///   3. Delete the participant row from Supabase (source of truth).
    ///
    /// When the agent has no resolvable runtime id (e.g. the daemon is
    /// offline or `agent_runtimes` hasn't surfaced the row yet), step 1
    /// is skipped with a logged warning. The subprocess then keeps running
    /// until the daemon notices the participant is gone on next reload —
    /// suboptimal but recoverable.
    public func removeAgent(_ actorID: String) {
        Task { [weak self] in
            guard let self,
                  let sessionID = self.session?.sessionId,
                  !sessionID.isEmpty else { return }

            let routeDevice = self.routeDeviceID(forAgentActorID: actorID)
            let runtimeID = self.runtimeID(forAgentActorID: actorID)

            // 1. Stop the agent's runtime (best-effort).
            if let routeDevice, !routeDevice.isEmpty,
               let runtimeID, !runtimeID.isEmpty,
               let teamclawService = self.teamclawService {
                let (ok, err) = await teamclawService.runtimeStopRpc(
                    targetDeviceID: routeDevice, runtimeID: runtimeID)
                if !ok {
                    print("[RuntimeDetailVM] removeAgent: runtimeStop failed: \(err)")
                }
            } else {
                print("[RuntimeDetailVM] removeAgent: skipping runtimeStop — routeDevice=\(routeDevice ?? "nil") runtimeID=\(runtimeID ?? "nil")")
            }

            // 2. Best-effort daemon-side participant removal for cache
            //    invalidation + peer notify fanout.
            if let routeDevice, !routeDevice.isEmpty,
               let teamclawService = self.teamclawService {
                let (ok, err) = await teamclawService.removeParticipantRpc(
                    targetDeviceID: routeDevice,
                    sessionID: sessionID,
                    actorID: actorID)
                if !ok {
                    print("[RuntimeDetailVM] removeAgent: removeParticipantRpc failed: \(err)")
                }
            }

            // 3. Supabase delete (source of truth).
            let sessionsRepo = self.sessionsRepository ?? (try? SupabaseSessionRepository())
            if let sessionsRepo {
                do {
                    try await sessionsRepo.removeParticipant(sessionID: sessionID, actorID: actorID)
                } catch {
                    print("[RuntimeDetailVM] removeAgent: removeParticipant failed: \(error)")
                }
            } else {
                print("[RuntimeDetailVM] removeAgent: no sessions repo available")
            }

            await self.refreshMemberSheet()
        }
    }

    /// Resolves the MQTT device-id of the daemon backing an agent actor,
    /// using the in-memory `ConnectedAgentsStore`. Returns nil when the store
    /// hasn't loaded the agent yet (caller should treat as "skip / log").
    /// Same lookup `addAgent` and `NewSessionSheet` use to route runtime RPCs.
    private func routeDeviceID(forAgentActorID actorID: String) -> String? {
        connectedAgentsStore?.agents.first(where: { $0.id == actorID })?.deviceID
    }

    /// Looks up the daemon's 8-char runtime id for an agent actor in the
    /// current session, reading from the `MemberSheetAgent` snapshot that
    /// `refreshMemberSheet` populated. Nil when the row hasn't been seen yet
    /// (just-spawned, daemon offline, or not-yet-bound to this session).
    private func runtimeID(forAgentActorID actorID: String) -> String? {
        memberSheetAgents.first(where: { $0.id == actorID })?.runtimeID
    }

    // MARK: - Index caches (for O(1) event lookup during streaming)
    //
    // Long sessions accumulate thousands of events. Each tool_result /
    // permission_resolved / tool_title_update previously did a
    // `lastIndex(where:)` scan, making the event-handling hot path O(n)
    // and the full session O(n²). These maps + optionals give O(1) lookup;
    // they're maintained incrementally by `appendEvent`/`removeEvent` and
    // rebuilt after bulk operations (fetch, sort, insert-at-zero).
    private var toolUseIndexByToolId: [String: Int] = [:]
    private var permissionIndexByRequestId: [String: Int] = [:]
    private var todoUpdateIndex: Int?
    private var lastIncompleteOutputIndex: Int?

    private func rebuildIndexes() {
        toolUseIndexByToolId.removeAll(keepingCapacity: true)
        permissionIndexByRequestId.removeAll(keepingCapacity: true)
        todoUpdateIndex = nil
        lastIncompleteOutputIndex = nil
        for (i, e) in events.enumerated() { registerIndex(event: e, at: i) }
    }

    private func registerIndex(event: AgentEvent, at idx: Int) {
        switch event.eventType {
        case "tool_use":
            if let id = event.toolId { toolUseIndexByToolId[id] = idx }
        case "permission_request":
            if let id = event.toolId { permissionIndexByRequestId[id] = idx }
        case "todo_update":
            todoUpdateIndex = idx
        case "output":
            if !event.isComplete { lastIncompleteOutputIndex = idx }
        default:
            break
        }
    }

    private func appendEvent(_ event: AgentEvent) {
        let idx = events.count
        events.append(event)
        registerIndex(event: event, at: idx)
    }

    private func removeEvent(at idx: Int) {
        let removed = events.remove(at: idx)
        switch removed.eventType {
        case "tool_use":
            if let id = removed.toolId, toolUseIndexByToolId[id] == idx {
                toolUseIndexByToolId.removeValue(forKey: id)
            }
        case "permission_request":
            if let id = removed.toolId, permissionIndexByRequestId[id] == idx {
                permissionIndexByRequestId.removeValue(forKey: id)
            }
        case "todo_update":
            if todoUpdateIndex == idx { todoUpdateIndex = nil }
        case "output":
            if lastIncompleteOutputIndex == idx { lastIncompleteOutputIndex = nil }
        default: break
        }
        // Shift indexes that pointed past the removed position. k is tiny
        // in practice (one output, one todo, a handful of permissions,
        // tool count per session), so this stays well below the old
        // lastIndex(where:) cost over the whole event stream.
        for (k, v) in toolUseIndexByToolId where v > idx {
            toolUseIndexByToolId[k] = v - 1
        }
        for (k, v) in permissionIndexByRequestId where v > idx {
            permissionIndexByRequestId[k] = v - 1
        }
        if let t = todoUpdateIndex, t > idx { todoUpdateIndex = t - 1 }
        if let l = lastIncompleteOutputIndex, l > idx { lastIncompleteOutputIndex = l - 1 }
    }

    /// Validated O(1) lookup. Returns nil (and clears the stale cache
    /// entry) if the cached index no longer matches the predicate, so
    /// callers fall through to their "create new" branch as before.
    private func toolUseIndex(forToolId id: String) -> Int? {
        if let idx = toolUseIndexByToolId[id],
           idx < events.count,
           events[idx].eventType == "tool_use",
           events[idx].toolId == id {
            return idx
        }
        toolUseIndexByToolId.removeValue(forKey: id)
        return nil
    }

    private func permissionIndex(forRequestId id: String) -> Int? {
        if let idx = permissionIndexByRequestId[id],
           idx < events.count,
           events[idx].eventType == "permission_request",
           events[idx].toolId == id {
            return idx
        }
        permissionIndexByRequestId.removeValue(forKey: id)
        return nil
    }

    private func incompleteOutputIndex() -> Int? {
        if let idx = lastIncompleteOutputIndex,
           idx < events.count,
           events[idx].eventType == "output",
           events[idx].isComplete == false {
            return idx
        }
        lastIncompleteOutputIndex = nil
        return nil
    }

    /// Find an in-flight (incomplete) `output` event belonging to a
    /// specific agent. Used by per-agent streaming output flow so two
    /// concurrent agents don't accidentally claim each other's pending
    /// row when finalizing or replacing a synthetic stop()-saved event.
    private func incompleteOutputIndex(forAgentID agentID: String) -> Int? {
        // Walk newest-first since incomplete outputs cluster near the end.
        var i = events.count - 1
        while i >= 0 {
            let e = events[i]
            if e.eventType == "output",
               e.isComplete == false,
               (e.senderActorID ?? "") == agentID {
                return i
            }
            i -= 1
        }
        return nil
    }

    public func start(modelContext: ModelContext) {
        // Idempotent on re-appear. SwiftUI's NavigationStack fires the
        // source view's `.onAppear` again when a pushed destination
        // pops back; the VM and its MQTT subscription are still alive
        // from the first start(). Cancelling and re-running setup
        // would drop the in-flight `for await msg in stream` loop
        // mid-iteration, so every ACP envelope that arrived while the
        // destination was on top is lost. (Bug visible as
        // StreamingDetailView freezing on the first thinking row
        // until you navigate back, at which point the missed events
        // replay in via incremental sync.)
        if task != nil { return }
        startModelContext = modelContext

        // resolveRuntime may return a placeholder for session-with-pending-
        // primary-agent or nil for collab-only sessions with no agent yet.
        // Either is fine — the cached event load + Supabase seed work off
        // session.sessionId scope, and the streaming subscribe block below
        // gates on `session` not on `runtime`.
        let runtime = resolveRuntime(modelContext: modelContext)

        if let runtime {
            // Clear unread badge when user opens the session
            runtime.hasUnread = false
            try? modelContext.save()

            // Seed slash commands from the cached state-topic snapshot so
            // the composer popup is populated before (or even without) a
            // fresh AvailableCommandsUpdate arriving on the events stream.
            let cachedCommands = runtime.availableCommands
            if !cachedCommands.isEmpty && availableCommands.isEmpty {
                availableCommands = cachedCommands
            }
        }

        // Load cached events immediately (works offline). Scope keys on
        // session_id when present so collab-only sessions (no runtime yet)
        // still see past Supabase-seeded messages.
        let scope = eventScopeKey
        let descriptor = FetchDescriptor<AgentEvent>(
            predicate: #Predicate { $0.agentId == scope },
            sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.sequence)]
        )
        events = (try? modelContext.fetch(descriptor)) ?? []
        pruneDuplicateRuntimeEvents(modelContext: modelContext)
        sortEventsForDisplay()
        // Rehydrate the reducer's state from persisted events so
        // future applies dedup against prior session history.
        rehydrateTimelineStateFromEvents()

        // Insert initial prompt as first user bubble if not already present
        let initialPrompt: String = {
            if let session, !session.summary.isEmpty { return session.summary }
            if let runtime, !runtime.currentPrompt.isEmpty { return runtime.currentPrompt }
            return ""
        }()

        if !initialPrompt.isEmpty && !events.contains(where: { $0.eventType == "user_prompt" }) {
            let promptEvent = AgentEvent(agentId: scope, sequence: 0, eventType: "user_prompt")
            promptEvent.text = initialPrompt
            // Initial prompt comes from session.summary or runtime.currentPrompt
            // — both written by the session creator at create-time. Stamp the
            // creator so the chat row reads as theirs even before any live
            // messages arrive.
            promptEvent.senderActorID = session?.createdBy
            modelContext.insert(promptEvent)
            events.insert(promptEvent, at: 0)
            // insert-at-zero shifts every cached index; cheaper to rebuild
            rebuildIndexes()
            rehydrateTimelineStateFromEvents()
        }

        // Resume streaming state if there's an incomplete output event (saved by stop()).
        // Hydrate streamingText for an instant preview, then drop the synthetic
        // event — keeping it would render the same bytes as both a bubble and
        // the streaming text, and live deltas appended to streamingText would
        // visibly duplicate the bubble content. The incremental sync below
        // rebuilds streamingText from the daemon's raw deltas.
        if let idx = incompleteOutputIndex() {
            let lastOutput = events[idx]
            // Resume keyed by whatever attribution the synthetic stop()-saved
            // event carries. That id was stamped via bucketKey at flush time,
            // so it's either the agent actor id or the runtime id — both
            // remain valid keys for the streaming buffer dictionaries.
            let agentID = lastOutput.senderActorID ?? eventScopeKey
            streamingTextByAgent[agentID] = lastOutput.text ?? ""
            if let model = lastOutput.model { streamingModelByAgent[agentID] = model }
            if runtime?.isActive ?? false {
                streamingAgentSet.insert(agentID)
            }
            modelContext.delete(lastOutput)
            removeEvent(at: idx)
        }

        recomputeGroups()

        // Single subscription path: session/{sid}/live. iOS only ever
        // resolves a session-backed detail view — bare-runtime navigation
        // was deleted alongside RuntimeDestinationView. Daemon mirrors this
        // by fanning all agent envelopes (ACP events + HistoryBatch
        // replies) onto the same topic.
        guard let session else {
            print("[RuntimeDetailVM] no session bound; skipping subscribe")
            return
        }
        let subscribeTopic = MQTTTopics.sessionLive(teamID: teamID, sessionID: session.sessionId)
        let mqtt = self.mqtt
        let hub = self.hub
        task = Task { @MainActor [weak self, mqtt, hub, subscribeTopic, modelContext] in
            // Outer loop: each iteration represents a fresh MQTT connection lifecycle.
            // When the inner stream finishes (e.g. after disconnect clears continuations),
            // we loop back, wait for reconnect, resubscribe, and trigger an incremental
            // sync to fetch any events missed during the gap.
            while !Task.isCancelled {
                // Wait for MQTT to be connected
                while mqtt.connectionState != .connected {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }

                // Hub-filtered stream: only messages on the bound session's
                // live topic. The subscribe call below tells the broker to
                // deliver them; the predicate is the belt to those suspenders.
                let stream = await hub.messages(topic: subscribeTopic)
                try? await mqtt.subscribe(subscribeTopic)
                print("[RuntimeDetailVM] subscribed to \(subscribeTopic)")

                // Two-source recovery:
                //   1. Supabase `messages` for past finalized turns —
                //      this is the team-wide truth that survives any
                //      single daemon's history buffer (multi-agent
                //      friendly).
                //   2. Daemon RequestHistory for events the broker may
                //      have dropped on the floor (new session that's
                //      streaming RIGHT NOW between Supabase persistence
                //      and our subscribe; or kill+relaunch mid-turn).
                //      Without this, fresh session detail shows nothing
                //      until the agent finishes a turn.
                // Dedupe: Supabase-seeded events carry a supabaseMessageId
                // and won't be duplicated by re-running the seed; daemon
                // replay uses sequence-based filtering. Some past-turn
                // double-display can happen for sessions that have BOTH
                // Supabase rows AND daemon history; acceptable trade-off
                // until we add cross-source content dedupe.
                await self?.seedFromSupabaseMessages(modelContext: modelContext)
                try? await self?.requestIncrementalSync(modelContext: modelContext)

                for await msg in stream {
                    guard let self else { return }
                    guard let live = try? Teamclaw_LiveEventEnvelope(serializedBytes: msg.payload)
                    else { continue }

                    if live.eventType == "acp.event",
                       let envelope = try? Amux_Envelope(serializedBytes: live.body) {
                        handleEnvelope(envelope, modelContext: modelContext)
                    } else if live.eventType.hasPrefix("message."),
                              let msgEnv = try? Teamclaw_SessionMessageEnvelope(serializedBytes: live.body),
                              msgEnv.hasMessage {
                        // Other collaborators' chat messages — convert to a
                        // user_prompt AgentEvent so EventFeedView renders
                        // them. Loopback / dedupe handled inside.
                        handleIncomingChatMessage(msgEnv.message, modelContext: modelContext)
                    }
                }
                // Stream finished — connection likely dropped. Loop and resubscribe.
                if Task.isCancelled { return }
                print("[RuntimeDetailVM] stream ended, waiting to resubscribe…")
            }
        }
    }

    /// VM lifetime cleanup. Task closure captures `self` weakly so this
    /// fires once the owning view drops its last reference (e.g., user
    /// navigates back from the session detail to the session list).
    /// Without explicit cancel here, the `while !Task.isCancelled` loop
    /// keeps spinning and the MQTT subscription leaks.
    deinit {
        task?.cancel()
    }

    public func stop() {
        task?.cancel(); task = nil

        // Flush every in-progress per-agent streaming buffer to a
        // persisted incomplete event so it's visible when the user returns.
        // Multi-agent: each active stream gets its own synthetic row stamped
        // with the producing agent's actor id.
        if !streamingAgentSet.isEmpty, runtime != nil, let ctx = startModelContext {
            var seq = (events.last?.sequence ?? 0) + 1
            for agentID in streamingAgentSet {
                guard let text = streamingTextByAgent[agentID], !text.isEmpty else { continue }
                let event = AgentEvent(agentId: eventScopeKey, sequence: seq, eventType: "output")
                event.senderActorID = agentID
                event.text = text
                event.isComplete = false
                event.model = streamingModelByAgent[agentID]
                ctx.insert(event)
                appendEvent(event)
                seq += 1
            }
            try? ctx.save()
            streamingAgentSet.removeAll()
            streamingTextByAgent.removeAll()
            streamingModelByAgent.removeAll()
            recomputeGroups()
        }
        startModelContext = nil
    }

    private func handleEnvelope(_ env: Amux_Envelope, modelContext: ModelContext) {
        switch env.payload {
        case .acpEvent(let acp):
            if handleAcpEvent(acp,
                              sequence: Int(env.sequence),
                              runtimeID: env.runtimeID,
                              modelContext: modelContext) {
                try? modelContext.save()
                recomputeGroups()
            }
        case .sessionEvent(let evt): handleSessionEvent(evt, sequence: Int(env.sequence), modelContext: modelContext)
        case .none: break
        }
    }

    /// Handles a `message.created` live envelope (chat message from another
    /// collaborator, or a loopback of our own send). For pure-human sessions
    /// this is the only inbound source — there's no daemon fanning ACP
    /// events. We convert the proto message into a `user_prompt` AgentEvent
    /// so EventFeedView renders it the same way as the local user's typed
    /// prompts.
    ///
    /// Loopback dedupe is two-layer: senderActorID match against the local
    /// human actor catches the common case; a content+type fallback covers
    /// older actors that haven't resolved currentHumanActorId yet, and
    /// re-arrivals during reconnect.
    private func handleIncomingChatMessage(_ message: Teamclaw_Message, modelContext: ModelContext) {
        // Pre-filters: only render text messages, and drop our own
        // loopbacks + content-equal duplicates before feeding the
        // reducer so its identity-dedup doesn't conflate a fresh
        // message with a re-arrival under a different messageID.
        guard message.kind == .text else { return }
        let myActorID = teamclawService?.currentHumanActorId ?? ""
        if !myActorID.isEmpty, message.senderActorID == myActorID { return }
        let content = message.content
        if events.contains(where: {
            $0.eventType == "user_prompt" && ($0.text ?? "") == content
        }) {
            return
        }

        let dirty = applyTimelineInput(
            .liveMessage(LiveMessageInput(
                messageID: message.messageID.isEmpty ? UUID().uuidString : message.messageID,
                clientLocalID: nil,
                senderActorID: message.senderActorID,
                content: content,
                createdAt: message.createdAt > 0
                    ? Date(timeIntervalSince1970: TimeInterval(message.createdAt))
                    : .now
            )),
            modelContext: modelContext
        )
        if dirty { recomputeGroups() }
    }

    /// Builds a fresh AgentEvent stamped with the agent that produced it.
    /// Resolution prefers the agent actor id mapped from the envelope's
    /// `runtime_id` via `memberSheetAgents`; when that mapping isn't ready
    /// yet (cold start before refreshMemberSheet, or a runtime row not
    /// in the session participants) we stamp the runtime id itself so
    /// the event still lands in its own per-runtime bucket. We
    /// deliberately do NOT fall back to `session.primaryAgentId` —
    /// concurrent agents would otherwise cross-attribute their early
    /// events to whichever agent happens to be "primary."
    private func makeAgentSideEvent(sequence: Int,
                                    eventType: String,
                                    runtimeID: String? = nil) -> AgentEvent {
        let event = AgentEvent(agentId: eventScopeKey, sequence: sequence, eventType: eventType)
        event.senderActorID = bucketKey(forRuntimeID: runtimeID)
        return event
    }

    /// Resolve a daemon-side `runtime_id` (8-char) to the owning agent
    /// actor id by walking `memberSheetAgents`. Returns nil when no match
    /// — callers should fall back to the runtime id via `bucketKey`
    /// rather than to a session-wide "primary" agent.
    private func agentActorID(forRuntimeID runtimeID: String?) -> String? {
        guard let runtimeID, !runtimeID.isEmpty else { return nil }
        return memberSheetAgents.first(where: { $0.runtimeID == runtimeID })?.id
    }

    /// First-resolved bucket key per runtime_id, frozen for the lifetime
    /// of this VM. The mapping memberSheetAgents → bucketKey can flip
    /// from raw runtime_id to agent_actor_id mid-turn (memberSheet is
    /// loaded asynchronously). If thinking lands with the raw form and
    /// the closing output lands with the mapped form, the two entries
    /// pick up different `senderActorID`s and `buildFeedItems` strands
    /// the thinking row in a trailing activeStream card instead of
    /// bundling it into the completedTurn. Freezing on first resolve
    /// trades a momentary "raw id as chip label" cosmetic miss for a
    /// stable grouping key. New VM per detail view → cache rebuilds
    /// from scratch on every session open.
    private var resolvedBucketKeyByRuntimeID: [String: String] = [:]

    /// Stable per-agent bucket key used for `senderActorID` stamping and
    /// the streaming-buffer dictionaries. Returns the cached resolution
    /// if we've seen this runtime_id before; otherwise resolves once
    /// (mapped → fall back to raw runtime_id) and caches. Nil only when
    /// no runtime_id is supplied at all (legacy session-event paths).
    private func bucketKey(forRuntimeID runtimeID: String?) -> String? {
        guard let rid = runtimeID, !rid.isEmpty else { return nil }
        if let cached = resolvedBucketKeyByRuntimeID[rid] { return cached }
        let resolved = agentActorID(forRuntimeID: rid) ?? rid
        resolvedBucketKeyByRuntimeID[rid] = resolved
        return resolved
    }

    /// Once `memberSheetAgents` finishes loading, walk every state slice
    /// that stamps `senderActorID` and rewrite raw runtime_id stamps to
    /// the resolved agent_actor_id. Without this:
    ///   - live MQTT events that arrived before memberSheet loaded sit in
    ///     a "5ffcd7fc" (raw) bucket forever (`bucketKey` cache freezes
    ///     on first resolve to avoid mid-turn flips)
    ///   - Supabase-seeded history rows land in a "c6205a14-…" (actor id)
    ///     bucket for the same agent
    ///   - `buildFeedItems` strands them into separate `.completedTurn`
    ///     entries + leaves a permanent trailing `.activeStream` card
    ///     because `statusChange:.idle` resolves to the actor_id bucket
    ///     and doesn't match the streaming buffer's raw-id key
    private func relabelRawRuntimeIDStampsToActorIDs() {
        // runtime_id → actor_id from the freshly-loaded memberSheet.
        var mapping: [String: String] = [:]
        for agent in memberSheetAgents {
            guard let rid = agent.runtimeID, !rid.isEmpty, rid != agent.id else { continue }
            mapping[rid] = agent.id
        }
        if mapping.isEmpty { return }

        var didMutateEvents = false
        for (rawID, actorID) in mapping {
            // Refresh the resolution cache so future `bucketKey` calls
            // route to the actor id, not the raw runtime id.
            resolvedBucketKeyByRuntimeID[rawID] = actorID

            for idx in events.indices where events[idx].senderActorID == rawID {
                events[idx].senderActorID = actorID
                didMutateEvents = true
            }

            for idx in timelineState.entries.indices
                where timelineState.entries[idx].senderActorID == rawID {
                timelineState.entries[idx].senderActorID = actorID
            }

            // streamingAgentSet / streamingTextByAgent / streamingModelByAgent
            // are mirrored from timelineState by `applyTimelineInput` —
            // rewrite timelineState first, then mirror at the end.
            if timelineState.streamingAgentSet.remove(rawID) != nil {
                timelineState.streamingAgentSet.insert(actorID)
            }
            if let text = timelineState.streamingTextByAgent.removeValue(forKey: rawID) {
                timelineState.streamingTextByAgent[actorID, default: ""] += text
            }
            if let model = timelineState.streamingModelByAgent.removeValue(forKey: rawID) {
                timelineState.streamingModelByAgent[actorID] = model
            }
        }

        // Mirror reducer state onto the VM's @Observable fields so the
        // chat feed picks up the rebucketed streaming buffers.
        streamingAgentSet = timelineState.streamingAgentSet
        streamingTextByAgent = timelineState.streamingTextByAgent
        streamingModelByAgent = timelineState.streamingModelByAgent

        if didMutateEvents {
            try? startModelContext?.save()
            recomputeGroups()
        } else {
            // Even if no SwiftData rows changed, streaming/state buckets
            // may have moved; recompute so the trailing activeStream card
            // (if any) re-renders against the new bucket.
            recomputeGroups()
        }
    }

    /// Applies one ACP event to in-memory + SwiftData state. Returns `true`
    /// iff the event caused a SwiftData mutation or a change to grouping-
    /// relevant fields; callers save + recompute groups only when `true`.
    /// Streaming deltas (the hot path, dozens per second) return `false`
    /// after the first delta of a stream, skipping the SQLite commit and
    /// the O(n) regroup that would otherwise fire on every token.
    @discardableResult
    private func handleAcpEvent(_ acp: Amux_AcpEvent,
                                sequence: Int,
                                runtimeID: String? = nil,
                                modelContext: ModelContext) -> Bool {
        // Heartbeat: any ACP event arrival means the runtime is busy.
        // Drives the chip stop icon / streamingAgentIDs across the
        // whole turn (thinking → tool_use → output) regardless of
        // whether `runtime.isActive` flipped on the daemon side.
        markAgentWorking()

        // Reducer is source of truth for entry mutations. Apply +
        // project. Side effects the reducer doesn't track (runtime
        // status flip, markAgentDone heartbeat reset) are handled
        // below.
        let dirty = applyTimelineInput(
            .acp(AcpInput(
                envelopeSequence: UInt64(sequence),
                runtimeID: runtimeID ?? "",
                agentBucketKey: bucketKey(forRuntimeID: runtimeID) ?? eventScopeKey,
                timestamp: .now,
                acpEvent: acp
            )),
            modelContext: modelContext
        )

        // Runtime status + heartbeat side effects.
        if case .statusChange(let sc) = acp.event {
            runtime?.status = Int(sc.newStatus.rawValue)
            if sc.newStatus == .idle { markAgentDone() }
        }

        // Hand-rolled raw tool_title_update parser. The reducer
        // explicitly leaves `.raw` alone (see TimelineInput.swift
        // contract); patch the matching tool_use entry in place.
        if case .raw(let raw) = acp.event, raw.method == "tool_title_update" {
            let payload = String(data: raw.jsonPayload, encoding: .utf8) ?? ""
            if let pipeIdx = payload.firstIndex(of: "|") {
                let toolId = String(payload[payload.startIndex..<pipeIdx])
                let newTitle = String(payload[payload.index(after: pipeIdx)...])
                if let idx = events.firstIndex(where: { $0.eventType == "tool_use" && $0.toolId == toolId }) {
                    events[idx].toolName = newTitle
                    try? modelContext.save()
                    return true
                }
            }
        }

        return dirty
    }

    private func handleSessionEvent(_ sessionEvent: Amux_SessionEvent, sequence: Int, modelContext: ModelContext) {
        switch sessionEvent.event {
        case .promptAccepted:
            // Confirmation: set runtime to active (triggers typing indicator)
            runtime?.status = Int(Amux_AgentStatus.active.rawValue)
        case .promptRejected(let pr):
            let event = makeAgentSideEvent(sequence: sequence, eventType: "error")
            event.text = "Rejected: \(pr.reason)"
            appendEvent(event)
            recomputeGroups()
        case .permissionResolved(let resolved):
            // Reducer updates the matching permission_request entry
            // in place; sync mirrors the mutation onto the SwiftData
            // row. Drops silently if there's no matching entry, same
            // as the prior inline behaviour.
            let dirty = applyTimelineInput(
                .permissionResolution(PermissionResolutionInput(
                    requestID: resolved.requestID,
                    granted: resolved.granted
                )),
                modelContext: modelContext
            )
            if dirty { recomputeGroups() }
        case .historyBatch(let batch):
            handleHistoryBatch(batch)
        case .none:
            break
        }
    }

    private var syncModelContext: ModelContext?
    public var isSyncing = false
    private var syncGeneration: Int = 0
    private var startModelContext: ModelContext?

    private func handleHistoryBatch(_ batch: Amux_HistoryBatch) {
        guard let modelContext = syncModelContext else { return }
        let existingSeqs = Set(events.compactMap { $0.sequence != 0 ? $0.sequence : nil })

        // Aggregate dirty across the batch so we save + regroup once per page
        // instead of per-event. Sort+regroup is deferred to the last page in
        // the common case where the client keeps paginating (batch.hasMore_p).
        var anyDirty = false
        for envelope in batch.events {
            let seq = Int(envelope.sequence)
            guard !existingSeqs.contains(seq) else { continue }

            if case .acpEvent(let acp) = envelope.payload {
                if handleAcpEvent(acp,
                                  sequence: seq,
                                  runtimeID: envelope.runtimeID,
                                  modelContext: modelContext) {
                    anyDirty = true
                }
            }
        }

        if anyDirty {
            try? modelContext.save()
        }

        if batch.hasMore_p {
            // Mid-sync: rebuild groups so the user sees progress, but defer
            // the O(n log n) sort to the final page.
            if anyDirty { recomputeGroups() }
            Task {
                try? await requestHistoryPage(afterSequence: batch.nextAfterSequence)
            }
        } else {
            sortEventsForDisplay()
            recomputeGroups()
            syncGeneration &+= 1
            isSyncing = false
        }
    }

    /// Fetch events newer than our local max sequence from the daemon.
    /// Cursor-based + paginated — cheap to call on every reconnect / foreground.
    ///
    /// Pull `messages` rows for this session from Supabase and project them
    /// into AgentEvent rows so past completed turns are visible without
    /// hitting the daemon's per-runtime history buffer. Dedupe is keyed on
    /// `supabaseMessageId` — re-running the seed is a no-op once the rows
    /// have been ingested. Tool calls / thinking / status events are NOT
    /// represented; only `user_*` and `agent_reply` kinds become AgentEvents.
    public func seedFromSupabaseMessages(modelContext: ModelContext) async {
        guard let session else { return }
        guard let repo = try? SupabaseMessagesRepository() else { return }
        let messages: [MessageRecord]
        do {
            messages = try await repo.listForSession(sessionID: session.sessionId)
        } catch {
            print("[RuntimeDetailVM] supabase messages seed failed: \(error)")
            return
        }
        guard !messages.isEmpty else { return }

        // Reducer dedupes by `supabaseMessageID` and backfills the
        // id onto an existing content-equal entry when one exists.
        // Apply per record, project once at the end.
        var anyChange = false
        for record in messages {
            let kind: HistoryKind
            switch record.kind {
            case "agent_reply": kind = .output
            // "text" is the legacy iOS write spelling — kept here so
            // rows that landed in Supabase before the writer switched
            // to "user_message" still rehydrate. Drop once those rows
            // age out.
            case "user_message", "user_prompt", "text": kind = .userPrompt
            default: continue
            }
            let dirty = applyTimelineInput(
                .historyMessage(HistoryInput(
                    supabaseMessageID: record.id,
                    kind: kind,
                    senderActorID: record.senderActorID.isEmpty ? nil : record.senderActorID,
                    content: record.content,
                    createdAt: record.createdAt,
                    model: record.model,
                    turnID: record.turnID
                )),
                modelContext: modelContext
            )
            if dirty { anyChange = true }
        }
        if anyChange { recomputeGroups() }
    }

    /// Also clears any stale streaming UI state: if the app was backgrounded
    /// mid-stream and missed the `isComplete=true` or `status_change=idle`
    /// event, `isStreaming` could be stuck showing a typing indicator. The
    /// history batch will restore the correct state (and if the runtime is
    /// actually still streaming, incoming deltas will flip `isStreaming` back).
    public func requestIncrementalSync(modelContext: ModelContext) async throws {
        guard runtime != nil else { return }
        self.syncModelContext = modelContext
        isSyncing = true
        // Clear stale streaming state — will be re-established by the batch
        // (if runtime is idle now) or by fresh deltas (if it's still active).
        streamingAgentSet.removeAll()
        streamingTextByAgent.removeAll()
        streamingModelByAgent.removeAll()
        let maxSeq = events.compactMap({ $0.sequence != 0 ? $0.sequence : nil }).max() ?? 0

        // Watchdog: if no history batch arrives (daemon offline, runtime gone,
        // etc.) the response handler in handleHistoryBatch never fires and the
        // button would spin forever. Bumping a generation token makes back-to-back
        // syncs safe — only the watchdog matching the active generation resets state.
        syncGeneration &+= 1
        let myGeneration = syncGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            if self.syncGeneration == myGeneration && self.isSyncing {
                self.isSyncing = false
            }
        }

        try await requestHistoryPage(afterSequence: UInt64(maxSeq))
    }

    private func requestHistoryPage(afterSequence: UInt64) async throws {
        var req = Amux_AcpRequestHistory()
        req.afterSequence = afterSequence
        req.pageSize = 50
        req.requestID = UUID().uuidString
        try await sendCommand { $0.command = .requestHistory(req) }
    }

    private func sendCommand(_ makeCommand: (inout Amux_AcpCommand) -> Void) async throws {
        guard let runtime else {
            await surfaceSendError(SendCommandError.noRuntime)
            throw SendCommandError.noRuntime
        }
        let deviceID = resolveDaemonDeviceId()
        let sender = RuntimeCommandSender(mqtt: mqtt, teamID: teamID, peerID: peerId)
        do {
            try await sender.send(
                runtimeID: runtime.runtimeId,
                deviceID: deviceID,
                currentHumanActorID: teamclawService?.currentHumanActorId,
                makeCommand: makeCommand
            )
        } catch let error as SendCommandError {
            if case .daemonDeviceIdUnresolved = error {
                print("[RuntimeDetailVM] dropping command — daemon device-id not resolved (primaryAgentId=\(session?.primaryAgentId ?? "nil") runtimeId=\(runtime.runtimeId))")
            }
            await surfaceSendError(error)
            throw error
        } catch {
            await surfaceSendError(error)
            throw error
        }
    }

    public func sendPrompt(_ text: String, modelId: String? = nil, modelContext: ModelContext? = nil) async throws {
        if let session, let teamclawService {
            // Session-backed chats use the session live stream as the
            // canonical messaging channel so other collaborators see the
            // user's prompt too. The daemon subscribes to session/{sid}/live
            // and forwards each message to its bound ACP runtime.
            //
            // Body composition: prepend `@<displayName> ` for any lit chip
            // that the user hasn't already typed inline. The auto-light
            // single-agent default would otherwise produce a body without
            // any visible mention even though the chip is engaging an
            // agent — confusing in chat history, especially for other
            // collaborators reading along.
            let body = composeBodyWithMentions(text)
            let messageID = UUID().uuidString
            let mentionIDs = Array(agentChipSelection)

            // 1. Local user_prompt entry for the bubble. The
            //    reducer's .localPrompt path stamps `outboxMessageID =
            //    clientID` onto the entry so the chat view's
            //    status-dot accessory binds correctly. Apply +
            //    project; the sync layer inserts the matching
            //    AgentEvent row.
            if let ctx = modelContext ?? startModelContext {
                let dirty = applyTimelineInput(
                    .localPrompt(LocalPromptInput(
                        clientID: messageID,
                        senderActorID: teamclawService.currentHumanActorId ?? "",
                        content: body,
                        createdAt: .now
                    )),
                    modelContext: ctx
                )
                if dirty { recomputeGroups() }
            }

            // Flip the busy flag immediately on send so the chip-bar
            // stop button surfaces without waiting for the first ACP
            // event to round-trip. The 10s safety reset still fires;
            // the first real ACP event resets the timer.
            markAgentWorking()

            // 2. Hand the body off to the outbox. The sender loop will
            //    drive MQTT publish + Supabase persist with retries.
            //    Falls back to the legacy synchronous path when the
            //    outbox sender hasn't been wired in (e.g. tests).
            if let outboxSender {
                await outboxSender.enqueue(
                    messageID: messageID,
                    sessionID: session.sessionId,
                    senderActorID: teamclawService.currentHumanActorId ?? "",
                    content: body,
                    mentionActorIDs: mentionIDs,
                    modelID: modelId
                )
                return
            }

            // Legacy (test/no-outbox) fallback: send synchronously and
            // surface the error inline. Production view-paths always
            // construct an OutboxSender so this branch is exercised
            // primarily by unit tests / earlier-API callers.
            do {
                _ = try await teamclawService.sendMessage(
                    sessionId: session.sessionId,
                    content: body,
                    modelId: modelId,
                    mentionActorIDs: mentionIDs,
                    messageID: messageID
                )
            } catch {
                surfaceSendError(error)
                throw error
            }
        } else if runtime != nil {
            // Legacy runtime-only flow (no session): send via ACP command.
            let seq = (events.last?.sequence ?? 0) + 1
            let userEvent = AgentEvent(agentId: eventScopeKey, sequence: seq, eventType: "user_prompt")
            userEvent.text = text
            userEvent.senderActorID = teamclawService?.currentHumanActorId
            if let ctx = modelContext ?? syncModelContext { ctx.insert(userEvent); try? ctx.save() }
            appendEvent(userEvent)
            recomputeGroups()

            var p = Amux_AcpSendPrompt(); p.text = text
            if let modelId, !modelId.isEmpty {
                p.modelID = modelId
            }
            try await sendCommand { $0.command = .sendPrompt(p) }
        }
    }
    @MainActor
    private func surfaceSendError(_ error: Error) {
        sendErrorMessage = error.localizedDescription
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self, errorMessageTTL] in
            try? await Task.sleep(for: .seconds(errorMessageTTL))
            guard let self, !Task.isCancelled else { return }
            self.sendErrorMessage = nil
        }
    }

    public func cancelTask() async throws {
        try await sendCommand { $0.command = .cancel(Amux_AcpCancel()) }
        markAgentDone()
    }

    /// Flip isAgentWorking on and arm a 10s safety reset so a missed
    /// `statusChange:.idle` event doesn't leave the chip stuck in stop.
    private func markAgentWorking() {
        isAgentWorking = true
        agentWorkingResetTask?.cancel()
        agentWorkingResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.isAgentWorking = false }
        }
    }

    private func markAgentDone() {
        isAgentWorking = false
        agentWorkingResetTask?.cancel()
        agentWorkingResetTask = nil
    }

    // MARK: - Phase 4 reducer apply + project

    /// Apply one input to the reducer, mirror the reducer-owned
    /// auxiliary state (streaming buffers, availableCommands) onto the
    /// VM's @Observable fields, then project entries into the
    /// SwiftData-backed `events`. Returns `true` iff the projection
    /// mutated the events array — callers use that to decide when to
    /// recompute groups.
    @discardableResult
    private func applyTimelineInput(_ input: TimelineInput,
                                    modelContext: ModelContext) -> Bool {
        ChatTimelineReducer.apply(input, to: &timelineState)
        timelineState.entries.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.id < $1.id
        }
        // Mirror the reducer's per-agent buffers + slash commands so
        // the view's existing @Observable bindings stay correct.
        streamingTextByAgent = timelineState.streamingTextByAgent
        streamingModelByAgent = timelineState.streamingModelByAgent
        streamingAgentSet = timelineState.streamingAgentSet
        if !timelineState.availableCommands.isEmpty {
            availableCommands = timelineState.availableCommands
        }
        // Project entries → SwiftData rows.
        return TimelineSwiftDataSync.sync(
            state: timelineState,
            into: &events,
            agentId: eventScopeKey,
            modelContext: modelContext
        )
    }

    /// Rehydrate the reducer's entry state from the SwiftData-loaded
    /// `events` at view-mount time. Without this, the first reducer
    /// applies dedup against an empty state and we'd duplicate every
    /// historical row.
    ///
    /// Streaming buffers are reset to empty: a stop()/start() cycle
    /// (triggered by every NavigationStack push of `StreamingDetailView`)
    /// re-enters this function, and the reducer-owned streaming state
    /// from before the stop is now stale — the matching SwiftData
    /// state was already persisted as a synthetic incomplete-output
    /// entry by `stop()`. Leaving the prior streaming set in place
    /// would short-circuit the `.output(notComplete)` first-delta
    /// path on the next delta (set already contains the bucket), so
    /// the synthetic never gets absorbed, accumulates as orphan
    /// entries in `state.entries`, and bleeds into every subsequent
    /// completedTurn's `runtimeEvents`.
    private func rehydrateTimelineStateFromEvents() {
        timelineState.entries = events.map { event in
            TimelineEntry(
                id: event.id,
                sequence: UInt64(max(event.sequence, 0)),
                eventType: event.eventType,
                text: event.text,
                toolID: event.toolId,
                toolName: event.toolName,
                isComplete: event.isComplete,
                success: event.success,
                senderActorID: event.senderActorID,
                timestamp: event.timestamp,
                model: event.model,
                supabaseMessageID: event.supabaseMessageId,
                outboxMessageID: event.outboxMessageID,
                turnID: event.turnID
            )
        }
        timelineState.streamingTextByAgent = [:]
        timelineState.streamingModelByAgent = [:]
        timelineState.streamingAgentSet = []
    }
    public func grantPermission(requestId: String) async throws {
        var g = Amux_AcpGrantPermission(); g.requestID = requestId
        try await sendCommand { $0.command = .grantPermission(g) }
    }
    public func denyPermission(requestId: String) async throws {
        var d = Amux_AcpDenyPermission(); d.requestID = requestId
        try await sendCommand { $0.command = .denyPermission(d) }
    }
}

// MARK: - Test seams (DEBUG only)

#if DEBUG
extension SessionDetailViewModel {
    /// Builds a minimal VM suitable for unit tests. Uses a stub MQTTService
    /// (no network) and no session/runtime context.
    public static func testInstance() -> SessionDetailViewModel {
        let mqtt = MQTTService()
        return SessionDetailViewModel(
            runtime: nil,
            mqtt: mqtt,
            hub: MQTTMessageHub(mqtt: mqtt),
            teamID: "test-team",
            peerId: "test-peer"
        )
    }

    // NSMapTable with weak keys: the container lives as long as the VM does,
    // then both are released together when the test runner deallocates the VM.
    private static let _testStorage = NSMapTable<SessionDetailViewModel, ModelContainer>(
        keyOptions: .weakMemory, valueOptions: .strongMemory
    )

    /// Calls the private `handleIncomingChatMessage` via a per-VM in-memory
    /// ModelContainer whose lifetime is tied to this VM instance. Using a
    /// single retained container prevents the "model instance was destroyed"
    /// crash that occurred when a locally-scoped container was released before
    /// test assertions could read back inserted objects from `vm.events`.
    public func _test_handleIncomingChatMessage(_ message: Teamclaw_Message) {
        let container: ModelContainer
        if let existing = Self._testStorage.object(forKey: self) {
            container = existing
        } else {
            guard let fresh = try? ModelContainer(
                for: AgentEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) else { return }
            Self._testStorage.setObject(fresh, forKey: self)
            container = fresh
        }
        handleIncomingChatMessage(message, modelContext: container.mainContext)
    }

    /// Drive the post-load behaviour of `refreshMemberSheet` directly:
    /// set the agent roster + run the raw-runtime-id relabel pass. Lets
    /// tests exercise the bucket reconciliation without standing up a
    /// Supabase loader.
    public func _test_setMemberSheetAgentsAndRelabel(_ agents: [MemberSheetAgent]) {
        memberSheetAgents = agents
        relabelRawRuntimeIDStampsToActorIDs()
    }

    /// Append a raw event to in-memory `events` + `timelineState.entries`
    /// the same way the production live path would, without going through
    /// the reducer. Lets tests seed pre-memberSheet stamps.
    public func _test_appendRawEvent(senderActorID: String, eventType: String, text: String) {
        let event = AgentEvent(agentId: eventScopeKey, sequence: events.count + 1, eventType: eventType)
        event.senderActorID = senderActorID
        event.text = text
        events.append(event)
        timelineState.entries.append(TimelineEntry(
            id: event.id,
            sequence: UInt64(event.sequence),
            eventType: eventType,
            text: text,
            isComplete: false,
            senderActorID: senderActorID,
            timestamp: event.timestamp
        ))
    }

    /// Inject a streaming-buffer entry as if a live ACP output delta had
    /// landed under `bucket` before memberSheet finished loading.
    public func _test_seedStreamingBuffer(bucket: String, text: String, model: String? = nil) {
        timelineState.streamingAgentSet.insert(bucket)
        timelineState.streamingTextByAgent[bucket] = text
        if let model { timelineState.streamingModelByAgent[bucket] = model }
        streamingAgentSet = timelineState.streamingAgentSet
        streamingTextByAgent = timelineState.streamingTextByAgent
        streamingModelByAgent = timelineState.streamingModelByAgent
    }
}

extension SessionParticipant {
    public static func testFixture(actorID: String, role: String, displayName: String) -> SessionParticipant {
        SessionParticipant(actorID: actorID, role: role, displayName: displayName)
    }
}
#endif
