import { invoke } from '@tauri-apps/api/core'
import { initOpenCodeClient } from './sdk-client'
import { useWorkspaceStore } from '@/stores/workspace'

export interface RestartResult {
  url: string
}

export type OpenCodeReloadReason =
  | 'skills-file-change'
  | 'skills-permission-change'
  | 'team-skills-sync'
  | 'manual'

let runtimeReloadInFlight: Promise<RestartResult> | null = null

// Stop+start the OpenCode sidecar and restore the SDK client URL and ready flags.
// Provider state (including the team provider) is reconciled by the Rust
// `ensure_team_provider` step inside `start_opencode` itself, so callers don't
// need to re-apply team config here.
export async function restartOpencode(workspacePath: string): Promise<RestartResult> {
  const { setOpenCodeBootstrapped, setOpenCodeReady } = useWorkspaceStore.getState()
  setOpenCodeBootstrapped(false)
  await invoke('stop_opencode', { workspacePath })
  await new Promise((resolve) => setTimeout(resolve, 500))
  const status = await invoke<{ url: string }>('start_opencode', {
    config: { workspace_path: workspacePath },
  })
  initOpenCodeClient({ baseUrl: status.url, workspacePath })
  setOpenCodeBootstrapped(true, status.url)
  setOpenCodeReady(true, status.url)
  return { url: status.url }
}

export function requestOpenCodeRuntimeReload(
  workspacePath: string,
  _reason: OpenCodeReloadReason = 'manual',
): Promise<RestartResult> {
  if (runtimeReloadInFlight) {
    return runtimeReloadInFlight
  }

  runtimeReloadInFlight = restartOpencode(workspacePath).finally(() => {
    runtimeReloadInFlight = null
  })
  return runtimeReloadInFlight
}
