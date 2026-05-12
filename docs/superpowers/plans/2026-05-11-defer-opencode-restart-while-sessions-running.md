# Defer OpenCode Restart While Sessions Are Running Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delay Skills-triggered OpenCode restarts while sessions are busy, then automatically run the pending restart once the runtime becomes idle.

**Architecture:** Extend `packages/app/src/lib/opencode/restart.ts` from a thin restart wrapper into a small per-workspace reload coordinator. The coordinator reads session activity from `useSessionStore` and `busySessions`, coalesces pending reloads, emits generic reload lifecycle events, and keeps existing immediate behavior for unrelated callers.

**Tech Stack:** TypeScript, React, Zustand, Vitest, Testing Library, existing Tauri `stop_opencode` / `start_opencode` commands.

---

## File Structure

- Modify `packages/app/src/lib/opencode/restart.ts`
  - Add `OpenCodeReloadMode`, `OpenCodeReloadRequestResult`, generic event constants, busy detection, pending reload state, and deferred flush logic.
  - Keep `restartOpencode(workspacePath)` as the low-level immediate restart function.

- Modify `packages/app/src/lib/opencode/__tests__/restart.test.ts`
  - Add coordinator tests for `defer-if-busy`, pending coalescing, independent workspaces, and idle-triggered restart.

- Modify `packages/app/src/components/settings/SkillsSection.tsx`
  - Pass `mode: "defer-if-busy"` for Skills auto restart, manual Skills restart, permission restart, and ZIP import restart.
  - Add pending UI state for deferred restarts.
  - Listen for generic reload lifecycle events and clear pending/dirty state only after an actual successful restart.

- Modify `packages/app/src/components/settings/__tests__/SkillsSection.test.tsx`
  - Update existing expectations for the new third argument.
  - Add pending-state tests for automatic and manual restart while busy.

- Modify `packages/app/src/components/chat/ChatPanel.tsx`
  - Pass `mode: "defer-if-busy"` for the Skills restart banner.
  - Do not dispatch a success event when the restart request is only deferred.
  - Clear the prompt when the coordinator emits a successful Skills reload event.

- Modify `packages/app/src/components/chat/__tests__/ChatPanel-submission.test.tsx`
  - Update restart mock return shape.
  - Add a manual banner restart test for deferred behavior.

---

### Task 1: Add Deferred Reload Coordinator Tests

**Files:**
- Modify: `packages/app/src/lib/opencode/__tests__/restart.test.ts`

- [ ] **Step 1: Add session-store and busy-session mocks**

At the top of `restart.test.ts`, extend the hoisted block and mocks:

```ts
const {
  invokeMock,
  workspaceState,
  initOpenCodeClientMock,
  sessionState,
  sessionSubscribers,
  busySessionsMock,
} = vi.hoisted(() => ({
  invokeMock: vi.fn(),
  workspaceState: {
    setOpenCodeBootstrapped: vi.fn(),
    setOpenCodeReady: vi.fn(),
  },
  initOpenCodeClientMock: vi.fn(),
  sessionState: {
    sessionStatuses: {},
    pendingPermissions: [],
    pendingQuestions: [],
  } as {
    sessionStatuses: Record<string, { type: 'idle' | 'busy' | 'retry' } | undefined>
    pendingPermissions: unknown[]
    pendingQuestions: unknown[]
  },
  sessionSubscribers: [] as Array<(state: typeof sessionState) => void>,
  busySessionsMock: new Set<string>(),
}))
```

Add these mocks below the existing workspace mock:

```ts
vi.mock('@/stores/session', () => ({
  useSessionStore: {
    getState: () => sessionState,
    subscribe: (listener: (state: typeof sessionState) => void) => {
      sessionSubscribers.push(listener)
      return () => {
        const index = sessionSubscribers.indexOf(listener)
        if (index >= 0) sessionSubscribers.splice(index, 1)
      }
    },
  },
}))

vi.mock('@/stores/session-internals', () => ({
  busySessions: busySessionsMock,
}))
```

- [ ] **Step 2: Reset busy state in `beforeEach`**

Inside `beforeEach`, add:

```ts
sessionState.sessionStatuses = {}
sessionState.pendingPermissions = []
sessionState.pendingQuestions = []
sessionSubscribers.length = 0
busySessionsMock.clear()
```

- [ ] **Step 3: Update existing tests for the new return shape**

Change existing `requestOpenCodeRuntimeReload(...)` success expectations from:

```ts
{ url: 'http://127.0.0.1:4096' }
```

to:

```ts
{ status: 'restarted', url: 'http://127.0.0.1:4096' }
```

For the two-workspace test, expect:

```ts
await expect(Promise.all([first, second])).resolves.toEqual([
  { status: 'restarted', url: 'http://127.0.0.1:4096' },
  { status: 'restarted', url: 'http://127.0.0.1:4097' },
])
```

- [ ] **Step 4: Add a failing test for busy defer**

Append:

```ts
it('defers a reload request while a session is busy', async () => {
  sessionState.sessionStatuses = { 'session-1': { type: 'busy' } }

  const { requestOpenCodeRuntimeReload } = await import('../restart')
  await expect(
    requestOpenCodeRuntimeReload('/workspace/project', 'skills-file-change', {
      mode: 'defer-if-busy',
    }),
  ).resolves.toEqual({
    status: 'deferred',
    workspacePath: '/workspace/project',
    reason: 'skills-file-change',
  })

  expect(invokeMock).not.toHaveBeenCalledWith('stop_opencode', expect.anything())
  expect(invokeMock).not.toHaveBeenCalledWith('start_opencode', expect.anything())
})
```

- [ ] **Step 5: Add a failing test for pending flush after idle**

Append:

```ts
it('runs a deferred reload after the runtime becomes idle', async () => {
  sessionState.sessionStatuses = { 'session-1': { type: 'busy' } }
  invokeMock.mockImplementation((command: string) => {
    if (command === 'stop_opencode') return Promise.resolve(undefined)
    if (command === 'start_opencode') return Promise.resolve({ url: 'http://127.0.0.1:4096' })
    return Promise.resolve(undefined)
  })

  const { requestOpenCodeRuntimeReload } = await import('../restart')
  await requestOpenCodeRuntimeReload('/workspace/project', 'skills-file-change', {
    mode: 'defer-if-busy',
  })

  sessionState.sessionStatuses = { 'session-1': { type: 'idle' } }
  sessionSubscribers.forEach((listener) => listener(sessionState))
  await vi.advanceTimersByTimeAsync(500)
  await vi.waitFor(() => {
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(1)
  })
  expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'start_opencode')).toHaveLength(1)
})
```

- [ ] **Step 6: Add a failing test for coalescing**

Append:

```ts
it('coalesces repeated deferred requests for the same workspace', async () => {
  sessionState.sessionStatuses = { 'session-1': { type: 'busy' } }
  invokeMock.mockImplementation((command: string) => {
    if (command === 'stop_opencode') return Promise.resolve(undefined)
    if (command === 'start_opencode') return Promise.resolve({ url: 'http://127.0.0.1:4096' })
    return Promise.resolve(undefined)
  })

  const { requestOpenCodeRuntimeReload } = await import('../restart')
  await requestOpenCodeRuntimeReload('/workspace/project', 'skills-file-change', { mode: 'defer-if-busy' })
  await requestOpenCodeRuntimeReload('/workspace/project', 'team-skills-sync', { mode: 'defer-if-busy' })

  sessionState.sessionStatuses = {}
  sessionSubscribers.forEach((listener) => listener(sessionState))
  await vi.advanceTimersByTimeAsync(500)
  await vi.waitFor(() => {
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(1)
  })
})
```

- [ ] **Step 7: Run the focused test and confirm it fails**

Run:

```bash
pnpm --filter @teamclaw/app exec vitest run src/lib/opencode/__tests__/restart.test.ts
```

Expected: FAIL because `requestOpenCodeRuntimeReload` does not accept options yet and still restarts immediately.

---

### Task 2: Implement The Restart Coordinator

**Files:**
- Modify: `packages/app/src/lib/opencode/restart.ts`

- [ ] **Step 1: Add imports and event constants**

Update imports:

```ts
import { invoke } from '@tauri-apps/api/core'
import { initOpenCodeClient } from './sdk-client'
import { useWorkspaceStore } from '@/stores/workspace'
import { useSessionStore } from '@/stores/session'
import { busySessions } from '@/stores/session-internals'
```

Add below the `OpenCodeReloadReason` type:

```ts
export type OpenCodeReloadMode = 'immediate' | 'defer-if-busy'

export type OpenCodeRuntimeReloadEventDetail = {
  workspacePath: string
  reason: OpenCodeReloadReason
  url?: string
  error?: string
}

export type OpenCodeReloadRequestResult =
  | { status: 'restarted'; url: string }
  | { status: 'deferred'; workspacePath: string; reason: OpenCodeReloadReason }

export const OPENCODE_RUNTIME_RELOAD_DEFERRED_EVENT = 'opencode-runtime-reload-deferred'
export const OPENCODE_RUNTIME_RELOADED_EVENT = 'opencode-runtime-reloaded'
export const OPENCODE_RUNTIME_RELOAD_FAILED_EVENT = 'opencode-runtime-reload-failed'
```

- [ ] **Step 2: Add coordinator state and event helper**

Replace the existing in-flight map with:

```ts
const runtimeReloadsInFlight = new Map<string, Promise<RestartResult>>()
const pendingRuntimeReloads = new Map<string, { workspacePath: string; reason: OpenCodeReloadReason }>()
let unsubscribeSessionStore: (() => void) | null = null

function emitRuntimeReloadEvent(
  name: string,
  detail: OpenCodeRuntimeReloadEventDetail,
) {
  if (typeof window === 'undefined') return
  window.dispatchEvent(new CustomEvent(name, { detail }))
}
```

- [ ] **Step 3: Add busy detection**

Add:

```ts
function isRuntimeBusy(): boolean {
  const state = useSessionStore.getState()
  const hasBusyStatus = Object.values(state.sessionStatuses || {}).some(
    (status) => status?.type === 'busy' || status?.type === 'retry',
  )
  return (
    hasBusyStatus ||
    busySessions.size > 0 ||
    (state.pendingPermissions?.length ?? 0) > 0 ||
    (state.pendingQuestions?.length ?? 0) > 0
  )
}
```

- [ ] **Step 4: Extract the in-flight guarded restart**

Add this helper below `restartOpencode`:

```ts
function performRuntimeReload(
  workspacePath: string,
  reason: OpenCodeReloadReason,
): Promise<RestartResult> {
  const existingReload = runtimeReloadsInFlight.get(workspacePath)
  if (existingReload) {
    return existingReload
  }

  const reload = restartOpencode(workspacePath)
    .then((result) => {
      emitRuntimeReloadEvent(OPENCODE_RUNTIME_RELOADED_EVENT, {
        workspacePath,
        reason,
        url: result.url,
      })
      return result
    })
    .catch((error) => {
      emitRuntimeReloadEvent(OPENCODE_RUNTIME_RELOAD_FAILED_EVENT, {
        workspacePath,
        reason,
        error: error instanceof Error ? error.message : String(error),
      })
      throw error
    })
    .finally(() => {
      if (runtimeReloadsInFlight.get(workspacePath) === reload) {
        runtimeReloadsInFlight.delete(workspacePath)
      }
    })

  runtimeReloadsInFlight.set(workspacePath, reload)
  return reload
}
```

- [ ] **Step 5: Add pending flush and subscription**

Add:

```ts
function ensurePendingReloadSubscription() {
  if (unsubscribeSessionStore) return
  unsubscribeSessionStore = useSessionStore.subscribe(() => {
    void flushPendingRuntimeReloads()
  })
}

async function flushPendingRuntimeReloads() {
  if (pendingRuntimeReloads.size === 0 || isRuntimeBusy()) return

  for (const [workspacePath, pending] of Array.from(pendingRuntimeReloads.entries())) {
    if (runtimeReloadsInFlight.has(workspacePath)) continue
    pendingRuntimeReloads.delete(workspacePath)
    void performRuntimeReload(workspacePath, pending.reason)
  }
}
```

- [ ] **Step 6: Replace `requestOpenCodeRuntimeReload`**

Replace the existing exported function with:

```ts
export async function requestOpenCodeRuntimeReload(
  workspacePath: string,
  reason: OpenCodeReloadReason = 'manual',
  options: { mode?: OpenCodeReloadMode } = {},
): Promise<OpenCodeReloadRequestResult> {
  const mode = options.mode ?? 'immediate'
  const existingReload = runtimeReloadsInFlight.get(workspacePath)
  if (existingReload) {
    const result = await existingReload
    return { status: 'restarted', url: result.url }
  }

  if (mode === 'defer-if-busy' && isRuntimeBusy()) {
    pendingRuntimeReloads.set(workspacePath, { workspacePath, reason })
    ensurePendingReloadSubscription()
    emitRuntimeReloadEvent(OPENCODE_RUNTIME_RELOAD_DEFERRED_EVENT, {
      workspacePath,
      reason,
    })
    return { status: 'deferred', workspacePath, reason }
  }

  const result = await performRuntimeReload(workspacePath, reason)
  return { status: 'restarted', url: result.url }
}
```

- [ ] **Step 7: Run restart tests**

Run:

```bash
pnpm --filter @teamclaw/app exec vitest run src/lib/opencode/__tests__/restart.test.ts
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/app/src/lib/opencode/restart.ts packages/app/src/lib/opencode/__tests__/restart.test.ts
git commit -m "feat: defer opencode reloads while sessions run"
```

---

### Task 3: Wire Deferred Results Into Skills Settings

**Files:**
- Modify: `packages/app/src/components/settings/SkillsSection.tsx`
- Modify: `packages/app/src/components/settings/__tests__/SkillsSection.test.tsx`

- [ ] **Step 1: Update the restart mock shape in Skills tests**

In `beforeEach`, change:

```ts
mockRequestOpenCodeRuntimeReload.mockResolvedValue({ url: 'http://localhost:4096' })
```

to:

```ts
mockRequestOpenCodeRuntimeReload.mockResolvedValue({
  status: 'restarted',
  url: 'http://localhost:4096',
})
```

- [ ] **Step 2: Update existing Skills expectations for defer mode**

Replace expectations like:

```ts
expect(mockRequestOpenCodeRuntimeReload).toHaveBeenCalledWith('/workspace/project', 'skills-file-change')
```

with:

```ts
expect(mockRequestOpenCodeRuntimeReload).toHaveBeenCalledWith(
  '/workspace/project',
  'skills-file-change',
  { mode: 'defer-if-busy' },
)
```

For manual restart expectations, use:

```ts
expect(mockRequestOpenCodeRuntimeReload).toHaveBeenCalledWith(
  '/workspace/project',
  'manual',
  { mode: 'defer-if-busy' },
)
```

- [ ] **Step 3: Add a failing test for deferred auto restart UI**

Append near the existing auto-restart tests:

```ts
it('shows a pending restart message when auto-restart is deferred while a session is running', async () => {
  workspaceState.workspacePath = '/workspace/project'
  autoRestartState.enabled = true
  mockRequestOpenCodeRuntimeReload.mockResolvedValueOnce({
    status: 'deferred',
    workspacePath: '/workspace/project',
    reason: 'skills-file-change',
  })

  render(<SkillsSection />)

  const toggle = await screen.findByRole('switch', { name: 'Auto restart after Skills changes' })
  await waitFor(() => {
    expect(toggle.getAttribute('aria-checked')).toBe('true')
  })

  await act(async () => {
    window.dispatchEvent(new CustomEvent('skills-files-changed'))
  })

  expect(await screen.findByText('Detected Skill Changes')).toBeTruthy()
  expect(screen.getByText('OpenCode will restart after the current task finishes.')).toBeTruthy()
  expect(mockRequestOpenCodeRuntimeReload).toHaveBeenCalledWith(
    '/workspace/project',
    'skills-file-change',
    { mode: 'defer-if-busy' },
  )
})
```

- [ ] **Step 4: Add a failing test for clearing after coordinator success**

Append:

```ts
it('clears a pending Skills restart after the deferred runtime reload succeeds', async () => {
  workspaceState.workspacePath = '/workspace/project'
  autoRestartState.enabled = true
  mockRequestOpenCodeRuntimeReload.mockResolvedValueOnce({
    status: 'deferred',
    workspacePath: '/workspace/project',
    reason: 'skills-file-change',
  })

  render(<SkillsSection />)

  await screen.findByRole('switch', { name: 'Auto restart after Skills changes' })
  await act(async () => {
    window.dispatchEvent(new CustomEvent('skills-files-changed'))
  })
  expect(await screen.findByText('OpenCode will restart after the current task finishes.')).toBeTruthy()

  await act(async () => {
    window.dispatchEvent(new CustomEvent('opencode-runtime-reloaded', {
      detail: {
        workspacePath: '/workspace/project',
        reason: 'skills-file-change',
        url: 'http://localhost:4096',
      },
    }))
  })

  await waitFor(() => {
    expect(screen.queryByText('Detected Skill Changes')).toBeNull()
  })
})
```

- [ ] **Step 5: Update imports in SkillsSection**

Change the restart import to include event constants and result type:

```ts
import {
  OPENCODE_RUNTIME_RELOAD_FAILED_EVENT,
  OPENCODE_RUNTIME_RELOADED_EVENT,
  requestOpenCodeRuntimeReload,
  type OpenCodeReloadReason,
  type OpenCodeReloadRequestResult,
  type OpenCodeRuntimeReloadEventDetail,
} from '@/lib/opencode/restart'
```

- [ ] **Step 6: Add pending state**

Near existing restart state:

```ts
const [isRestartPending, setIsRestartPending] = React.useState(false)
```

- [ ] **Step 7: Return coordinator results from `restartOpenCodeInstance`**

Replace the body with:

```ts
const restartOpenCodeInstance = React.useCallback(
  async (options?: RestartOptions): Promise<OpenCodeReloadRequestResult | undefined> => {
    if (!workspacePath) return undefined
    const result = await requestOpenCodeRuntimeReload(
      workspacePath,
      options?.reason ?? 'manual',
      { mode: 'defer-if-busy' },
    )
    if (result.status === 'restarted' && !options?.preserveChangeFlag) {
      setHasChanges(false)
    }
    return result
  },
  [workspacePath],
)
```

- [ ] **Step 8: Handle deferred auto restart**

In `runSkillsAutoRestart`, replace the success block with:

```ts
const result = await restartOpenCodeInstance({ preserveChangeFlag: true, reason: 'skills-file-change' })
if (result?.status === 'deferred') {
  setIsRestartPending(true)
  return
}
setIsRestartPending(false)
setHasSkillRuntimeChanges(false)
```

- [ ] **Step 9: Handle deferred manual restart**

In `handleRestartOpenCode`, replace the success block with:

```ts
const result = await restartOpenCodeInstance({ reason: 'manual' })
if (result?.status === 'deferred') {
  setIsRestartPending(true)
  return
}
setIsRestartPending(false)
setHasSkillRuntimeChanges(false)
```

- [ ] **Step 10: Do not close ZIP import dialog on deferred restart failure**

In `importSkillFromZip`, replace:

```ts
await restartOpenCodeInstance()
```

with:

```ts
await restartOpenCodeInstance({ reason: 'skills-file-change' })
```

The result can be ignored because the coordinator and shared UI state own pending/success. Keep the existing dialog close behavior.

- [ ] **Step 11: Listen for coordinator events**

Add an effect near the Skills changed event effect:

```ts
React.useEffect(() => {
  if (!workspacePath) return

  const isSkillsReason = (reason: OpenCodeReloadReason) =>
    reason === 'skills-file-change' ||
    reason === 'skills-permission-change' ||
    reason === 'team-skills-sync' ||
    reason === 'manual'

  const onReloaded = (event: Event) => {
    const detail = (event as CustomEvent<OpenCodeRuntimeReloadEventDetail>).detail
    if (!detail || detail.workspacePath !== workspacePath || !isSkillsReason(detail.reason)) return
    setIsRestartPending(false)
    setHasSkillRuntimeChanges(false)
    setHasChanges(false)
    setRestartError(null)
  }

  const onFailed = (event: Event) => {
    const detail = (event as CustomEvent<OpenCodeRuntimeReloadEventDetail>).detail
    if (!detail || detail.workspacePath !== workspacePath || !isSkillsReason(detail.reason)) return
    setIsRestartPending(false)
    setRestartError(detail.error ?? 'Failed to restart OpenCode')
  }

  window.addEventListener(OPENCODE_RUNTIME_RELOADED_EVENT, onReloaded)
  window.addEventListener(OPENCODE_RUNTIME_RELOAD_FAILED_EVENT, onFailed)
  return () => {
    window.removeEventListener(OPENCODE_RUNTIME_RELOADED_EVENT, onReloaded)
    window.removeEventListener(OPENCODE_RUNTIME_RELOAD_FAILED_EVENT, onFailed)
  }
}, [workspacePath])
```

- [ ] **Step 12: Update restart prompt copy for pending**

In the `hasSkillRuntimeChanges` prompt, replace the body paragraph with:

```tsx
<p className="text-sm text-sky-700 dark:text-sky-300 mt-1">
  {isRestartPending
    ? t('settings.skills.restartPendingUntilIdle', 'OpenCode will restart after the current task finishes.')
    : t('settings.skills.restartToLoadNewSkills', 'New or updated skills were detected. Restart OpenCode to load them in the current runtime.')}
</p>
```

Disable the button while pending:

```tsx
disabled={isRestarting || isRestartPending || !workspacePath}
```

- [ ] **Step 13: Run Skills tests**

Run:

```bash
pnpm --filter @teamclaw/app exec vitest run src/components/settings/__tests__/SkillsSection.test.tsx
```

Expected: PASS.

- [ ] **Step 14: Commit**

```bash
git add packages/app/src/components/settings/SkillsSection.tsx packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
git commit -m "feat: show deferred skills restart state"
```

---

### Task 4: Wire Deferred Results Into ChatPanel Banner

**Files:**
- Modify: `packages/app/src/components/chat/ChatPanel.tsx`
- Modify: `packages/app/src/components/chat/__tests__/ChatPanel-submission.test.tsx`

- [ ] **Step 1: Update restart import in ChatPanel**

Replace:

```ts
import { requestOpenCodeRuntimeReload } from "@/lib/opencode/restart";
```

with:

```ts
import {
  OPENCODE_RUNTIME_RELOADED_EVENT,
  requestOpenCodeRuntimeReload,
  type OpenCodeRuntimeReloadEventDetail,
} from "@/lib/opencode/restart";
```

- [ ] **Step 2: Listen for generic runtime reload success**

In the Skills prompt effect, keep `SKILLS_CHANGED_EVENT`, but replace the old runtime-reloaded listener with:

```ts
const onOpenCodeRuntimeReloaded = (event: Event) => {
  const detail = (event as CustomEvent<OpenCodeRuntimeReloadEventDetail>).detail;
  if (!detail || detail.workspacePath !== workspacePath) return;
  if (
    detail.reason !== 'skills-file-change' &&
    detail.reason !== 'skills-permission-change' &&
    detail.reason !== 'team-skills-sync' &&
    detail.reason !== 'manual'
  ) {
    return;
  }
  setHasSkillRestartPrompt(false);
  setIsRestartingSkillsRuntime(false);
};
window.addEventListener(OPENCODE_RUNTIME_RELOADED_EVENT, onOpenCodeRuntimeReloaded);
```

and remove it in cleanup. Add `workspacePath` to the effect dependency array.

- [ ] **Step 3: Request manual banner restart with defer mode**

Replace:

```ts
await requestOpenCodeRuntimeReload(workspacePath, 'manual');
window.dispatchEvent(new CustomEvent(SKILLS_RUNTIME_RELOADED_EVENT));
```

with:

```ts
const result = await requestOpenCodeRuntimeReload(workspacePath, 'manual', {
  mode: 'defer-if-busy',
});
if (result.status === 'deferred') {
  return;
}
```

The coordinator emits `OPENCODE_RUNTIME_RELOADED_EVENT` after an actual restart.

- [ ] **Step 4: Update ChatPanel test mock return shape**

In `ChatPanel-submission.test.tsx`, update the restart mock:

```ts
requestOpenCodeRuntimeReload: vi.fn(async () => ({
  status: 'restarted',
  url: 'http://localhost:4096',
})),
```

- [ ] **Step 5: Add a failing ChatPanel deferred test**

Add a test near the existing runtime-reloaded test:

```ts
it('keeps the Skills restart prompt visible when manual restart is deferred', async () => {
  mockRequestOpenCodeRuntimeReload.mockResolvedValueOnce({
    status: 'deferred',
    workspacePath: '/workspace/project',
    reason: 'manual',
  })

  render(<ChatPanel />)
  await act(async () => {
    window.dispatchEvent(new CustomEvent('skills-files-changed'))
  })

  fireEvent.click(await screen.findByRole('button', { name: 'Restart' }))

  await waitFor(() => {
    expect(mockRequestOpenCodeRuntimeReload).toHaveBeenCalledWith(
      '/workspace/project',
      'manual',
      { mode: 'defer-if-busy' },
    )
  })
  expect(screen.getByText('Detected new skills')).toBeTruthy()
})
```

- [ ] **Step 6: Add a generic reload success test**

Add:

```ts
it('clears the Skills restart prompt when the runtime reload coordinator reports success', async () => {
  render(<ChatPanel />)
  await act(async () => {
    window.dispatchEvent(new CustomEvent('skills-files-changed'))
  })
  expect(await screen.findByText('Detected new skills')).toBeTruthy()

  await act(async () => {
    window.dispatchEvent(new CustomEvent('opencode-runtime-reloaded', {
      detail: {
        workspacePath: '/workspace/project',
        reason: 'skills-file-change',
        url: 'http://localhost:4096',
      },
    }))
  })

  await waitFor(() => {
    expect(screen.queryByText('Detected new skills')).toBeNull()
  })
})
```

- [ ] **Step 7: Run ChatPanel tests**

Run:

```bash
pnpm --filter @teamclaw/app exec vitest run src/components/chat/__tests__/ChatPanel-submission.test.tsx
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/app/src/components/chat/ChatPanel.tsx packages/app/src/components/chat/__tests__/ChatPanel-submission.test.tsx
git commit -m "feat: defer chat skills restart action"
```

---

### Task 5: Full Focused Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run focused frontend tests**

Run:

```bash
pnpm --filter @teamclaw/app exec vitest run \
  src/lib/opencode/__tests__/restart.test.ts \
  src/components/settings/__tests__/SkillsSection.test.tsx \
  src/components/chat/__tests__/ChatPanel-submission.test.tsx
```

Expected: PASS.

- [ ] **Step 2: Run typecheck**

Run:

```bash
pnpm --filter @teamclaw/app exec tsc --noEmit
```

Expected: PASS.

- [ ] **Step 3: Check worktree state**

Run:

```bash
git status --short
```

Expected: clean working tree.

---

## Self-Review

- Spec coverage: The plan covers busy detection, deferred restart, coalescing, UI pending state, ChatPanel clearing, and focused tests.
- Blank-fill scan: No marker text, vague test instructions, or undefined follow-up tasks remain.
- Type consistency: The result type is `OpenCodeReloadRequestResult`, the mode is `OpenCodeReloadMode`, and event detail type is `OpenCodeRuntimeReloadEventDetail` throughout.
