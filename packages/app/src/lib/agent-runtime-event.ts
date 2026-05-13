import { invoke } from "@tauri-apps/api/core";
import { isTauri } from "@/lib/utils";

export type AgentRuntimeEventRow = {
  id: string;
  sessionId: string;
  turnId?: string | null;
  senderActorId?: string | null;
  /** 'agent_tool_call' | 'agent_tool_result' | 'agent_thinking' */
  kind: string;
  content: string;
  metadataJson?: string | null;
  model?: string | null;
  createdAt: string; // ISO 8601
};

/**
 * Persist a non-canonical agent runtime event to the local libsql cache.
 * No-op outside Tauri. Errors are swallowed (caller logs).
 */
export async function insertAgentRuntimeEvent(
  row: AgentRuntimeEventRow,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("agent_runtime_event_insert", { record: row });
}

export async function loadAgentRuntimeEvents(
  sessionId: string,
): Promise<AgentRuntimeEventRow[]> {
  if (!isTauri()) return [];
  return await invoke<AgentRuntimeEventRow[]>("agent_runtime_event_load", {
    sessionId,
  });
}

export async function pruneAgentRuntimeEvents(maxRows = 5000): Promise<void> {
  if (!isTauri()) return;
  await invoke("agent_runtime_event_prune", { maxRows });
}
