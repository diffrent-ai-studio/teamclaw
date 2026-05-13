/**
 * session-sync.ts — Sync sessions from Supabase into local libsql cache.
 *
 * updated_at: ✓ present on sessions (confirmed via information_schema)
 * Watermark key: "sessions" namespaced by teamId.
 */

import { syncTableForTeam } from "@/lib/cache-sync";
import * as cache from "@/lib/local-cache";
import { isTauri } from "@/lib/utils";

// Supabase `sessions` columns: id, team_id, created_by_actor_id, primary_agent_id,
// mode, title, summary, last_message_preview, last_message_at, created_at,
// updated_at, idea_id. (No `created_by`, no `metadata_json`.)
interface SupabaseSessionRow {
  id: string;
  team_id: string;
  title?: string | null;
  mode?: string | null;
  primary_agent_id?: string | null;
  idea_id?: string | null;
  summary?: string | null;
  last_message_preview?: string | null;
  last_message_at?: string | null;
  created_by_actor_id?: string | null;
  created_at: string;
  updated_at: string;
}

const COLUMNS =
  "id, team_id, title, mode, primary_agent_id, idea_id, summary, last_message_preview, last_message_at, created_by_actor_id, created_at, updated_at";

function mapRow(r: SupabaseSessionRow): cache.SessionRow {
  return {
    id: r.id,
    teamId: r.team_id,
    title: r.title ?? null,
    mode: r.mode ?? null,
    primaryAgentId: r.primary_agent_id ?? null,
    ideaId: r.idea_id ?? null,
    summary: r.summary ?? null,
    lastMessagePreview: r.last_message_preview ?? null,
    lastMessageAt: r.last_message_at ?? null,
    createdBy: r.created_by_actor_id ?? null,
    metadataJson: null,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    deletedAt: null,
    syncedAt: new Date().toISOString(),
  };
}

/**
 * Pull sessions for a team from Supabase (delta or full),
 * upsert into local cache, bump watermark.
 *
 * @returns number of rows synced
 */
export async function syncSessionsForTeam(
  teamId: string,
  opts?: { full?: boolean },
): Promise<number> {
  if (!isTauri()) return 0;
  const { count } = await syncTableForTeam<SupabaseSessionRow, cache.SessionRow>({
    tableName: "sessions",
    teamId,
    selectColumns: COLUMNS,
    mapRow,
    upsertBatch: cache.upsertSessionsBatch,
    full: opts?.full,
  });
  return count;
}
