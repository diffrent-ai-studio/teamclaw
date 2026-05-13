import { invoke } from "@tauri-apps/api/core";
import { isTauri } from "@/lib/utils";

// ── Row types (mirror Rust serde shape, camelCase) ─────────────────────────

export type ActorRow = {
  id: string;
  teamId: string;
  actorType: string;
  displayName: string;
  avatarUrl?: string | null;
  memberStatus?: string | null;
  agentStatus?: string | null;
  metadataJson?: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type SessionRow = {
  id: string;
  teamId: string;
  title?: string | null;
  mode?: string | null;
  primaryAgentId?: string | null;
  ideaId?: string | null;
  summary?: string | null;
  lastMessagePreview?: string | null;
  lastMessageAt?: string | null;
  createdBy?: string | null;
  metadataJson?: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type SessionParticipantRow = {
  id: string;
  sessionId: string;
  actorId: string;
  joinedAt?: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type MessageRow = {
  id: string;
  teamId: string;
  sessionId: string;
  turnId?: string | null;
  senderActorId?: string | null;
  replyToMessageId?: string | null;
  kind: string;
  content: string;
  metadataJson?: string | null;
  model?: string | null;
  mentionsJson?: string | null;
  /** 'supabase' | 'mqtt-live' | 'local-only' */
  origin: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type IdeaRow = {
  id: string;
  teamId: string;
  workspaceId?: string | null;
  parentId?: string | null;
  title: string;
  description?: string | null;
  status?: string | null;
  createdBy?: string | null;
  archived: number;
  metadataJson?: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type ClaimRow = {
  id: string;
  ideaId: string;
  actorId: string;
  claimedAt: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

export type SubmissionRow = {
  id: string;
  ideaId: string;
  actorId: string;
  content?: string | null;
  submittedAt: string;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  syncedAt: string;
};

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
  createdAt: string;
};

// ── actor ──────────────────────────────────────────────────────────────────

export async function upsertActorsBatch(rows: ActorRow[]): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_actor_upsert_batch", { rows });
}

export async function loadActorsForTeam(
  teamId: string,
  includeDeleted = false,
): Promise<ActorRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_actor_load_team", { teamId, includeDeleted });
}

export async function softDeleteActor(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_actor_soft_delete", { id, deletedAt });
}

// ── session ────────────────────────────────────────────────────────────────

export async function upsertSessionsBatch(rows: SessionRow[]): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_session_upsert_batch", { rows });
}

export async function loadSessionsForTeam(
  teamId: string,
  includeDeleted = false,
): Promise<SessionRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_session_load_team", { teamId, includeDeleted });
}

export async function softDeleteSession(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_session_soft_delete", { id, deletedAt });
}

// ── session_participant ────────────────────────────────────────────────────

export async function upsertSessionParticipantsBatch(
  rows: SessionParticipantRow[],
): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_session_participant_upsert_batch", { rows });
}

export async function loadSessionParticipants(
  sessionId: string,
  includeDeleted = false,
): Promise<SessionParticipantRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_session_participant_load_session", {
    sessionId,
    includeDeleted,
  });
}

export async function softDeleteSessionParticipant(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_session_participant_soft_delete", { id, deletedAt });
}

// ── message ────────────────────────────────────────────────────────────────

export async function upsertMessagesBatch(rows: MessageRow[]): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_message_upsert_batch", { rows });
}

export async function loadMessagesForSession(
  sessionId: string,
  includeDeleted = false,
): Promise<MessageRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_message_load_session", {
    sessionId,
    includeDeleted,
  });
}

export async function softDeleteMessage(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_message_soft_delete", { id, deletedAt });
}

// ── idea ───────────────────────────────────────────────────────────────────

export async function upsertIdeasBatch(rows: IdeaRow[]): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_idea_upsert_batch", { rows });
}

export async function loadIdeasForTeam(
  teamId: string,
  includeDeleted = false,
): Promise<IdeaRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_idea_load_team", { teamId, includeDeleted });
}

export async function softDeleteIdea(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_idea_soft_delete", { id, deletedAt });
}

// ── claim ──────────────────────────────────────────────────────────────────

export async function upsertClaimsBatch(rows: ClaimRow[]): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_claim_upsert_batch", { rows });
}

export async function loadClaimsForIdea(
  ideaId: string,
  includeDeleted = false,
): Promise<ClaimRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_claim_load_idea", { ideaId, includeDeleted });
}

export async function softDeleteClaim(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_claim_soft_delete", { id, deletedAt });
}

// ── submission ─────────────────────────────────────────────────────────────

export async function upsertSubmissionsBatch(
  rows: SubmissionRow[],
): Promise<void> {
  if (!isTauri() || rows.length === 0) return;
  await invoke("local_cache_submission_upsert_batch", { rows });
}

export async function loadSubmissionsForIdea(
  ideaId: string,
  includeDeleted = false,
): Promise<SubmissionRow[]> {
  if (!isTauri()) return [];
  return invoke("local_cache_submission_load_idea", { ideaId, includeDeleted });
}

export async function softDeleteSubmission(
  id: string,
  deletedAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_submission_soft_delete", { id, deletedAt });
}

// ── sync watermark ─────────────────────────────────────────────────────────

export async function getWatermark(
  tableName: string,
  teamId: string,
): Promise<string | null> {
  if (!isTauri()) return null;
  const res = await invoke<string | null>("local_cache_watermark_get", {
    tableName,
    teamId,
  });
  return res ?? null;
}

export async function setWatermark(
  tableName: string,
  teamId: string,
  lastSyncAt: string,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_watermark_set", { tableName, teamId, lastSyncAt });
}

// ── clear_team ─────────────────────────────────────────────────────────────

export async function clearTeam(teamId: string): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_clear_team", { teamId });
}

// ── Backwards-compat re-exports for agent runtime event cache callers ───────
// The narrow API is preserved; long-term these callers will migrate
// to the generic upsert/load pattern.

export async function insertAgentRuntimeEvent(
  row: AgentRuntimeEventRow,
): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_agent_runtime_event_insert", { record: row });
}

export async function loadAgentRuntimeEvents(
  sessionId: string,
): Promise<AgentRuntimeEventRow[]> {
  if (!isTauri()) return [];
  return invoke<AgentRuntimeEventRow[]>(
    "local_cache_agent_runtime_event_load",
    { sessionId },
  );
}

export async function pruneAgentRuntimeEvents(maxRows = 5000): Promise<void> {
  if (!isTauri()) return;
  await invoke("local_cache_agent_runtime_event_prune", { maxRows });
}
