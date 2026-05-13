import { describe, it, expect } from "vitest";
import { create } from "@bufbuild/protobuf";
import { MessageSchema, MessageKind } from "@/lib/proto/teamclaw_pb";
import { adaptTeamclawMessages } from "@/lib/v2-message-adapter";

// Simple counter for stable IDs in tests (avoids crypto.randomUUID dependency)
let _idCounter = 0;
function nextId() {
  return `msg-${++_idCounter}`;
}

function tmsg(o: {
  id?: string;
  senderActorId?: string;
  kind?: MessageKind;
  content?: string;
  metadataJson?: string;
  model?: string;
  turnId?: string;
  t?: number;
  sessionId?: string;
}) {
  return create(MessageSchema, {
    messageId: o.id ?? nextId(),
    sessionId: o.sessionId ?? "s1",
    senderActorId: o.senderActorId ?? "actor-a",
    kind: o.kind ?? MessageKind.AGENT_REPLY,
    content: o.content ?? "",
    metadataJson: o.metadataJson ?? "",
    model: o.model ?? "",
    turnId: o.turnId ?? "",
    createdAt: BigInt(o.t ?? 0),
  });
}

describe("adaptTeamclawMessages", () => {
  it("returns undefined when input is undefined", () => {
    expect(adaptTeamclawMessages(undefined)).toBeUndefined();
  });

  it("passes through messages with empty turnId 1:1 (legacy/non-agent)", () => {
    const msgs = [
      tmsg({ kind: MessageKind.TEXT, content: "hello", turnId: "" }),
      tmsg({ kind: MessageKind.TEXT, content: "world", turnId: "" }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(2);
    expect(result[0].content).toBe("hello");
    expect(result[1].content).toBe("world");
    expect(result[0].role).toBe("user");
  });

  it("passes through SYSTEM messages with turnId (kindToRole → not assistant)", () => {
    // SYSTEM is role 'system' not 'assistant', so it bypasses grouping
    const msgs = [
      tmsg({ kind: MessageKind.SYSTEM, content: "sys", turnId: "t1" }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);
    expect(result[0].role).toBe("system");
    expect(result[0].content).toBe("sys");
  });

  it("single AGENT_REPLY with turnId → single SdkMessage (same content)", () => {
    const id = nextId();
    const msgs = [
      tmsg({ id, kind: MessageKind.AGENT_REPLY, content: "hi", turnId: "t2", t: 1000 }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe(id);
    expect(result[0].content).toBe("hi");
    expect(result[0].role).toBe("assistant");
    expect(result[0].timestamp).toEqual(new Date(1000 * 1000));
  });

  it("thinking + 2 replies same turnId → one SdkMessage with joined content and reasoning part", () => {
    const msgs = [
      tmsg({ kind: MessageKind.AGENT_THINKING, content: "Let me think...", turnId: "t3", t: 1 }),
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "First part", turnId: "t3", t: 2 }),
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "Second part", turnId: "t3", t: 3 }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);

    const msg = result[0];
    expect(msg.content).toBe("First part\n\nSecond part");
    expect(msg.role).toBe("assistant");

    // reasoning part should be present
    const reasoningPart = msg.parts.find((p) => p.type === "reasoning");
    expect(reasoningPart).toBeDefined();
    expect(reasoningPart!.text).toBe("Let me think...");
    expect(reasoningPart!.content).toBe("Let me think...");

    // text part also present
    const textPart = msg.parts.find((p) => p.type === "text");
    expect(textPart).toBeDefined();
    expect(textPart!.text).toBe("First part\n\nSecond part");

    // timestamp is the earliest (group[0])
    expect(msg.timestamp).toEqual(new Date(1 * 1000));
  });

  it("tool_call + tool_result + reply same turnId → one SdkMessage with completed toolCall", () => {
    const toolId = "tool-xyz";
    const msgs = [
      tmsg({
        kind: MessageKind.AGENT_TOOL_CALL,
        content: "",
        metadataJson: JSON.stringify({ tool_id: toolId, tool_name: "bash", description: "run ls" }),
        turnId: "t4",
        t: 1,
      }),
      tmsg({
        kind: MessageKind.AGENT_TOOL_RESULT,
        content: "file1.txt\nfile2.txt",
        metadataJson: JSON.stringify({ tool_id: toolId, success: true }),
        turnId: "t4",
        t: 2,
      }),
      tmsg({
        kind: MessageKind.AGENT_REPLY,
        content: "Done listing files.",
        turnId: "t4",
        t: 3,
      }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);

    const msg = result[0];
    expect(msg.content).toBe("Done listing files.");
    expect(msg.toolCalls).toHaveLength(1);

    const tc = msg.toolCalls![0];
    expect(tc.id).toBe(toolId);
    expect(tc.name).toBe("bash");
    expect(tc.status).toBe("completed");
    expect(tc.result).toBe("file1.txt\nfile2.txt");
    expect(tc.arguments).toEqual({ _description: "run ls" });

    // No reasoning part
    expect(msg.parts.find((p) => p.type === "reasoning")).toBeUndefined();
  });

  it("tool_call without matching result → ToolCall with status 'calling'", () => {
    const msgs = [
      tmsg({
        kind: MessageKind.AGENT_TOOL_CALL,
        metadataJson: JSON.stringify({ tool_id: "t-orphan", tool_name: "search", description: "search web" }),
        turnId: "t5",
        t: 1,
      }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);

    const tc = result[0].toolCalls![0];
    expect(tc.status).toBe("calling");
    expect(tc.id).toBe("t-orphan");
    expect(tc.result).toBeUndefined();
  });

  it("mixed: messages with turnId collapse, messages without stay 1:1", () => {
    const userMsg = tmsg({ kind: MessageKind.TEXT, content: "user question", turnId: "", t: 1 });
    const agentReply1 = tmsg({ kind: MessageKind.AGENT_REPLY, content: "part A", turnId: "t6", t: 10 });
    const agentReply2 = tmsg({ kind: MessageKind.AGENT_REPLY, content: "part B", turnId: "t6", t: 11 });
    const anotherUser = tmsg({ kind: MessageKind.TEXT, content: "follow-up", turnId: "", t: 20 });

    const msgs = [userMsg, agentReply1, agentReply2, anotherUser];
    const result = adaptTeamclawMessages(msgs)!;

    // user + collapsed group + user = 3 messages
    expect(result).toHaveLength(3);
    expect(result[0].role).toBe("user");
    expect(result[0].content).toBe("user question");

    expect(result[1].role).toBe("assistant");
    expect(result[1].content).toBe("part A\n\npart B");

    expect(result[2].role).toBe("user");
    expect(result[2].content).toBe("follow-up");
  });

  it("different senderActorIds with same turnId are NOT merged (separate groups)", () => {
    // Same turnId but different senderActorId → each forms its own group
    const msgs = [
      tmsg({ senderActorId: "actor-a", kind: MessageKind.AGENT_REPLY, content: "from A", turnId: "t7", t: 1 }),
      tmsg({ senderActorId: "actor-b", kind: MessageKind.AGENT_REPLY, content: "from B", turnId: "t7", t: 2 }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(2);
    expect(result[0].content).toBe("from A");
    expect(result[1].content).toBe("from B");
  });

  it("no replies but has tool calls → SdkMessage with empty content and toolCalls[]", () => {
    const toolId = "t-call-only";
    const msgs = [
      tmsg({
        kind: MessageKind.AGENT_TOOL_CALL,
        metadataJson: JSON.stringify({ tool_id: toolId, tool_name: "write_file", description: "" }),
        turnId: "t8",
        t: 1,
      }),
      tmsg({
        kind: MessageKind.AGENT_TOOL_RESULT,
        content: "ok",
        metadataJson: JSON.stringify({ tool_id: toolId, success: false }),
        turnId: "t8",
        t: 2,
      }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);
    expect(result[0].content).toBe("");
    expect(result[0].toolCalls).toHaveLength(1);
    expect(result[0].toolCalls![0].status).toBe("failed");
  });

  it("modelID comes from the last AGENT_REPLY in the group", () => {
    const msgs = [
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "a", model: "model-old", turnId: "t9", t: 1 }),
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "b", model: "model-new", turnId: "t9", t: 2 }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);
    expect(result[0].modelID).toBe("model-new");
  });

  it("sorts messages by createdAt ascending before grouping", () => {
    // Provide messages out of order — after sort they should group correctly
    const msgs = [
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "second", turnId: "t10", t: 20 }),
      tmsg({ kind: MessageKind.AGENT_REPLY, content: "first", turnId: "t10", t: 10 }),
    ];
    const result = adaptTeamclawMessages(msgs)!;
    expect(result).toHaveLength(1);
    // earliest timestamp wins for the group timestamp
    expect(result[0].timestamp).toEqual(new Date(10 * 1000));
    // content joined in sorted order
    expect(result[0].content).toBe("first\n\nsecond");
  });
});
