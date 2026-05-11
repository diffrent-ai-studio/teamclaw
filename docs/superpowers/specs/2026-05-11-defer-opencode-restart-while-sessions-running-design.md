# Defer OpenCode Restart While Sessions Are Running Design

## Context

TeamClaw now supports a global setting that can automatically restart OpenCode after Skills change. That solves unattended remote server deployments, but it introduces one important safety issue: restarting OpenCode while a session is actively running can interrupt the user's current task.

OpenCode already emits session activity through SSE. The frontend tracks this as `session.status` values (`busy`, `retry`, `idle`), a `busySessions` set, pending permission requests, and pending questions. Those signals are enough to delay an automatic restart until the runtime is idle.

## Goals

- Do not restart OpenCode immediately while any relevant session is active.
- Preserve unattended remote behavior: once the active work finishes, a pending Skills restart should happen automatically.
- Coalesce repeated restart requests into one pending restart per workspace.
- Keep manual restart available, but avoid accidental task interruption by default.
- Centralize the restart scheduling logic so future restart-required settings can reuse it.

## Non-Goals

- Do not implement session cancellation or force-stop behavior.
- Do not add a new timeout that kills long-running sessions.
- Do not move the whole restart system to Rust in this change.
- Do not change the global auto-restart setting semantics: it stays disabled by default.

## User Experience

When auto restart is enabled and Skills change while OpenCode is idle:

- TeamClaw restarts OpenCode immediately.
- The existing restart-required prompt is cleared after success.

When auto restart is enabled and Skills change while a session is running:

- TeamClaw does not restart immediately.
- The UI shows a pending state such as:

```text
Skills updated. OpenCode will restart after the current task finishes.
```

- When the active session becomes idle, TeamClaw restarts OpenCode automatically.
- If more Skills changes happen before the pending restart runs, they are merged into the same pending restart.

When the user clicks a manual Restart button while a session is running:

- Default behavior should also defer instead of interrupting.
- A future force-restart confirmation can be added separately, but it is not part of this change.

## Busy Definition

A workspace is considered busy if any of the following are true:

- `useSessionStore.getState().sessionStatuses` contains a status of `busy` or `retry`.
- `busySessions` contains at least one session id.
- `pendingPermissions` is non-empty.
- `pendingQuestions` is non-empty.

`retry` counts as busy because OpenCode is still actively trying to complete the request. Pending permissions and questions count as busy because the session is waiting on the user and restarting could lose context.

The first implementation can treat session activity as app-global because the current frontend store tracks the active OpenCode runtime globally. If the app later supports several simultaneous workspaces in one process, this check should be narrowed by session directory/workspace.

## Architecture

Introduce a small restart coordinator in the OpenCode runtime layer. UI components should request a reload; they should not decide whether it is safe to restart.

Suggested API:

```ts
export type OpenCodeReloadMode = "immediate" | "defer-if-busy";

export type OpenCodeReloadRequestResult =
  | { status: "restarted"; url: string }
  | { status: "deferred"; workspacePath: string; reason: OpenCodeReloadReason };

export function requestOpenCodeRuntimeReload(
  workspacePath: string,
  reason?: OpenCodeReloadReason,
  options?: { mode?: OpenCodeReloadMode },
): Promise<OpenCodeReloadRequestResult>;
```

Default mode should be `immediate` only for compatibility with existing callers. Skills auto restart and manual Skills restart should pass `mode: "defer-if-busy"`.

The coordinator owns:

- Per-workspace in-flight restart dedupe.
- Per-workspace pending restart state.
- A lightweight idle subscription that re-checks pending restarts after session activity changes.

## Data Flow

### Idle Runtime

```text
Skills change
  -> requestOpenCodeRuntimeReload(workspacePath, "skills-file-change", { mode: "defer-if-busy" })
  -> coordinator sees runtime idle
  -> restartOpencode(workspacePath)
  -> dispatch SKILLS_RUNTIME_RELOADED_EVENT after success
```

### Busy Runtime

```text
Skills change
  -> requestOpenCodeRuntimeReload(workspacePath, "skills-file-change", { mode: "defer-if-busy" })
  -> coordinator sees busy/retry/pending interaction
  -> store pending restart for workspace
  -> return { status: "deferred" }
  -> UI shows pending restart state
  -> session status later becomes idle
  -> coordinator re-checks busy state
  -> restartOpencode(workspacePath)
  -> dispatch SKILLS_RUNTIME_RELOADED_EVENT after success
```

### Repeated Changes While Pending

```text
First Skills change while busy
  -> pending restart created

Second Skills change while busy
  -> same workspace already pending
  -> update reason/metadata if useful
  -> do not create a second restart

Runtime becomes idle
  -> one restart runs
```

## Error Handling

- If a restart request is deferred, it is not treated as an error.
- If the deferred restart later fails, keep the restart-required UI visible and surface the error.
- If a restart is already in flight for the workspace, duplicate requests join the existing in-flight restart.
- If a restart is pending and a manual restart request arrives with `defer-if-busy`, keep a single pending restart.
- If the workspace disappears before a pending restart runs, drop the pending restart.

## UI State

Skills UI should distinguish three runtime states:

- `dirty`: Skills changed and restart is required.
- `pending`: Skills changed and restart is queued until OpenCode is idle.
- `restarting`: Restart is actively running.

The ChatPanel restart banner should also understand the `pending` state so the user does not see a misleading failure or a button that appears to do nothing.

## Testing

Unit tests for the coordinator:

- Idle `defer-if-busy` request restarts immediately.
- Busy `defer-if-busy` request returns `deferred` and does not call `stop_opencode`.
- Multiple busy requests for the same workspace produce one pending restart.
- Different workspaces keep independent pending restart state.
- When session status changes to idle and no pending permissions/questions remain, the pending restart runs.
- Restart failure after a deferred request leaves pending/dirty state visible to callers.

Component tests:

- Skills auto restart shows pending copy when a session is busy.
- Skills auto restart clears pending state after the deferred restart succeeds.
- Manual Skills restart while busy defers instead of immediately stopping OpenCode.
- ChatPanel clears the restart prompt when the deferred restart succeeds.

## Rollout

Phase 1:

- Add the restart coordinator and use it for Skills auto/manual restart.
- Keep existing immediate behavior for unrelated callers.

Phase 2:

- Move other restart-required settings, such as LLM or Env Vars, to the same coordinator if product behavior calls for defer-by-default.

Phase 3:

- If backend-managed Skills sync becomes the primary remote path, mirror the same pending-restart model in Rust using the frontend coordinator behavior as the contract.
