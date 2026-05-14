import { create } from "zustand";
import { supabase } from "@/lib/supabase-client";
import { useAuthStore } from "./auth-store";
import { isTauri } from "@/lib/utils";
import {
  loadSessionsForTeam,
  upsertSessionsBatch,
  getWatermark,
  setWatermark,
  type SessionRow,
} from "@/lib/local-cache";

export interface SessionListEntry {
  id: string;
  title: string;
  team_id: string;
  last_message_at: string | null;
  last_message_preview: string | null;
  mode: "solo" | "collab" | "control";
  idea_id: string | null;
}

function mapCacheToEntry(r: SessionRow): SessionListEntry {
  return {
    id: r.id,
    title: r.title ?? "",
    team_id: r.teamId,
    last_message_at: r.lastMessageAt ?? null,
    last_message_preview: r.lastMessagePreview ?? null,
    mode: (r.mode as SessionListEntry["mode"]) ?? "solo",
    idea_id: r.ideaId ?? null,
  };
}

/** Sort entries: null last_message_at first, then by last_message_at DESC */
function sortEntries(entries: SessionListEntry[]): SessionListEntry[] {
  return [...entries].sort((a, b) => {
    if (!a.last_message_at && !b.last_message_at) return 0;
    if (!a.last_message_at) return -1;
    if (!b.last_message_at) return 1;
    return b.last_message_at.localeCompare(a.last_message_at);
  });
}

interface State {
  rows: SessionListEntry[];
  loading: boolean;
  error: string | null;
  load: () => Promise<void>;
}

export const useSessionListStore = create<State>((set) => ({
  rows: [],
  loading: false,
  error: null,
  load: async () => {
    const session = useAuthStore.getState().session;
    if (!session) {
      set({ rows: [], loading: false, error: null });
      return;
    }
    set({ loading: true, error: null });

    // Derive the team_id: use user's metadata or first row already in store
    // The primary source is the first row already loaded (set by prior loads).
    // On first boot we fall through to Supabase which populates it.
    const existingRows = useSessionListStore.getState().rows;
    const teamId = existingRows[0]?.team_id ?? null;

    // ── Phase 1: hydrate instantly from local cache (Tauri only) ──────────
    if (isTauri() && teamId) {
      const localRows = await loadSessionsForTeam(teamId);
      if (localRows.length > 0) {
        set({ rows: sortEntries(localRows.map(mapCacheToEntry)) });
      }
    }

    // ── Phase 2: pull delta from Supabase, upsert local, re-hydrate ───────
    const TABLE = "sessions";

    // Build query — apply watermark if we have a teamId and are in Tauri
    const watermark =
      isTauri() && teamId
        ? await getWatermark(TABLE, teamId)
        : null;

    let q = supabase
      .from("sessions")
      .select("id, title, team_id, mode, last_message_at, last_message_preview, created_at, updated_at, idea_id")
      // Brand-new sessions have last_message_at = null. Put them first so
      // they're immediately visible AND so per-session subscribers /
      // rows.find consumers (e.g., ChatPanel.sendIntoSession) can resolve
      // the row right after creation. Older sessions still ranked by
      // recency via the secondary created_at sort.
      .order("last_message_at", { ascending: false, nullsFirst: true })
      .order("created_at", { ascending: false })
      .limit(50);

    // Only apply watermark filter when doing a delta pull inside Tauri
    if (isTauri() && teamId && watermark) {
      q = q.gt("updated_at", watermark);
    }

    const { data, error } = await q;
    if (error) {
      set({ loading: false, error: error.message });
      return;
    }

    const fresh = (data ?? []) as Array<{
      id: string;
      title: string;
      team_id: string;
      mode: string;
      last_message_at: string | null;
      last_message_preview: string | null;
      created_at: string;
      updated_at: string;
      idea_id: string | null;
    }>;

    // In non-Tauri builds (or first boot without teamId) just set rows directly
    if (!isTauri() || !teamId) {
      set({ rows: fresh.map((r) => ({
        id: r.id,
        title: r.title ?? "",
        team_id: r.team_id,
        last_message_at: r.last_message_at,
        last_message_preview: r.last_message_preview,
        mode: (r.mode as SessionListEntry["mode"]) ?? "solo",
        idea_id: r.idea_id ?? null,
      })), loading: false });
      return;
    }

    // Tauri path: upsert into local cache, then re-hydrate to pick up any
    // previously-cached rows that weren't returned in the delta query.
    if (fresh.length > 0) {
      const cacheRows: SessionRow[] = fresh.map((r) => ({
        id: r.id,
        teamId: r.team_id,
        title: r.title ?? null,
        mode: r.mode ?? null,
        primaryAgentId: null,
        ideaId: r.idea_id ?? null,
        summary: null,
        lastMessagePreview: r.last_message_preview ?? null,
        lastMessageAt: r.last_message_at ?? null,
        createdBy: null,
        metadataJson: null,
        createdAt: r.created_at,
        updatedAt: r.updated_at,
        deletedAt: null,
        syncedAt: new Date().toISOString(),
      }));
      await upsertSessionsBatch(cacheRows);

      // Bump watermark
      const resolvedTeamId = fresh[0].team_id;
      const maxUpdated = fresh.reduce(
        (acc, r) => (r.updated_at > acc ? r.updated_at : acc),
        watermark ?? "",
      );
      if (maxUpdated) {
        await setWatermark(TABLE, resolvedTeamId, maxUpdated);
      }
    }

    // Re-hydrate from local cache (merges cached + freshly-synced rows)
    const resolvedTeamId = fresh[0]?.team_id ?? teamId;
    const allLocal = await loadSessionsForTeam(resolvedTeamId);
    set({
      rows: sortEntries(allLocal.map(mapCacheToEntry)),
      loading: false,
    });
  },
}));
