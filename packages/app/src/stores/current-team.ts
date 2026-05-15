import { create } from "zustand";
import { supabase } from "@/lib/supabase-client";
import { useAuthStore } from "./auth-store";
import {
  getTeamWorkspaceConfig,
  type TeamWorkspaceConfig,
} from "@/lib/team-workspace-config";

export interface CurrentTeam {
  id: string;
  name: string;
  slug: string;
}

interface State {
  team: CurrentTeam | null;
  activeWorkspaceConfig: TeamWorkspaceConfig | null;
  loading: boolean;
  saving: boolean;
  error: string | null;
  load: () => Promise<void>;
  reloadAndSwitchTo: (teamId: string) => Promise<void>;
  rename: (newName: string) => Promise<boolean>;
}

export const useCurrentTeamStore = create<State>((set, get) => ({
  team: null,
  activeWorkspaceConfig: null,
  loading: false,
  saving: false,
  error: null,

  load: async () => {
    const session = useAuthStore.getState().session;
    if (!session) {
      set({ team: null, activeWorkspaceConfig: null, loading: false, error: null });
      return;
    }

    set({ loading: true, error: null });
    const { data, error } = await supabase
      .from("teams")
      .select("id, name, slug, created_at")
      .order("created_at", { ascending: true })
      .limit(1);

    if (error) {
      set({ loading: false, error: error.message });
      return;
    }
    const row = data?.[0];
    const activeTeam = row ? { id: row.id, name: row.name, slug: row.slug } : null;
    const activeWorkspaceConfig = activeTeam
      ? await getTeamWorkspaceConfig(activeTeam.id)
      : null;
    set({
      team: activeTeam,
      activeWorkspaceConfig,
      loading: false,
    });
  },

  reloadAndSwitchTo: async (teamId: string) => {
    const session = useAuthStore.getState().session;
    if (!session) {
      set({ team: null, activeWorkspaceConfig: null, loading: false, error: null });
      return;
    }

    set({ loading: true, error: null });
    const { data, error } = await supabase
      .from("teams")
      .select("id, name, slug")
      .eq("id", teamId)
      .single();

    if (error) {
      set({ loading: false, error: error.message });
      return;
    }
    const activeTeam = data ? { id: data.id, name: data.name, slug: data.slug } : null;
    const activeWorkspaceConfig = activeTeam
      ? await getTeamWorkspaceConfig(activeTeam.id)
      : null;
    set({
      team: activeTeam,
      activeWorkspaceConfig,
      loading: false,
    });
  },

  rename: async (newName) => {
    const team = get().team;
    if (!team) {
      set({ error: "no current team" });
      return false;
    }
    const trimmed = newName.trim();
    if (!trimmed) {
      set({ error: "team name is required" });
      return false;
    }

    set({ saving: true, error: null });
    const { data, error } = await supabase.rpc("rename_team", {
      p_team_id: team.id,
      p_name: trimmed,
    });

    if (error) {
      set({ saving: false, error: error.message });
      return false;
    }
    const row = Array.isArray(data) ? data[0] : data;
    set({
      team: row
        ? { id: row.team_id, name: row.team_name, slug: row.team_slug }
        : { ...team, name: trimmed },
      saving: false,
    });
    return true;
  },
}));
