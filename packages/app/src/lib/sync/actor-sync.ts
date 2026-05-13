/**
 * actor-sync.ts — Sync actor_directory from Supabase into local libsql cache.
 *
 * Uses the `actor_directory` view (joined view the frontend already queries)
 * because it exposes actor_type, display_name, member_status, agent_status,
 * and avatar_url in one SELECT.
 *
 * updated_at: ✓ present on actor_directory (confirmed via information_schema)
 */

import { supabase } from "@/lib/supabase-client";
import * as cache from "@/lib/local-cache";
import { isTauri } from "@/lib/utils";

// The Supabase row shape from actor_directory.
// NOTE: actor_directory has no avatar_url column — that lives on a separate
// member/agent extension table not surfaced by the view.
interface ActorDirectoryRow {
  id: string;
  team_id: string;
  actor_type: string;
  display_name: string;
  member_status?: string | null;
  agent_status?: string | null;
  created_at: string;
  updated_at: string;
}

const COLUMNS =
  "id, team_id, actor_type, display_name, member_status, agent_status, created_at, updated_at";

function mapRow(r: ActorDirectoryRow): cache.ActorRow {
  return {
    id: r.id,
    teamId: r.team_id,
    actorType: r.actor_type,
    displayName: r.display_name,
    avatarUrl: null,
    memberStatus: r.member_status ?? null,
    agentStatus: r.agent_status ?? null,
    metadataJson: null,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    deletedAt: null,
    syncedAt: new Date().toISOString(),
  };
}

/**
 * Pull actor_directory rows for a team from Supabase (delta or full),
 * upsert into local cache, bump watermark.
 *
 * @returns number of rows synced
 */
export async function syncActorsForTeam(
  teamId: string,
  opts?: { full?: boolean },
): Promise<number> {
  if (!isTauri()) return 0;
  const TABLE = "actor_directory";
  const watermark = opts?.full
    ? null
    : await cache.getWatermark(TABLE, teamId);

  let q = supabase
    .from(TABLE)
    .select(COLUMNS)
    .eq("team_id", teamId);
  if (watermark) q = q.gt("updated_at", watermark);

  const { data, error } = await q;
  if (error) {
    console.warn("[actor-sync] pull failed:", error.message);
    return 0;
  }

  const rows = ((data ?? []) as ActorDirectoryRow[]).map(mapRow);
  if (rows.length > 0) {
    await cache.upsertActorsBatch(rows);
    const maxUpdated = rows.reduce(
      (acc, r) => (r.updatedAt > acc ? r.updatedAt : acc),
      watermark ?? "",
    );
    if (maxUpdated) {
      await cache.setWatermark(TABLE, teamId, maxUpdated);
    }
  }
  return rows.length;
}
