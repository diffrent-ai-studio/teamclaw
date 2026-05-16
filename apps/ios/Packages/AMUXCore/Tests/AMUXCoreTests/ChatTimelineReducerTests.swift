import Testing
import Foundation
@testable import AMUXCore

// MARK: - ChatTimelineReducer fixture tests
//
// These tests pin the seven in-place mutation cases documented in
// `TimelineInput.swift` against synthetic inputs. They run without
// SwiftData / MQTT / SwiftUI; the reducer is a pure function over a
// value-type `TimelineState`.
//
// When the production migration off the inline SessionDetailViewModel
// handler lands (Phase 4 main), these scenarios should still pass
// against any recorded session traces — see project_phase4_status.md.

@Suite("ChatTimelineReducer — streaming output (case 1)")
struct ReducerStreamingOutputTests {
    @Test("first delta opens the stream and seeds the per-agent buffer")
    func firstDeltaOpensStream() {
        var state = TimelineState()
        var acp = Amux_AcpEvent()
        acp.event = .output(makeOutput(text: "Hel", isComplete: false))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt-1",
                          agentBucketKey: "agent-1", timestamp: .now,
                          acpEvent: acp)),
            to: &state
        )
        #expect(state.streamingAgentSet.contains("agent-1"))
        #expect(state.streamingTextByAgent["agent-1"] == "Hel")
        #expect(state.entries.isEmpty,
                "streaming deltas don't create entries until finalised")
    }

    @Test("subsequent deltas append onto the open stream's buffer")
    func deltasAppend() {
        var state = TimelineState()
        for chunk in ["Hel", "lo,", " world"] {
            var acp = Amux_AcpEvent()
            acp.event = .output(makeOutput(text: chunk, isComplete: false))
            ChatTimelineReducer.apply(
                .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt-1",
                              agentBucketKey: "agent-1", timestamp: .now,
                              acpEvent: acp)),
                to: &state
            )
        }
        #expect(state.streamingTextByAgent["agent-1"] == "Hello, world")
    }

    @Test("complete output finalises the stream and clears the buffer")
    func completeFinalises() {
        var state = TimelineState()
        // Seed an open stream.
        var delta = Amux_AcpEvent()
        delta.event = .output(makeOutput(text: "Hel", isComplete: false))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt-1",
                          agentBucketKey: "agent-1", timestamp: .now,
                          acpEvent: delta)),
            to: &state
        )
        // Final.
        var done = Amux_AcpEvent()
        done.event = .output(makeOutput(text: "Hello, world", isComplete: true))
        done.model = "claude-opus-4-7"
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt-1",
                          agentBucketKey: "agent-1", timestamp: .now,
                          acpEvent: done)),
            to: &state
        )
        #expect(!state.streamingAgentSet.contains("agent-1"))
        #expect(state.streamingTextByAgent["agent-1"] == nil)
        #expect(state.entries.count == 1)
        #expect(state.entries[0].text == "Hello, world")
        #expect(state.entries[0].isComplete)
        #expect(state.entries[0].model == "claude-opus-4-7")
    }

    @Test("two agents stream concurrently without bucket cross-contamination")
    func concurrentBuckets() {
        var state = TimelineState()
        var aDelta = Amux_AcpEvent()
        aDelta.event = .output(makeOutput(text: "A: ", isComplete: false))
        var bDelta = Amux_AcpEvent()
        bDelta.event = .output(makeOutput(text: "B: ", isComplete: false))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt-a",
                          agentBucketKey: "agent-a", timestamp: .now,
                          acpEvent: aDelta)),
            to: &state
        )
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt-b",
                          agentBucketKey: "agent-b", timestamp: .now,
                          acpEvent: bDelta)),
            to: &state
        )
        var aDelta2 = Amux_AcpEvent()
        aDelta2.event = .output(makeOutput(text: "hi", isComplete: false))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 3, runtimeID: "rt-a",
                          agentBucketKey: "agent-a", timestamp: .now,
                          acpEvent: aDelta2)),
            to: &state
        )
        #expect(state.streamingTextByAgent["agent-a"] == "A: hi")
        #expect(state.streamingTextByAgent["agent-b"] == "B: ",
                "second agent's buffer must not be touched by agent-a's deltas")
    }
}

@Suite("ChatTimelineReducer — tool result pairing (case 2)")
struct ReducerToolResultPairingTests {
    @Test("toolResult pairs with prior toolUse by toolID and marks it complete")
    func pairsWithPriorToolUse() {
        var state = TimelineState()
        var use = Amux_AcpEvent()
        use.event = .toolUse(makeToolUse(toolID: "t-1", toolName: "Read", description: "reading"))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: use)),
            to: &state
        )
        var result = Amux_AcpEvent()
        result.event = .toolResult(makeToolResult(toolID: "t-1", success: true, summary: "ok"))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: result)),
            to: &state
        )
        #expect(state.entries.count == 1, "tool_use stays as the single entry; tool_result lands in place")
        #expect(state.entries[0].eventType == "tool_use")
        #expect(state.entries[0].isComplete)
        #expect(state.entries[0].success == true)
    }

    @Test("out-of-order toolResult appends a standalone entry")
    func outOfOrderToolResult() {
        var state = TimelineState()
        var result = Amux_AcpEvent()
        result.event = .toolResult(makeToolResult(toolID: "t-orphan", success: false, summary: "fail"))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: result)),
            to: &state
        )
        #expect(state.entries.count == 1)
        #expect(state.entries[0].eventType == "tool_result")
    }
}

@Suite("ChatTimelineReducer — todo replace (case 3)")
struct ReducerTodoReplaceTests {
    @Test("a second todo_update replaces the first entry's text in place")
    func replacesInPlace() {
        var state = TimelineState()
        var first = Amux_AcpEvent()
        first.event = .todoUpdate(makeTodoUpdate([("plan", .pending)]))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: first)),
            to: &state
        )
        var second = Amux_AcpEvent()
        second.event = .todoUpdate(makeTodoUpdate([("plan", .completed),
                                                   ("ship", .inProgress)]))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: second)),
            to: &state
        )
        #expect(state.entries.count == 1,
                "todo_update is a snapshot replacement, not an append")
        #expect(state.entries[0].text?.contains("[done] plan") == true)
        #expect(state.entries[0].text?.contains("[wip] ship") == true)
    }
}

@Suite("ChatTimelineReducer — permission resolve (case 4)")
struct ReducerPermissionResolveTests {
    @Test("resolution updates the matching permission_request in place")
    func updatesInPlace() {
        var state = TimelineState()
        var request = Amux_AcpEvent()
        request.event = .permissionRequest(makePermissionRequest(requestID: "p-1",
                                                                 toolName: "Bash",
                                                                 description: "rm -rf /"))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: request)),
            to: &state
        )
        ChatTimelineReducer.apply(
            .permissionResolution(PermissionResolutionInput(requestID: "p-1", granted: false)),
            to: &state
        )
        #expect(state.entries.count == 1)
        #expect(state.entries[0].eventType == "permission_request")
        #expect(state.entries[0].isComplete)
        #expect(state.entries[0].success == false)
    }

    @Test("resolution without a matching request is dropped silently")
    func orphanResolutionDropped() {
        var state = TimelineState()
        ChatTimelineReducer.apply(
            .permissionResolution(PermissionResolutionInput(requestID: "p-orphan", granted: true)),
            to: &state
        )
        #expect(state.entries.isEmpty)
    }
}

@Suite("ChatTimelineReducer — status change idle flush (case 5)")
struct ReducerStatusChangeIdleTests {
    @Test("idle status flushes the open stream buffer to a final output entry")
    func idleFlushesBuffer() {
        var state = TimelineState()
        var delta = Amux_AcpEvent()
        delta.event = .output(makeOutput(text: "partial", isComplete: false))
        delta.model = "claude-sonnet-4-6"
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: delta)),
            to: &state
        )
        var idle = Amux_AcpEvent()
        idle.event = .statusChange(makeStatusChange(.idle))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: idle)),
            to: &state
        )
        #expect(state.entries.count == 1)
        #expect(state.entries[0].eventType == "output")
        #expect(state.entries[0].text == "partial")
        #expect(state.entries[0].isComplete)
        #expect(state.entries[0].model == "claude-sonnet-4-6")
        #expect(state.streamingAgentSet.isEmpty)
    }

    @Test("idle for one agent leaves the other agent's stream open")
    func idleIsBucketScoped() {
        var state = TimelineState()
        var aDelta = Amux_AcpEvent()
        aDelta.event = .output(makeOutput(text: "a", isComplete: false))
        var bDelta = Amux_AcpEvent()
        bDelta.event = .output(makeOutput(text: "b", isComplete: false))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt-a",
                          agentBucketKey: "agent-a", timestamp: .now,
                          acpEvent: aDelta)),
            to: &state
        )
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 2, runtimeID: "rt-b",
                          agentBucketKey: "agent-b", timestamp: .now,
                          acpEvent: bDelta)),
            to: &state
        )
        var idleA = Amux_AcpEvent()
        idleA.event = .statusChange(makeStatusChange(.idle))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 3, runtimeID: "rt-a",
                          agentBucketKey: "agent-a", timestamp: .now,
                          acpEvent: idleA)),
            to: &state
        )
        #expect(!state.streamingAgentSet.contains("agent-a"))
        #expect(state.streamingAgentSet.contains("agent-b"),
                "agent-b's stream must survive agent-a's idle")
    }
}

@Suite("ChatTimelineReducer — local prompt + live echo merge (case 6)")
struct ReducerLocalEchoMergeTests {
    @Test("local prompt creates an entry that the live echo merges into")
    func localEchoMerges() {
        var state = TimelineState()
        let clientID = "client-uuid-xyz"
        ChatTimelineReducer.apply(
            .localPrompt(LocalPromptInput(clientID: clientID,
                                          senderActorID: "user-1",
                                          content: "hi",
                                          createdAt: Date(timeIntervalSince1970: 100))),
            to: &state
        )
        #expect(state.entries.count == 1)
        #expect(state.entries[0].clientID == clientID)

        ChatTimelineReducer.apply(
            .liveMessage(LiveMessageInput(messageID: "msg-server-1",
                                          clientLocalID: clientID,
                                          senderActorID: "user-1",
                                          content: "hi",
                                          createdAt: Date(timeIntervalSince1970: 101))),
            to: &state
        )
        #expect(state.entries.count == 1, "no duplicate entry from the live echo")
        #expect(state.entries[0].id == "msg-server-1",
                "id swaps to the server-assigned messageID")
        #expect(state.entries[0].clientID == nil,
                "clientID is cleared once the server id takes over")
    }

    @Test("live message without a matching clientLocalID appends a new entry")
    func liveMessageWithoutMergeAppends() {
        var state = TimelineState()
        ChatTimelineReducer.apply(
            .liveMessage(LiveMessageInput(messageID: "msg-1",
                                          clientLocalID: nil,
                                          senderActorID: "user-2",
                                          content: "another user",
                                          createdAt: Date())),
            to: &state
        )
        #expect(state.entries.count == 1)
        #expect(state.entries[0].id == "msg-1")
    }
}

@Suite("ChatTimelineReducer — history + live cross-dedupe (case 7)")
struct ReducerHistoryCrossDedupeTests {
    @Test("history seed backfills supabaseMessageID onto a matching live entry")
    func backfillsExistingEntry() {
        var state = TimelineState()
        // Live stream completes first.
        var done = Amux_AcpEvent()
        done.event = .output(makeOutput(text: "Hello", isComplete: true))
        ChatTimelineReducer.apply(
            .acp(AcpInput(envelopeSequence: 1, runtimeID: "rt",
                          agentBucketKey: "agent", timestamp: .now,
                          acpEvent: done)),
            to: &state
        )
        // History seed arrives later for the same turn.
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-1",
                                         kind: .output,
                                         senderActorID: "agent",
                                         content: "Hello",
                                         createdAt: .now)),
            to: &state
        )
        #expect(state.entries.count == 1,
                "history seed must not insert a duplicate output entry")
        #expect(state.entries[0].supabaseMessageID == "sb-1")
    }

    @Test("history seed merges local prompt by outbox id before content")
    func historyMergesLocalPromptByOutboxId() {
        var state = TimelineState(entries: [
            TimelineEntry(
                eventType: "user_prompt",
                text: "same",
                isComplete: true,
                senderActorID: "user-1",
                timestamp: Date(timeIntervalSince1970: 1),
                outboxMessageID: "msg-old"
            ),
            TimelineEntry(
                eventType: "user_prompt",
                text: "same",
                isComplete: true,
                senderActorID: "user-1",
                timestamp: Date(timeIntervalSince1970: 2),
                outboxMessageID: "msg-new"
            )
        ])

        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "msg-new",
                                         kind: .userPrompt,
                                         senderActorID: "user-1",
                                         content: "same",
                                         createdAt: Date(timeIntervalSince1970: 3))),
            to: &state
        )

        #expect(state.entries.count == 2)
        #expect(state.entries[0].supabaseMessageID == nil)
        #expect(state.entries[1].supabaseMessageID == "msg-new")
    }

    @Test("re-seeding the same supabase id is idempotent")
    func reSeedIdempotent() {
        var state = TimelineState()
        let input = HistoryInput(supabaseMessageID: "sb-1",
                                 kind: .userPrompt,
                                 senderActorID: "user-1",
                                 content: "hi",
                                 createdAt: .now)
        ChatTimelineReducer.apply(.historyMessage(input), to: &state)
        ChatTimelineReducer.apply(.historyMessage(input), to: &state)
        #expect(state.entries.count == 1)
    }
}

// MARK: - turn_id history merge (case 8)

@Suite("ChatTimelineReducer — history same-turn merge (case 8)")
struct ReducerHistoryTurnMergeTests {
    @Test("two AgentReply rows with same turn_id merge into one bubble")
    func sameTurnMergesIntoOneEntry() {
        var state = TimelineState()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        // First flush (mid-turn ToolUse cut).
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-1",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "I'll use the Read tool. ",
                                          createdAt: t0,
                                          turnID: "turn-A")),
            to: &state
        )
        // Second flush (Active→Idle continuation).
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-2",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "Now I see — the answer is 42.",
                                          createdAt: t1,
                                          turnID: "turn-A")),
            to: &state
        )
        #expect(state.entries.count == 1, "same turnID rows must merge")
        #expect(state.entries[0].text == "I'll use the Read tool. Now I see — the answer is 42.")
        #expect(state.entries[0].turnID == "turn-A")
    }

    @Test("different turn_id keeps rows separate")
    func differentTurnStaysSeparate() {
        var state = TimelineState()
        let t0 = Date(timeIntervalSince1970: 2_000)
        let t1 = Date(timeIntervalSince1970: 2_001)
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-a",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "first turn reply",
                                          createdAt: t0,
                                          turnID: "turn-X")),
            to: &state
        )
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-b",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "second turn reply",
                                          createdAt: t1,
                                          turnID: "turn-Y")),
            to: &state
        )
        #expect(state.entries.count == 2, "distinct turnIDs must not merge")
    }

    @Test("nil turn_id falls back to per-row entries (legacy rows)")
    func nilTurnIDFallsBack() {
        var state = TimelineState()
        let t0 = Date(timeIntervalSince1970: 3_000)
        let t1 = Date(timeIntervalSince1970: 3_001)
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-old-1",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "old row 1",
                                          createdAt: t0,
                                          turnID: nil)),
            to: &state
        )
        ChatTimelineReducer.apply(
            .historyMessage(HistoryInput(supabaseMessageID: "sb-old-2",
                                          kind: .output,
                                          senderActorID: "agent",
                                          content: "old row 2",
                                          createdAt: t1,
                                          turnID: nil)),
            to: &state
        )
        #expect(state.entries.count == 2,
                "nil turnID must not collapse legacy rows together")
    }
}

// MARK: - Helpers building Amux_AcpEvent sub-payloads

private func makeOutput(text: String, isComplete: Bool) -> Amux_AcpOutput {
    var o = Amux_AcpOutput()
    o.text = text
    o.isComplete = isComplete
    return o
}

private func makeToolUse(toolID: String, toolName: String, description: String) -> Amux_AcpToolUse {
    var t = Amux_AcpToolUse()
    t.toolID = toolID
    t.toolName = toolName
    t.description_p = description
    return t
}

private func makeToolResult(toolID: String, success: Bool, summary: String) -> Amux_AcpToolResult {
    var r = Amux_AcpToolResult()
    r.toolID = toolID
    r.success = success
    r.summary = summary
    return r
}

private func makePermissionRequest(requestID: String, toolName: String, description: String) -> Amux_AcpPermissionRequest {
    var p = Amux_AcpPermissionRequest()
    p.requestID = requestID
    p.toolName = toolName
    p.description_p = description
    return p
}

private func makeStatusChange(_ newStatus: Amux_AgentStatus) -> Amux_AcpStatusChange {
    var s = Amux_AcpStatusChange()
    s.newStatus = newStatus
    return s
}

private func makeTodoUpdate(_ items: [(String, Amux_TodoItem.Status)]) -> Amux_AcpTodoUpdate {
    var u = Amux_AcpTodoUpdate()
    u.items = items.map { content, status in
        var i = Amux_TodoItem()
        i.content = content
        i.status = status
        return i
    }
    return u
}
