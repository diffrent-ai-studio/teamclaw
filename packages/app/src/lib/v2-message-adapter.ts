// v2 → SDK message-shape adapter. The legacy MessageList expects the
// OpenCode SDK Message shape (id, role, parts[], toolCalls, timestamp,
// etc). v2 stores Teamclaw_Message (proto) in `useSessionStore.messages`.
//
// In addition to shape adaptation, this module groups consecutive
// same-turn agent messages into ONE SdkMessage so that the daemon's
// per-ACP-block firehose (one thinking row, one tool_call row, one
// tool_result row, one or more agent_reply rows — all sharing a
// turn_id) renders as a single coherent agent bubble.

import type { Message as TeamclawMessage } from "@/lib/proto/teamclaw_pb";
import { MessageKind } from "@/lib/proto/teamclaw_pb";
import type {
  Message as SdkMessage,
  MessagePart,
  ToolCall,
} from "@/stores/session-types";

function kindToRole(kind: MessageKind): SdkMessage["role"] {
  switch (kind) {
    case MessageKind.SYSTEM:
      return "system";
    case MessageKind.AGENT_THINKING:
    case MessageKind.AGENT_TOOL_CALL:
    case MessageKind.AGENT_TOOL_RESULT:
    case MessageKind.AGENT_REPLY:
      return "assistant";
    case MessageKind.TEXT:
    default:
      return "user";
  }
}

/** 1:1 mapping (legacy path) for messages without a turn_id or for
 * non-assistant roles. */
export function adaptTeamclawMessageToSdk(m: TeamclawMessage): SdkMessage {
  return {
    id: m.messageId,
    sessionId: m.sessionId,
    senderActorId: m.senderActorId,
    role: kindToRole(m.kind),
    content: m.content,
    modelID: m.model || undefined,
    parts: [
      {
        id: `${m.messageId}-p0`,
        type: "text",
        text: m.content,
        content: m.content,
      },
    ],
    toolCalls: [],
    timestamp: new Date(Number(m.createdAt) * 1000),
  };
}

/** Collapse a run of consecutive same-(senderActorId, turnId) assistant
 * messages into one SdkMessage. Thinking → reasoning part. Tool calls →
 * toolCalls[] matched with results by metadata.tool_id. Replies →
 * concatenated content. */
function buildTurnSdkMessage(group: TeamclawMessage[]): SdkMessage {
  const thinking = group.filter((m) => m.kind === MessageKind.AGENT_THINKING);
  const toolCallProtos = group.filter((m) => m.kind === MessageKind.AGENT_TOOL_CALL);
  const toolResultProtos = group.filter((m) => m.kind === MessageKind.AGENT_TOOL_RESULT);
  const replies = group.filter((m) => m.kind === MessageKind.AGENT_REPLY);

  const resultByToolId = new Map<string, { success: boolean; summary: string }>();
  for (const r of toolResultProtos) {
    try {
      const md = r.metadataJson ? (JSON.parse(r.metadataJson) as Record<string, unknown>) : {};
      const toolId = String(md.tool_id ?? "");
      if (toolId) {
        resultByToolId.set(toolId, {
          success: Boolean(md.success),
          summary: r.content,
        });
      }
    } catch {
      // malformed metadata — skip
    }
  }

  const toolCalls: ToolCall[] = toolCallProtos.map((tc) => {
    let toolId = "";
    let toolName = "unknown";
    let description = "";
    try {
      const md = tc.metadataJson ? (JSON.parse(tc.metadataJson) as Record<string, unknown>) : {};
      toolId = String(md.tool_id ?? "");
      toolName = String(md.tool_name ?? "unknown");
      description = String(md.description ?? "");
    } catch {
      // malformed metadata — leave defaults
    }
    const match = toolId ? resultByToolId.get(toolId) : undefined;
    return {
      id: toolId || tc.messageId,
      name: toolName,
      status: match ? (match.success ? "completed" : "failed") : "calling",
      arguments: description ? { _description: description } : {},
      startTime: new Date(Number(tc.createdAt) * 1000),
      result: match ? match.summary : undefined,
    };
  });

  const replyText = replies.map((r) => r.content).join("\n\n");
  const thinkingText = thinking.map((t) => t.content).join("\n");

  const groupId = replies[0]?.messageId ?? group[0].messageId;
  const parts: MessagePart[] = [];
  if (thinkingText) {
    parts.push({
      id: `${groupId}-r0`,
      type: "reasoning",
      text: thinkingText,
      content: thinkingText,
    });
  }
  parts.push({
    id: `${groupId}-p0`,
    type: "text",
    text: replyText,
    content: replyText,
  });

  // model: prefer last reply (most recent decision), fall back to any
  // message that carries one.
  const modelID =
    replies[replies.length - 1]?.model ||
    group.find((m) => m.model)?.model ||
    undefined;

  return {
    id: groupId,
    sessionId: group[0].sessionId,
    senderActorId: group[0].senderActorId,
    role: "assistant",
    content: replyText,
    modelID,
    parts,
    toolCalls,
    timestamp: new Date(Number(group[0].createdAt) * 1000),
  };
}

function groupByTurn(msgs: TeamclawMessage[]): SdkMessage[] {
  const out: SdkMessage[] = [];
  let i = 0;
  while (i < msgs.length) {
    const m = msgs[i];
    // Pass-through if no turnId (legacy / non-agent / user / system).
    if (!m.turnId || kindToRole(m.kind) !== "assistant") {
      out.push(adaptTeamclawMessageToSdk(m));
      i++;
      continue;
    }
    const turnId = m.turnId;
    const senderId = m.senderActorId;
    const group: TeamclawMessage[] = [];
    while (
      i < msgs.length &&
      msgs[i].turnId === turnId &&
      msgs[i].senderActorId === senderId
    ) {
      group.push(msgs[i]);
      i++;
    }
    out.push(buildTurnSdkMessage(group));
  }
  return out;
}

export function adaptTeamclawMessages(
  msgs: TeamclawMessage[] | undefined,
): SdkMessage[] | undefined {
  if (!msgs) return undefined;
  // Sort defensively — caller should already merge in createdAt order,
  // but local cache + supabase merge can interleave at the same epoch.
  const sorted = [...msgs].sort((a, b) => Number(a.createdAt - b.createdAt));
  return groupByTurn(sorted);
}
