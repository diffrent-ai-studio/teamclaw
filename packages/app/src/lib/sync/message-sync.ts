/**
 * message-sync.ts — Sync messages from Supabase into local libsql cache.
 *
 * updated_at: ✓ present on messages (confirmed via information_schema)
 * Watermark key: "messages:<sessionId>" namespaced by teamId.
 *
 * Origin is set to "supabase" for all rows pulled from Supabase.
 * MQTT-live messages are written with origin="mqtt-live" directly in the
 * envelope handler in App.tsx.
 */

import { syncTableForSession } from "@/lib/cache-sync";
import * as cache from "@/lib/local-cache";
import { isTauri } from "@/lib/utils";

// Supabase column on public.messages is `metadata` (jsonb), not `metadata_json`.
// We stringify it into local libsql's metadata_json TEXT column.
interface SupabaseMessageRow {
  id: string;
  team_id: string;
  session_id: string;
  turn_id?: string | null;
  sender_actor_id?: string | null;
  reply_to_message_id?: string | null;
  kind: string;
  content: string;
  metadata?: unknown | null;
  model?: string | null;
  created_at: string;
  updated_at: string;
}

const COLUMNS =
  "id, team_id, session_id, turn_id, sender_actor_id, reply_to_message_id, kind, content, metadata, model, created_at, updated_at";

function mapRow(r: SupabaseMessageRow): cache.MessageRow {
  const metadataJson =
    r.metadata == null
      ? null
      : typeof r.metadata === "string"
        ? r.metadata
        : JSON.stringify(r.metadata);
  return {
    id: r.id,
    teamId: r.team_id,
    sessionId: r.session_id,
    turnId: r.turn_id ?? null,
    senderActorId: r.sender_actor_id ?? null,
    replyToMessageId: r.reply_to_message_id ?? null,
    kind: r.kind,
    content: r.content ?? "",
    metadataJson,
    model: r.model ?? null,
    mentionsJson: null,
    origin: "supabase",
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    deletedAt: null,
    syncedAt: new Date().toISOString(),
  };
}

/**
 * Pull messages for a session from Supabase (delta or full),
 * upsert into local cache, bump per-session watermark.
 *
 * @returns number of rows synced
 */
export async function syncMessagesForSession(
  sessionId: string,
  teamId: string,
  opts?: { full?: boolean },
): Promise<number> {
  if (!isTauri()) return 0;
  const { count } = await syncTableForSession<
    SupabaseMessageRow,
    cache.MessageRow
  >({
    tableName: "messages",
    sessionId,
    teamId,
    selectColumns: COLUMNS,
    mapRow,
    upsertBatch: cache.upsertMessagesBatch,
    full: opts?.full,
  });
  return count;
}
