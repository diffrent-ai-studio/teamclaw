import { create } from "zustand";
import type { ToolCall } from "@/stores/session-types";

export interface StreamingTodoItem {
  content: string;
  status: "pending" | "in_progress" | "completed";
}

export interface StreamingPermissionRequest {
  requestId: string;
  toolName: string;
  description: string;
  params: Record<string, string>;
}

export interface AgentStreamEntry {
  sessionId: string;
  actorId: string;
  outputText: string;           // accumulated output deltas, or final content after finalize
  thinkingText: string;         // accumulated thinking deltas
  toolCalls: ToolCall[];        // pushed on AcpToolUse, completed on AcpToolResult
  todos: StreamingTodoItem[];   // replaced wholesale on AcpTodoUpdate
  pendingPermission: StreamingPermissionRequest | null; // set on AcpPermissionRequest
  errorMessage: string | null;  // set on AcpError
  errorDetails: string | null;
  lastUpdate: number;           // ms epoch
  active: boolean;              // true while streaming; false after finalize
}

interface State {
  byKey: Record<string, AgentStreamEntry>;
  appendOutput: (sessionId: string, actorId: string, delta: string) => void;
  appendThinking: (sessionId: string, actorId: string, delta: string) => void;
  pushToolUse: (
    sessionId: string,
    actorId: string,
    args: { toolId: string; toolName: string; description: string; params: Record<string, string> },
  ) => void;
  completeToolUse: (
    sessionId: string,
    actorId: string,
    args: { toolId: string; success: boolean; summary: string },
  ) => void;
  setTodos: (sessionId: string, actorId: string, items: StreamingTodoItem[]) => void;
  setError: (sessionId: string, actorId: string, message: string, details: string) => void;
  setPermissionRequest: (
    sessionId: string,
    actorId: string,
    req: StreamingPermissionRequest,
  ) => void;
  clearPermissionRequest: (sessionId: string, actorId: string) => void;
  finalize: (sessionId: string, actorId: string, finalText: string) => void;
  clearActor: (sessionId: string, actorId: string) => void;
  clearSession: (sessionId: string) => void;
}

function k(sessionId: string, actorId: string): string {
  return `${sessionId}::${actorId}`;
}

function emptyEntry(sessionId: string, actorId: string): AgentStreamEntry {
  return {
    sessionId,
    actorId,
    outputText: "",
    thinkingText: "",
    toolCalls: [],
    todos: [],
    pendingPermission: null,
    errorMessage: null,
    errorDetails: null,
    lastUpdate: Date.now(),
    active: true,
  };
}

/** Get the entry to mutate. If a previous-turn entry exists but is inactive
 * (finalized), reset it for the new turn so we don't accumulate state
 * across turns. */
function activeEntry(state: State, sessionId: string, actorId: string): AgentStreamEntry {
  const key = k(sessionId, actorId);
  const existing = state.byKey[key];
  if (!existing || !existing.active) return emptyEntry(sessionId, actorId);
  return existing;
}

export const useV2StreamingStore = create<State>((set, get) => ({
  byKey: {},

  appendOutput: (sessionId, actorId, delta) => {
    if (!delta) return;
    const entry = activeEntry(get(), sessionId, actorId);
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          outputText: entry.outputText + delta,
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  appendThinking: (sessionId, actorId, delta) => {
    if (!delta) return;
    const entry = activeEntry(get(), sessionId, actorId);
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          thinkingText: entry.thinkingText + delta,
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  pushToolUse: (sessionId, actorId, { toolId, toolName, description, params }) => {
    if (!toolId) return;
    const entry = activeEntry(get(), sessionId, actorId);
    if (entry.toolCalls.some((tc) => tc.id === toolId)) return;
    const newToolCall: ToolCall = {
      id: toolId,
      name: toolName || "unknown",
      status: "calling",
      arguments: { ...(params ?? {}), ...(description ? { _description: description } : {}) },
      startTime: new Date(),
    };
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          toolCalls: [...entry.toolCalls, newToolCall],
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  completeToolUse: (sessionId, actorId, { toolId, success, summary }) => {
    if (!toolId) return;
    const key = k(sessionId, actorId);
    const existing = get().byKey[key];
    if (!existing) return;
    const updated = existing.toolCalls.map((tc) =>
      tc.id === toolId
        ? {
            ...tc,
            status: success ? ("completed" as const) : ("failed" as const),
            result: summary,
            duration: Date.now() - tc.startTime.getTime(),
          }
        : tc,
    );
    set({
      byKey: {
        ...get().byKey,
        [key]: {
          ...existing,
          toolCalls: updated,
          lastUpdate: Date.now(),
        },
      },
    });
  },

  setTodos: (sessionId, actorId, items) => {
    const entry = activeEntry(get(), sessionId, actorId);
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          todos: items,
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  setError: (sessionId, actorId, message, details) => {
    const entry = activeEntry(get(), sessionId, actorId);
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          errorMessage: message,
          errorDetails: details,
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  setPermissionRequest: (sessionId, actorId, req) => {
    const entry = activeEntry(get(), sessionId, actorId);
    set({
      byKey: {
        ...get().byKey,
        [k(sessionId, actorId)]: {
          ...entry,
          pendingPermission: req,
          lastUpdate: Date.now(),
          active: true,
        },
      },
    });
  },

  clearPermissionRequest: (sessionId, actorId) => {
    const key = k(sessionId, actorId);
    const existing = get().byKey[key];
    if (!existing) return;
    set({
      byKey: {
        ...get().byKey,
        [key]: { ...existing, pendingPermission: null, lastUpdate: Date.now() },
      },
    });
  },

  /** Finalize a streaming turn: replace outputText with the canonical final
   * content from the daemon's published Message and mark inactive. Keep
   * thinking + tool_calls + todos visible. The next turn's first
   * acp.event will reset the entry via activeEntry()'s inactive-check. */
  finalize: (sessionId, actorId, finalText) => {
    const key = k(sessionId, actorId);
    const existing = get().byKey[key];
    if (!existing) {
      // No prior streaming for this actor — create a finalized stub so the
      // bubble still renders the reply text consistently. (Rare; usually
      // the daemon emits acp.event before message.created.)
      set({
        byKey: {
          ...get().byKey,
          [key]: {
            ...emptyEntry(sessionId, actorId),
            outputText: finalText,
            active: false,
          },
        },
      });
      return;
    }
    set({
      byKey: {
        ...get().byKey,
        [key]: {
          ...existing,
          outputText: finalText || existing.outputText,
          lastUpdate: Date.now(),
          active: false,
        },
      },
    });
  },

  clearActor: (sessionId, actorId) => {
    const key = k(sessionId, actorId);
    const next = { ...get().byKey };
    delete next[key];
    set({ byKey: next });
  },

  clearSession: (sessionId) => {
    const next: Record<string, AgentStreamEntry> = {};
    for (const [key, entry] of Object.entries(get().byKey)) {
      if (entry.sessionId !== sessionId) next[key] = entry;
    }
    set({ byKey: next });
  },
}));

/** Selector helper: get all streaming entries for a session (active + finalized). */
export function selectStreamsForSession(state: State, sessionId: string): AgentStreamEntry[] {
  return Object.values(state.byKey).filter((e) => e.sessionId === sessionId);
}
