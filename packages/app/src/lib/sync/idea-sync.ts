/**
 * idea-sync.ts — Sync ideas from Supabase into local libsql cache.
 *
 * updated_at: ✓ present on ideas (confirmed via information_schema)
 * Watermark key: "ideas" namespaced by teamId.
 */

import { syncTableForTeam } from "@/lib/cache-sync";
import * as cache from "@/lib/local-cache";
import { isTauri } from "@/lib/utils";

// Supabase `ideas` columns: id, team_id, workspace_id, parent_idea_id,
// created_by_actor_id, title, description, status, archived, created_at, updated_at.
interface SupabaseIdeaRow {
  id: string;
  team_id: string;
  workspace_id?: string | null;
  parent_idea_id?: string | null;
  title: string;
  description?: string | null;
  status?: string | null;
  created_by_actor_id?: string | null;
  archived?: boolean | number | null;
  created_at: string;
  updated_at: string;
}

const COLUMNS =
  "id, team_id, workspace_id, parent_idea_id, title, description, status, created_by_actor_id, archived, created_at, updated_at";

function mapRow(r: SupabaseIdeaRow): cache.IdeaRow {
  return {
    id: r.id,
    teamId: r.team_id,
    workspaceId: r.workspace_id ?? null,
    parentId: r.parent_idea_id ?? null,
    title: r.title,
    description: r.description ?? null,
    status: r.status ?? null,
    createdBy: r.created_by_actor_id ?? null,
    // Supabase returns boolean; local cache stores 0/1
    archived: r.archived ? 1 : 0,
    metadataJson: null,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    deletedAt: null,
    syncedAt: new Date().toISOString(),
  };
}

/**
 * Pull ideas for a team from Supabase (delta or full),
 * upsert into local cache, bump watermark.
 *
 * @returns number of rows synced
 */
export async function syncIdeasForTeam(
  teamId: string,
  opts?: { full?: boolean },
): Promise<number> {
  if (!isTauri()) return 0;
  const { count } = await syncTableForTeam<SupabaseIdeaRow, cache.IdeaRow>({
    tableName: "ideas",
    teamId,
    selectColumns: COLUMNS,
    mapRow,
    upsertBatch: cache.upsertIdeasBatch,
    full: opts?.full,
  });
  return count;
}
