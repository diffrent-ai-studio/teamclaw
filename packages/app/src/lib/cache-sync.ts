/**
 * cache-sync.ts — Generic helpers for pulling Supabase rows into the local
 * libsql cache with watermark-based delta fetching.
 *
 * Schema notes (verified 2026-05-13):
 *   actors               — has updated_at ✓  (no deleted_at on Supabase; use soft-delete local only)
 *   sessions             — has updated_at ✓
 *   session_participants — has updated_at ✓  (no team_id column; scoped by session_id)
 *   messages             — has updated_at ✓
 *   ideas                — has updated_at ✓
 *   claims               — NOT in information_schema results → FULL-PULL ONLY (TODO: confirm schema)
 *   submissions          — NOT in information_schema results → FULL-PULL ONLY (TODO: confirm schema)
 *   team_workspace_config     — has updated_at ✓
 *   actor_message_feedback    — created_at only; FULL-PULL per team
 *   actor_session_report      — created_at only; FULL-PULL per team
 */

import { supabase } from "@/lib/supabase-client";
import * as cache from "@/lib/local-cache";

// ── Team-scoped sync ────────────────────────────────────────────────────────

/**
 * Pull rows from a Supabase table since the local watermark (delta sync),
 * upsert them into the local cache, and bump the watermark.
 *
 * The watermark key is `tableName` and is namespaced by `teamId`.
 */
export async function syncTableForTeam<TSupabaseRow, TCacheRow>(args: {
  /** Used as both the Supabase `from()` target and the watermark key. */
  tableName: string;
  teamId: string;
  selectColumns: string;
  mapRow: (r: TSupabaseRow) => TCacheRow;
  upsertBatch: (rows: TCacheRow[]) => Promise<void>;
  /** When true, ignore the watermark and pull all rows (forced full refresh). */
  full?: boolean;
}): Promise<{ count: number }> {
  const watermark = args.full
    ? null
    : await cache.getWatermark(args.tableName, args.teamId);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let q = (supabase.from(args.tableName) as any)
    .select(args.selectColumns)
    .eq("team_id", args.teamId);
  if (watermark) q = q.gt("updated_at", watermark);

  const { data, error } = await q;
  if (error) {
    console.warn(`[cache-sync] ${args.tableName} pull failed:`, error.message);
    return { count: 0 };
  }

  const rows = ((data as TSupabaseRow[]) ?? []).map(args.mapRow);
  if (rows.length > 0) {
    await args.upsertBatch(rows);
    // Bump watermark to the newest updated_at in this batch.
    const maxUpdated = rows.reduce<string>((acc, r) => {
      const u = (r as { updatedAt?: string }).updatedAt ?? "";
      return u > acc ? u : acc;
    }, watermark ?? "");
    if (maxUpdated) {
      await cache.setWatermark(args.tableName, args.teamId, maxUpdated);
    }
  }
  return { count: rows.length };
}

// ── Session-scoped sync ─────────────────────────────────────────────────────

/**
 * Pull rows from a Supabase table scoped to a single session (e.g. messages,
 * session_participants).  Watermark key is `<tableName>:<sessionId>`,
 * namespaced by `teamId`.
 */
export async function syncTableForSession<TSupabaseRow, TCacheRow>(args: {
  tableName: string;
  sessionId: string;
  /** Used only for watermark namespacing. */
  teamId: string;
  selectColumns: string;
  mapRow: (r: TSupabaseRow) => TCacheRow;
  upsertBatch: (rows: TCacheRow[]) => Promise<void>;
  full?: boolean;
}): Promise<{ count: number }> {
  const wmKey = `${args.tableName}:${args.sessionId}`;
  const watermark = args.full
    ? null
    : await cache.getWatermark(wmKey, args.teamId);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let q = (supabase.from(args.tableName) as any)
    .select(args.selectColumns)
    .eq("session_id", args.sessionId);
  if (watermark) q = q.gt("updated_at", watermark);

  const { data, error } = await q;
  if (error) {
    console.warn(
      `[cache-sync] ${args.tableName}@${args.sessionId} pull failed:`,
      error.message,
    );
    return { count: 0 };
  }

  const rows = ((data as TSupabaseRow[]) ?? []).map(args.mapRow);
  if (rows.length > 0) {
    await args.upsertBatch(rows);
    const maxUpdated = rows.reduce<string>((acc, r) => {
      const u = (r as { updatedAt?: string }).updatedAt ?? "";
      return u > acc ? u : acc;
    }, watermark ?? "");
    if (maxUpdated) {
      await cache.setWatermark(wmKey, args.teamId, maxUpdated);
    }
  }
  return { count: rows.length };
}
