# Auto Restart OpenCode On Skills Change Design

## Context

TeamClaw currently detects Skills changes in the frontend and shows a restart prompt in the Skills settings screen. The prompt works for an attended desktop session, but it does not cover remote server deployments where nobody is available to click Restart after Skills are synced, installed, edited, or deleted.

OpenCode runs on the remote server the same way it runs on macOS: TeamClaw owns the OpenCode sidecar/runtime lifecycle. That means the right long-term behavior is to make restart a runtime capability controlled by a setting, not a manual-only UI action.

## Goals

- Add a global setting: "Auto restart OpenCode after Skills changes".
- Keep the setting disabled by default.
- When disabled, preserve the current manual restart prompt behavior.
- When enabled, automatically restart the current OpenCode runtime after Skills change.
- Keep a manual restart action as a fallback when automatic restart fails.
- Design the setting so the backend can later enforce it without relying on an open frontend page.

## Non-Goals

- Do not implement OpenCode hot reload unless OpenCode exposes a supported runtime reload API.
- Do not make the setting workspace scoped.
- Do not force automatic restart for all users.
- Do not remove the existing manual restart button.

## User Experience

The Skills settings section gets a global toggle near the top:

- Label: "Auto restart after Skills changes"
- Description: "Automatically restart OpenCode after skills are installed, edited, deleted, or synced. Disabled by default."

Chinese copy:

- Label: "Skills 变更后自动重启 OpenCode"
- Description: "安装、编辑、删除或同步 Skills 后自动重启 OpenCode。默认关闭。"

When the toggle is off and Skills change, the existing restart prompt appears:

- "Detected Skill Changes"
- "New or updated skills were detected. Restart OpenCode to load them in the current runtime."
- Restart button

When the toggle is on and Skills change, the settings screen shows automatic progress instead:

- Restarting: "Detected Skill changes. Restarting OpenCode..."
- Success: "OpenCode restarted. Skills are now loaded."
- Failure: "Automatic restart failed." The existing manual Restart button remains available.

## Configuration

The setting is global and defaults to false.

Short-term storage can use the existing frontend global settings pattern if that is where similar preferences live. The key should not include the workspace path:

```text
teamclaw-auto-restart-opencode-on-skills-change
```

Preferred long-term storage is the Rust app settings layer, so remote server logic can read the setting without requiring a browser window. If the app settings command layer already supports arbitrary global preferences, this setting should live there from the start.

## Architecture

Introduce a small runtime reload abstraction instead of having UI components call `stop_opencode` and `start_opencode` directly.

Suggested frontend API:

```ts
requestOpenCodeRuntimeReload(workspacePath: string, reason: OpenCodeReloadReason): Promise<RestartResult>
```

Initial reasons:

```ts
type OpenCodeReloadReason =
  | "skills-file-change"
  | "skills-permission-change"
  | "team-skills-sync"
  | "manual"
```

The existing `restartOpencode(workspacePath)` implementation can back this API initially. The abstraction gives the backend a clean place to take over the reload decision later.

## Data Flow

### Toggle Off

```text
Skills file changes
  -> SKILLS_CHANGED_EVENT
  -> SkillsSection reloads the list
  -> hasSkillRuntimeChanges = true
  -> show manual restart prompt
```

### Toggle On

```text
Skills file changes
  -> SKILLS_CHANGED_EVENT
  -> SkillsSection reloads the list
  -> read global auto-restart setting
  -> call requestOpenCodeRuntimeReload(workspacePath, "skills-file-change")
  -> success clears hasSkillRuntimeChanges
  -> failure keeps hasSkillRuntimeChanges and shows manual retry
```

### Future Backend Flow

```text
Backend watcher or team sync updates Skills
  -> mark skills runtime dirty for workspace
  -> read global auto-restart setting
  -> if disabled, emit "reload required" status only
  -> if enabled, debounce and restart OpenCode runtime
  -> emit reload status to frontend
```

## Error Handling

- If automatic restart fails, keep the dirty/restart-required state visible.
- Show the error message in the existing restart prompt area.
- Do not retry in a tight loop from the frontend.
- Backend-managed retries, when added, should be debounced and capped.
- If no workspace is active, do not attempt restart.
- If a restart is already in progress, ignore duplicate triggers or join the in-flight restart.

## Concurrency

Skills changes often arrive as bursts: install, unzip, sync, delete, or Git checkout can touch multiple files. The existing watcher already debounces file changes before dispatching `SKILLS_CHANGED_EVENT`; the reload abstraction should also guard against concurrent restarts.

Minimum behavior:

- Track `isRestarting`.
- Drop or coalesce new auto-restart requests while one is in flight.
- After a successful restart, clear the runtime change flag.
- After a failed restart, preserve the flag and error.

Backend follow-up:

- Keep a per-workspace reload queue.
- Debounce reload requests for 2-5 seconds.
- Prefer restarting when OpenCode is idle.
- If a session is active, either defer or wait up to a configured maximum before restarting.

## Implementation Touchpoints

- `packages/app/src/components/settings/SkillsSection.tsx`
  - Add the global toggle UI.
  - Load and persist the global setting.
  - Auto-restart on `SKILLS_CHANGED_EVENT` when enabled.
  - Keep manual restart fallback.

- `packages/app/src/lib/opencode/restart.ts`
  - Add or rename to a reload-oriented API while preserving compatibility.
  - Ensure duplicate restart calls are guarded or easy for callers to guard.

- `packages/app/src/hooks/useAppInit.ts`
  - Keep current Skills watcher behavior.
  - Longer-term, move restart decision-making out of this frontend-only hook and into backend runtime management.

- `src-tauri/src/commands/app_settings.rs`
  - Preferred place for the global setting if existing app settings APIs can support it.

- `src-tauri/src/commands/opencode.rs`
  - Future backend implementation can reuse existing `stop_opencode` and `start_opencode` logic.

## Testing

Unit tests:

- Default setting is false.
- Toggling the setting persists globally, not per workspace.
- With setting off, `SKILLS_CHANGED_EVENT` shows manual restart prompt and does not call restart.
- With setting on, `SKILLS_CHANGED_EVENT` calls restart.
- Restart success clears the runtime-changed flag.
- Restart failure preserves the prompt and surfaces the error.

Integration or functional tests:

- Edit a Skill and verify the prompt behavior with the toggle off.
- Edit a Skill and verify automatic restart behavior with the toggle on.
- Simulate multiple quick `SKILLS_CHANGED_EVENT` events and verify only one restart is attempted.

Backend follow-up tests:

- Server-side Skills sync reads the global setting.
- Server-side sync does not restart when the setting is false.
- Server-side sync restarts OpenCode when the setting is true.
- Restart failures leave the workspace marked reload-required.

## Rollout

Phase 1:

- Add the global setting and frontend-controlled auto restart.
- Keep manual restart behavior unchanged for users who do not opt in.

Phase 2:

- Persist the setting in backend-readable global app settings.
- Add backend runtime reload manager.
- Trigger reload from backend Skills sync/file watcher paths.

Phase 3:

- If OpenCode supports a safe reload API in the future, replace process restart with runtime reload behind the same abstraction.

