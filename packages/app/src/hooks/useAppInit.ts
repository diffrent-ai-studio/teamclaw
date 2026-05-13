/**
 * useAppInit — initialization logic extracted from App.tsx
 *
 * Handles:
 *  - Tauri body class injection
 *  - Workspace restore
 *  - Channel gateway auto-start / keep-alive
 *  - Git repos auto-sync
 *  - External-link interception (Tauri only)
 *  - Dependency check + setup guide visibility
 *  - Telemetry consent dialog
 */
import { useEffect, useRef, useState, useCallback } from "react";
import { isTauri } from "@/lib/utils";
import { useTabsStore } from "@/stores/tabs";
import { urlToLabel } from "@/lib/webview-utils";
import { useWorkspaceStore } from "@/stores/workspace";
import { useChannelsStore } from "@/stores/channels";
import { useGitReposStore } from "@/stores/git-repos";
import { useUIStore } from "@/stores/ui";
import { useDepsStore, getSetupDecision, markSetupCompleted } from "@/stores/deps";
import { useTelemetryStore } from "@/stores/telemetry";
import { useTeamModeStore } from "@/stores/team-mode";
import { useTeamOssStore } from "@/stores/team-oss";
import { useTeamMembersStore } from "@/stores/team-members";
import { useShortcutsStore } from "@/stores/shortcuts";
import { useCronStore } from "@/stores/cron";
import { getSkillDirectories, loadAllSkills } from "@/lib/git/skill-loader";
import { appShortName, TEAMCLAW_DIR, TEAM_REPO_DIR } from "@/lib/build-config";

export const SKILLS_CHANGED_EVENT = "skills-files-changed";

// ─────────────────────────────────────────────────────────────────────────────
// Workspace restore
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Parse `?workspace=&port=` from window.location for secondary windows opened
 * via `create_workspace_window`. Returns null in the main window.
 */
function readWindowParams(): { workspace: string; port: number } | null {
  if (typeof window === "undefined" || !window.location?.search) return null;
  const params = new URLSearchParams(window.location.search);
  const workspace = params.get("workspace");
  const portStr = params.get("port");
  if (!workspace || !portStr) return null;
  const port = Number.parseInt(portStr, 10);
  if (!Number.isFinite(port) || port <= 0) return null;
  return { workspace, port };
}

const windowParams = readWindowParams();

export function useWorkspaceInit() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const setWorkspace = useWorkspaceStore((s) => s.setWorkspace);
  const [initialWorkspaceResolved, setInitialWorkspaceResolved] = useState(false);

  // Auto-restore last workspace on launch (runs once on mount).
  // Secondary windows opened via create_workspace_window skip the localStorage
  // path and use the URL-provided workspace so they don't clobber main's saved value.
  useEffect(() => {
    let cancelled = false;

    void (async () => {
      if (!workspacePath) {
        if (windowParams) {
          console.log(
            "[App] Secondary window detected; using URL workspace:",
            windowParams.workspace,
          );
          await setWorkspace(windowParams.workspace);
        } else {
          try {
            const savedPath = localStorage.getItem(`${appShortName}-workspace-path`);
            if (savedPath) {
              let canRestore = true;

              if (isTauri()) {
                try {
                  const { exists } = await import("@tauri-apps/plugin-fs");
                  canRestore = await exists(savedPath);
                } catch (error) {
                  console.warn("[App] Failed to validate saved workspace:", error);
                }
              }

              if (canRestore) {
                console.log("[App] Restoring workspace from last session:", savedPath);
                await setWorkspace(savedPath);
              } else {
                console.log("[App] Saved workspace no longer exists, clearing restore path:", savedPath);
                localStorage.removeItem(`${appShortName}-workspace-path`);
              }
            }
          } catch {
            /* ignore storage errors */
          }
        }
      }

      if (!cancelled) {
        setInitialWorkspaceResolved(true);
        performance.mark('workspace-restored');
      }
    })();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!workspacePath || !isTauri()) return;

    let cancelled = false;
    let unlisten: (() => void) | null = null;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    let watchedDirs: string[] = [];
    let skillDirs: string[] = [];
    let lastSkillSignature = "";
    let hasObservedSkillChange = false;
    let changeVersion = 0;

    const QUIET_WINDOW_MS = 3000;
    const SIGNATURE_CONFIRM_MS = 1200;

    const normalizePath = (value: string) => value.replace(/\\/g, "/").replace(/\/$/, "");
    const isSkillFileChange = (path: string) => {
      const normalizedPath = normalizePath(path);
      return skillDirs.some((dir) => {
        const normalizedDir = normalizePath(dir);
        return normalizedPath === normalizedDir || normalizedPath.startsWith(`${normalizedDir}/`);
      });
    };

    const buildSkillSignature = async () => {
      const { skills } = await loadAllSkills(workspacePath);
      return JSON.stringify(
        skills
          .map((skill) => ({
            filename: skill.filename,
            source: skill.source,
            dirPath: skill.dirPath,
            content: skill.content,
          }))
          .sort((a, b) => `${a.dirPath}/${a.filename}`.localeCompare(`${b.dirPath}/${b.filename}`)),
      );
    };

    const refreshSkillState = async (versionAtSchedule: number) => {
      if (versionAtSchedule !== changeVersion || cancelled) return;

      const firstSignature = await buildSkillSignature();
      await new Promise((resolve) => setTimeout(resolve, SIGNATURE_CONFIRM_MS));
      if (versionAtSchedule !== changeVersion || cancelled) return;

      const secondSignature = await buildSkillSignature();
      if (firstSignature !== secondSignature) return;

      if (secondSignature !== lastSkillSignature) {
        const isFirstObservedChange = !hasObservedSkillChange;
        hasObservedSkillChange = true;
        lastSkillSignature = secondSignature;
        // Suppress restart prompts caused by startup-time churn while the
        // initial watcher baseline is stabilizing.
        if (isFirstObservedChange) return;
        window.dispatchEvent(new CustomEvent(SKILLS_CHANGED_EVENT));
      }
    };

    void (async () => {
      try {
        const [{ invoke }, { listen }, { exists }] = await Promise.all([
          import("@tauri-apps/api/core"),
          import("@tauri-apps/api/event"),
          import("@tauri-apps/plugin-fs"),
        ]);

        skillDirs = await getSkillDirectories(workspacePath);
        lastSkillSignature = await buildSkillSignature();
        const watchableDirs = new Set<string>();

        for (const dir of skillDirs) {
          if (await exists(dir)) {
            watchableDirs.add(dir);
            continue;
          }

          const parentDir = dir.replace(/\/[^/]+$/, "");
          if (parentDir && await exists(parentDir)) {
            watchableDirs.add(parentDir);
          }
        }

        watchedDirs = Array.from(watchableDirs);
        await Promise.all(
          watchedDirs.map((path) =>
            invoke("watch_directory", { path }).catch((error) => {
              console.warn("[SkillsWatch] Failed to watch directory:", path, error);
            }),
          ),
        );

        if (cancelled) return;

        unlisten = await listen<{ path: string; kind: string }>("file-change", (event) => {
          if (!isSkillFileChange(event.payload.path)) return;

          changeVersion += 1;
          const versionAtSchedule = changeVersion;
          if (debounceTimer) clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => {
            void refreshSkillState(versionAtSchedule);
          }, QUIET_WINDOW_MS);
        });
      } catch (error) {
        console.warn("[SkillsWatch] Failed to initialize skill watcher:", error);
      }
    })();

    return () => {
      cancelled = true;
      if (debounceTimer) clearTimeout(debounceTimer);
      unlisten?.();

      void (async () => {
        if (watchedDirs.length === 0) return;
        try {
          const { invoke } = await import("@tauri-apps/api/core");
          await Promise.all(
            watchedDirs.map((path) =>
              invoke("unwatch_directory", { path }).catch((error) => {
                console.warn("[SkillsWatch] Failed to unwatch directory:", path, error);
              }),
            ),
          );
        } catch (error) {
          console.warn("[SkillsWatch] Failed to cleanup skill watchers:", error);
        }
      })();
    };
  }, [workspacePath]);

  return { initialWorkspaceResolved };
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel gateway auto-start / keep-alive
// ─────────────────────────────────────────────────────────────────────────────

export function useChannelGatewayInit() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const workspaceReady = !!workspacePath;
  const {
    autoStartEnabledGateways,
    loadConfig: loadChannelsConfig,
    stopAllAndReset,
    keepAliveCheck,
  } = useChannelsStore();
  const hasAutoStarted = useRef(false);
  const prevWorkspaceRef = useRef<string | null>(null);

  // When workspace changes: stop all gateways, reset state, allow re-auto-start
  useEffect(() => {
    if (prevWorkspaceRef.current === null) {
      prevWorkspaceRef.current = workspacePath;
      return;
    }

    if (workspacePath !== prevWorkspaceRef.current) {
      console.log(
        "[App] Workspace changed from",
        prevWorkspaceRef.current,
        "to",
        workspacePath,
      );
      prevWorkspaceRef.current = workspacePath;
      hasAutoStarted.current = false;

      stopAllAndReset().catch((err: unknown) => {
        console.warn("[App] Failed to stop gateways on workspace change:", err);
      });
    }
  }, [workspacePath, stopAllAndReset]);

  // When workspace becomes ready: load channel configs and auto-start enabled gateways
  useEffect(() => {
    if (workspaceReady && !hasAutoStarted.current) {
      hasAutoStarted.current = true;
      console.log("[App] Workspace ready, loading channel configs and auto-starting...");
      loadChannelsConfig()
        .then(() => {
          autoStartEnabledGateways();
        })
        .catch((err: unknown) => {
          console.error("[App] Failed to load channel configs for auto-start:", err);
        });
    }
  }, [workspaceReady, autoStartEnabledGateways, loadChannelsConfig]);

  // Keep-alive: periodically check enabled channels and restart if disconnected/errored
  useEffect(() => {
    if (!workspaceReady) return;
    const keepAliveInterval = setInterval(() => {
      keepAliveCheck().catch((err: unknown) => {
        console.warn("[App] Keep-alive check failed:", err);
      });
    }, 30_000);
    return () => clearInterval(keepAliveInterval);
  }, [workspaceReady, keepAliveCheck]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Git repos auto-sync
// ─────────────────────────────────────────────────────────────────────────────

export function useGitReposInit() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const workspaceReady = !!workspacePath;
  const { initialize: initGitRepos, syncAll: syncGitRepos } = useGitReposStore();
  const prevWorkspaceRef = useRef<string | null>(null);
  const teamSyncIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Local git repos init — re-runs when workspace changes
  useEffect(() => {
    if (!workspacePath) return;

    const isWorkspaceChange = prevWorkspaceRef.current !== null && prevWorkspaceRef.current !== workspacePath;
    prevWorkspaceRef.current = workspacePath;

    if (isWorkspaceChange) {
      useGitReposStore.getState().reset();
    }

    initGitRepos()
      .then(() => {
        syncGitRepos().catch((err: unknown) => {
          console.warn("[App] Git auto-sync failed (non-critical):", err);
        });
      })
      .catch((err: unknown) => {
        console.warn("[App] Git repos init failed (non-critical):", err);
      });
  }, [workspacePath, initGitRepos, syncGitRepos]);

  // Team sync — deferred until sidecar is ready to avoid I/O contention
  useEffect(() => {
    if (!workspacePath || !workspaceReady || !isTauri()) return;

    import("@tauri-apps/api/core")
      .then(({ invoke }) => {
        invoke("get_team_config", { workspacePath })
          .then((config: unknown) => {
            const teamConfig = config as { enabled?: boolean } | null;
            if (teamConfig?.enabled) {
              const doSync = () => {
                invoke("team_sync_repo", { force: false, workspacePath })
                  .then(async (result: unknown) => {
                    const r = result as {
                      success: boolean;
                      message: string;
                      needsConfirmation?: boolean;
                      newFiles?: Array<{ path: string; sizeBytes: number }>;
                      totalBytes?: number;
                    };
                    if (r.needsConfirmation) {
                      console.warn(
                        "[App] Team sync blocked by precheck — waiting for user confirmation in Settings",
                        { count: r.newFiles?.length ?? 0, totalBytes: r.totalBytes ?? 0 },
                      );
                      const { toast } = await import("sonner");
                      toast.warning(
                        `检测到 ${r.newFiles?.length ?? 0} 个较大的新文件待同步，请在设置 → 团队中确认`,
                      );
                      return;
                    }
                    if (r.success) {
                      const { useTeamModeStore } = await import("@/stores/team-mode");
                      useTeamModeStore.setState({ teamGitLastSyncAt: new Date().toISOString() });
                      if (useTeamModeStore.getState().teamModeType === "git") {
                        useTeamModeStore.getState().loadTeamGitFileSyncStatus(workspacePath);
                      }
                      console.log("[App] Team repo sync completed (MCP configs updated)");
                    } else {
                      console.warn("[App] Team repo sync skipped:", r.message);
                    }
                  })
                  .catch((err: unknown) => {
                    console.warn("[App] Team repo sync failed (non-critical):", err);
                  });
              };

              console.log("[App] Team config found, syncing team repo...");
              doSync();

              // Periodic sync every 5 minutes
              const intervalId = setInterval(() => {
                console.log("[App] Periodic team repo sync...");
                doSync();
              }, 5 * 60 * 1000);
              teamSyncIntervalRef.current = intervalId;
            }
          })
          .catch((err: unknown) => {
            console.warn("[App] Failed to check team config (non-critical):", err);
          });
      })
      .catch(() => {
        // Tauri not available, skip
      });

    // Load team shortcuts after team config
    import("@/lib/team-shortcuts")
      .then(({ loadTeamShortcutsFile }) => {
        return loadTeamShortcutsFile(workspacePath);
      })
      .then((teamShortcuts) => {
        useShortcutsStore.getState().setTeamNodes(teamShortcuts || []);
      })
      .catch((err: unknown) => {
        console.warn("[App] Failed to load team shortcuts (non-critical):", err);
      });

    void (async () => {
      try {
        await useTeamMembersStore.getState().loadCurrentNodeId();
      } catch (err: unknown) {
        console.warn("[App] Failed to load current team member identity (non-critical):", err);
      }

      try {
        await useTeamMembersStore.getState().loadMembers();
      } catch (err: unknown) {
        console.warn("[App] Failed to load team members for shortcut roles (non-critical):", err);
      }
    })();

    return () => {
      if (teamSyncIntervalRef.current) {
        clearInterval(teamSyncIntervalRef.current);
        teamSyncIntervalRef.current = null;
      }
    };
  }, [workspacePath, workspaceReady]);

  // Real-time: refresh team-git file status and member roles when team files change
  useEffect(() => {
    if (!workspacePath || !isTauri()) return;
    let unlistenFileChange: (() => void) | undefined;
    let unlistenMembersChanged: (() => void) | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancelled = false;

    const normalizePath = (value: string) => value.replace(/\\/g, "/").replace(/\/$/, "");
    const teamDirPrefix = `${workspacePath}/${TEAM_REPO_DIR}/`;
    const memberManifestPaths = new Set([
      `${workspacePath}/${TEAM_REPO_DIR}/_meta/members.json`,
      `${workspacePath}/${TEAM_REPO_DIR}/_team/members.json`,
      `${workspacePath}/${TEAMCLAW_DIR}/_team/members.json`,
    ].map(normalizePath));

    const refreshCurrentMemberShortcutRoles = async () => {
      try {
        await useTeamMembersStore.getState().loadCurrentNodeId();
      } catch (err: unknown) {
        console.warn("[App] Failed to refresh current team member identity (non-critical):", err);
      }

      try {
        await useTeamMembersStore.getState().loadMembers();
      } catch (err: unknown) {
        console.warn("[App] Failed to refresh team members for shortcut roles (non-critical):", err);
      }
    };

    import("@tauri-apps/api/event").then(({ listen }) => {
      if (cancelled) return;
      listen<{ path: string; kind: string }>("file-change", (event) => {
        const path = normalizePath(event.payload.path);
        if (memberManifestPaths.has(path)) {
          void refreshCurrentMemberShortcutRoles();
        }

        if (!path.startsWith(teamDirPrefix)) return;
        // Skip churn inside .git/
        if (path.includes(`/${TEAM_REPO_DIR}/.git/`)) return;
        if (timer) clearTimeout(timer);
        timer = setTimeout(async () => {
          const { useTeamModeStore } = await import("@/stores/team-mode");
          if (useTeamModeStore.getState().teamModeType !== "git") return;
          useTeamModeStore.getState().loadTeamGitFileSyncStatus(workspacePath);
        }, 500);
      }).then((fn) => {
        if (cancelled) {
          fn();
          return;
        }
        unlistenFileChange = fn;
      });

      listen("team:members-changed", () => {
        void refreshCurrentMemberShortcutRoles();
      }).then((fn) => {
        if (cancelled) {
          fn();
          return;
        }
        unlistenMembersChanged = fn;
      });
    });

    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
      unlistenFileChange?.();
      unlistenMembersChanged?.();
    };
  }, [workspacePath]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Cron session IDs (for sidebar filtering)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// P2P auto-reconnect (team mode)
// ─────────────────────────────────────────────────────────────────────────────

export function useP2pAutoReconnect() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const workspaceReady = !!workspacePath;
  const teamMode = useTeamModeStore((s) => s.teamMode);
  const teamModeType = useTeamModeStore((s) => s.teamModeType);

  useEffect(() => {
    // Only auto-reconnect for P2P teams, not S3/OSS/Git
    if (!workspacePath || !workspaceReady || !teamMode || !isTauri()) return;
    if (teamModeType && teamModeType !== 'p2p') return;

    let cancelled = false;
    const MAX_RETRIES = 5;
    const INITIAL_DELAY = 3000;

    const attemptReconnect = async (attempt: number) => {
      if (cancelled) return;
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        await invoke("p2p_reconnect");

        // Update connection status
        const status = await invoke<{ connected?: boolean; role?: string }>("p2p_sync_status").catch(() => null);
        if (status) {
          useTeamModeStore.setState({
            p2pConnected: status.connected ?? false,
            myRole: (status.role as 'owner' | 'editor' | 'viewer') ?? null,
          });
        }

        // Initialize engine store so sidebar icon and popover reflect connection state
        const { useP2pEngineStore } = await import("@/stores/p2p-engine");
        await useP2pEngineStore.getState().init();
        await useP2pEngineStore.getState().fetch();

        console.log("[P2P] Auto-reconnect completed");
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (attempt < MAX_RETRIES && msg.includes("not running")) {
          const delay = INITIAL_DELAY * Math.pow(2, attempt);
          console.warn(`[P2P] Auto-reconnect attempt ${attempt + 1}/${MAX_RETRIES} failed (iroh not ready), retrying in ${delay}ms`);
          timer = setTimeout(() => attemptReconnect(attempt + 1), delay);
        } else {
          console.warn("[P2P] Auto-reconnect failed:", msg);
        }
      }
    };

    // Delay first attempt so it doesn't compete with app startup
    let timer: ReturnType<typeof setTimeout> = setTimeout(() => attemptReconnect(0), INITIAL_DELAY);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [workspacePath, workspaceReady, teamMode, teamModeType]);
}

export function useCronInit() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const workspaceReady = !!workspacePath;

  useEffect(() => {
    if (!isTauri() || !workspacePath || !workspaceReady) return;

    let unlisten: (() => void) | undefined;
    let cancelled = false;

    (async () => {
      const { listen } = await import("@tauri-apps/api/event");
      if (cancelled) return;
      unlisten = await listen("cron:cron-sessions-updated", () => {
        useCronStore.getState().loadCronSessionIds().catch((err: unknown) => {
          console.warn("[App] Cron session IDs refresh failed (non-critical):", err);
        });
      });

      try {
        await useCronStore.getState().reinit();
      } catch (err: unknown) {
        console.warn("[App] Cron reinit failed (non-critical):", err);
      }
    })();

    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [workspacePath, workspaceReady]);
}

// ─────────────────────────────────────────────────────────────────────────────
// OSS sync auto-restore
// ─────────────────────────────────────────────────────────────────────────────

export function useOssSyncInit() {
  const workspacePath = useWorkspaceStore((s) => s.workspacePath);
  const workspaceReady = !!workspacePath;
  const initialize = useTeamOssStore((s) => s.initialize);
  const cleanup = useTeamOssStore((s) => s.cleanup);

  useEffect(() => {
    if (!workspacePath || !workspaceReady || !isTauri()) return;

    // Clean up previous workspace listener, reset state, then re-initialize
    cleanup();
    initialize(workspacePath).catch((err: unknown) => {
      console.warn("[App] OSS sync init failed (non-critical):", err);
    });

    return () => {
      cleanup();
    };
  }, [workspacePath, workspaceReady, initialize, cleanup]);
}

// ─────────────────────────────────────────────────────────────────────────────
// External link interception (Tauri only)
// ─────────────────────────────────────────────────────────────────────────────

export function useExternalLinkHandler() {
  useEffect(() => {
    if (!isTauri()) return;

    const handler = (e: MouseEvent) => {
      const anchor = (e.target as HTMLElement).closest?.("a");
      if (!anchor) return;
      const href = anchor.getAttribute("href");
      if (href && /^https?:\/\//.test(href)) {
        e.preventDefault();
        e.stopPropagation();
        useTabsStore.getState().openTab({
          type: "webview",
          target: href,
          label: urlToLabel(href),
        });
      }
    };

    document.addEventListener("click", handler, true);
    return () => document.removeEventListener("click", handler, true);
  }, []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tauri body class
// ─────────────────────────────────────────────────────────────────────────────

export function useTauriBodyClass() {
  useEffect(() => {
    if (isTauri()) {
      document.documentElement.classList.add("tauri");
      return () => document.documentElement.classList.remove("tauri");
    }
  }, []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Dependency check / setup guide
// ─────────────────────────────────────────────────────────────────────────────

export function useSetupGuide(workspaceReady: boolean) {
  const [showSetupGuide, setShowSetupGuide] = useState(false);
  const {
    dependencies,
    checkDependencies,
  } = useDepsStore();
  const depsResultRef = useRef<{ checked: boolean; hasRequiredMissing: boolean }>({
    checked: false,
    hasRequiredMissing: false,
  });
  const setupDecisionRef = useRef(getSetupDecision());

  // Dependency check — deferred until workspace is ready to avoid CPU contention
  useEffect(() => {
    const debugForceSetup = (() => {
      try {
        return localStorage.getItem(`${appShortName}-debug-force-setup`) === "1";
      } catch {
        return false;
      }
    })();

    if (!isTauri() && !debugForceSetup) return;

    const decision = setupDecisionRef.current;

    if (decision === "skip") {
      depsResultRef.current = { checked: true, hasRequiredMissing: false };
      return;
    }

    // Wait for workspace to be ready before checking deps (reduces startup CPU contention)
    if (!workspaceReady && isTauri()) return;

    console.log("[Setup] Checking dependencies (decision:", decision, ")");
    checkDependencies().then((result) => {
      const hasRequiredMissing = result.some((d) => d.required && !d.installed);
      depsResultRef.current = { checked: true, hasRequiredMissing };
      if (hasRequiredMissing && (decision === "show" || decision === "silent-check")) {
        setShowSetupGuide(true);
      }
    });
  }, [workspaceReady, checkDependencies]);

  const handleRecheck = useCallback(async () => {
    return checkDependencies();
  }, [checkDependencies]);

  const handleSetupContinue = useCallback(() => {
    markSetupCompleted();
    setShowSetupGuide(false);
  }, []);

  return { showSetupGuide, dependencies, handleRecheck, handleSetupContinue };
}

// ─────────────────────────────────────────────────────────────────────────────
// Telemetry consent dialog
// ─────────────────────────────────────────────────────────────────────────────

export function useTelemetryConsent(showSetupGuide: boolean) {
  const [showConsentDialog, setShowConsentDialog] = useState(false);
  const telemetryConsent = useTelemetryStore((s) => s.consent);
  const telemetryInit = useTelemetryStore((s) => s.init);
  const telemetryInitialized = useTelemetryStore((s) => s.isInitialized);

  // Initialize telemetry on mount
  useEffect(() => {
    telemetryInit();
  }, [telemetryInit]);

  // Show consent dialog after setup is done if consent is undecided
  useEffect(() => {
    if (!showSetupGuide && telemetryInitialized && telemetryConsent === "undecided") {
      setShowConsentDialog(true);
    }
  }, [showSetupGuide, telemetryInitialized, telemetryConsent]);

  return { showConsentDialog, setShowConsentDialog };
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout mode keyboard shortcut + panel auto-open
// ─────────────────────────────────────────────────────────────────────────────

export function useLayoutModeShortcut() {
  const toggleLayoutMode = useUIStore((s) => s.toggleLayoutMode);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "\\") {
        if (!useUIStore.getState().advancedMode) return;
        e.preventDefault();
        toggleLayoutMode();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [toggleLayoutMode]);
}
