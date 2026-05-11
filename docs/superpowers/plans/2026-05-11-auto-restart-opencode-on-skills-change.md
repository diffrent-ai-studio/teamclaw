# Auto Restart OpenCode On Skills Change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a disabled-by-default global setting that automatically restarts OpenCode after Skills changes when enabled, while preserving the manual restart fallback.

**Architecture:** Store the preference in the Rust global app settings file so the value is backend-readable for remote server follow-up work. Expose small frontend helpers for reading/writing the setting and for requesting a deduplicated OpenCode runtime reload. Update `SkillsSection` to show the toggle and to auto-restart only when the global setting is enabled.

**Tech Stack:** Rust Tauri commands, React, Zustand-backed workspace state, Vitest, Testing Library.

---

## File Structure

- Modify `src-tauri/src/commands/app_settings.rs`
  - Owns global app settings stored in `~/.teamclaw/app-settings.json`.
  - Add boolean read/write helpers and Tauri commands for `autoRestartOpencodeOnSkillsChange`.

- Modify `src-tauri/src/lib.rs`
  - Register the new Tauri commands.

- Create `packages/app/src/lib/opencode/runtime-settings.ts`
  - Frontend API for the global auto-restart setting.
  - Uses Rust commands in Tauri and a global localStorage fallback in web/test mode.

- Modify `packages/app/src/lib/opencode/restart.ts`
  - Add `requestOpenCodeRuntimeReload()` and `OpenCodeReloadReason`.
  - Deduplicate concurrent reload requests.
  - Keep `restartOpencode()` for existing callers.

- Modify `packages/app/src/components/settings/SkillsSection.tsx`
  - Add the global toggle UI.
  - Load/persist the setting.
  - Auto-restart after Skills changes when enabled.
  - Keep existing manual restart prompt on disabled or failed auto-restart paths.

- Modify `packages/app/src/components/settings/__tests__/SkillsSection.test.tsx`
  - Cover default-off behavior, toggle persistence, auto-restart success, failure fallback, and duplicate event coalescing.

- Create `packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts`
  - Cover global default, Tauri read/write, and localStorage fallback.

- Create `packages/app/src/lib/opencode/__tests__/restart.test.ts`
  - Cover reload deduplication.

---

### Task 1: Backend Global Setting

**Files:**
- Modify: `src-tauri/src/commands/app_settings.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add pure setting helpers and tests**

In `src-tauri/src/commands/app_settings.rs`, add this constant near the existing setting keys:

```rust
const AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY: &str =
    "autoRestartOpencodeOnSkillsChange";
```

Add these helpers below `read_settings_value()`:

```rust
fn read_bool_setting_from_value(value: &Value, key: &str, default_value: bool) -> bool {
    value
        .get(key)
        .and_then(Value::as_bool)
        .unwrap_or(default_value)
}

fn write_setting_value(key: &str, value: Value) -> Result<(), String> {
    let mut settings = match read_settings_value() {
        Value::Object(map) => map,
        _ => Map::new(),
    };
    settings.insert(key.to_string(), value);

    let path = settings_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create settings directory: {e}"))?;
    }
    let content = serde_json::to_string_pretty(&Value::Object(settings))
        .map_err(|e| format!("Failed to serialize settings: {e}"))?;
    std::fs::write(&path, content).map_err(|e| format!("Failed to write settings: {e}"))
}
```

Refactor `write_spotlight_shortcut_setting()` to use the shared writer:

```rust
fn write_spotlight_shortcut_setting(shortcut: &str) -> Result<(), String> {
    write_setting_value(
        SPOTLIGHT_SHORTCUT_KEY,
        Value::String(shortcut.to_string()),
    )
}
```

Add tests inside the existing `#[cfg(test)] mod tests`:

```rust
#[test]
fn boolean_setting_defaults_when_missing() {
    let value = Value::Object(Map::new());

    assert!(!read_bool_setting_from_value(
        &value,
        AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY,
        false,
    ));
}

#[test]
fn boolean_setting_reads_explicit_true() {
    let value = serde_json::json!({
        "autoRestartOpencodeOnSkillsChange": true
    });

    assert!(read_bool_setting_from_value(
        &value,
        AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY,
        false,
    ));
}

#[test]
fn boolean_setting_ignores_wrong_type() {
    let value = serde_json::json!({
        "autoRestartOpencodeOnSkillsChange": "true"
    });

    assert!(!read_bool_setting_from_value(
        &value,
        AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY,
        false,
    ));
}
```

- [ ] **Step 2: Run backend tests and verify the new tests pass**

Run:

```bash
cargo test -p teamclaw app_settings --manifest-path src-tauri/Cargo.toml
```

Expected: PASS. If the package name differs, run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml app_settings
```

Expected: PASS with the three new boolean setting tests passing.

- [ ] **Step 3: Add Tauri commands for reading and writing the global setting**

In `src-tauri/src/commands/app_settings.rs`, add:

```rust
pub fn read_auto_restart_opencode_on_skills_change() -> bool {
    read_bool_setting_from_value(
        &read_settings_value(),
        AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY,
        false,
    )
}

#[tauri::command]
pub fn get_auto_restart_opencode_on_skills_change() -> bool {
    read_auto_restart_opencode_on_skills_change()
}

#[tauri::command]
pub fn set_auto_restart_opencode_on_skills_change(enabled: bool) -> Result<bool, String> {
    write_setting_value(
        AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_KEY,
        Value::Bool(enabled),
    )?;
    Ok(enabled)
}
```

In `src-tauri/src/lib.rs`, register the commands next to the existing app settings commands:

```rust
commands::app_settings::get_spotlight_shortcut,
commands::app_settings::set_spotlight_shortcut,
commands::app_settings::get_auto_restart_opencode_on_skills_change,
commands::app_settings::set_auto_restart_opencode_on_skills_change,
```

- [ ] **Step 4: Run backend tests again**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml app_settings
```

Expected: PASS.

- [ ] **Step 5: Commit backend setting**

```bash
git add src-tauri/src/commands/app_settings.rs src-tauri/src/lib.rs
git commit -m "feat: add global skills restart setting"
```

---

### Task 2: Frontend Setting API

**Files:**
- Create: `packages/app/src/lib/opencode/runtime-settings.ts`
- Create: `packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts`

- [ ] **Step 1: Write failing tests for frontend setting API**

Create `packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest'

const { invokeMock, isTauriState } = vi.hoisted(() => ({
  invokeMock: vi.fn(),
  isTauriState: { value: false },
}))

vi.mock('@tauri-apps/api/core', () => ({ invoke: invokeMock }))
vi.mock('@/lib/utils', () => ({ isTauri: () => isTauriState.value }))
vi.mock('@/lib/build-config', () => ({ appShortName: 'teamclaw' }))

describe('runtime settings', () => {
  beforeEach(() => {
    invokeMock.mockReset()
    localStorage.clear()
    isTauriState.value = false
  })

  it('defaults auto restart to false in web mode', async () => {
    const { getAutoRestartOpencodeOnSkillsChange } = await import('../runtime-settings')

    await expect(getAutoRestartOpencodeOnSkillsChange()).resolves.toBe(false)
  })

  it('persists auto restart globally in web mode', async () => {
    const {
      AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_STORAGE_KEY,
      getAutoRestartOpencodeOnSkillsChange,
      setAutoRestartOpencodeOnSkillsChange,
    } = await import('../runtime-settings')

    await expect(setAutoRestartOpencodeOnSkillsChange(true)).resolves.toBe(true)

    expect(localStorage.getItem(AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_STORAGE_KEY)).toBe('true')
    await expect(getAutoRestartOpencodeOnSkillsChange()).resolves.toBe(true)
  })

  it('reads from Tauri app settings when available', async () => {
    isTauriState.value = true
    invokeMock.mockResolvedValueOnce(true)
    const { getAutoRestartOpencodeOnSkillsChange } = await import('../runtime-settings')

    await expect(getAutoRestartOpencodeOnSkillsChange()).resolves.toBe(true)

    expect(invokeMock).toHaveBeenCalledWith('get_auto_restart_opencode_on_skills_change')
  })

  it('writes to Tauri app settings when available', async () => {
    isTauriState.value = true
    invokeMock.mockResolvedValueOnce(false)
    const { setAutoRestartOpencodeOnSkillsChange } = await import('../runtime-settings')

    await expect(setAutoRestartOpencodeOnSkillsChange(false)).resolves.toBe(false)

    expect(invokeMock).toHaveBeenCalledWith(
      'set_auto_restart_opencode_on_skills_change',
      { enabled: false },
    )
  })
})
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
pnpm --filter app test -- packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts
```

Expected: FAIL because `runtime-settings.ts` does not exist.

- [ ] **Step 3: Implement the frontend setting API**

Create `packages/app/src/lib/opencode/runtime-settings.ts`:

```ts
import { invoke } from '@tauri-apps/api/core'
import { appShortName } from '@/lib/build-config'
import { isTauri } from '@/lib/utils'

export const AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_STORAGE_KEY =
  `${appShortName}-auto-restart-opencode-on-skills-change`

export async function getAutoRestartOpencodeOnSkillsChange(): Promise<boolean> {
  if (isTauri()) {
    return invoke<boolean>('get_auto_restart_opencode_on_skills_change')
  }

  try {
    return localStorage.getItem(AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_STORAGE_KEY) === 'true'
  } catch {
    return false
  }
}

export async function setAutoRestartOpencodeOnSkillsChange(enabled: boolean): Promise<boolean> {
  if (isTauri()) {
    return invoke<boolean>('set_auto_restart_opencode_on_skills_change', { enabled })
  }

  try {
    localStorage.setItem(
      AUTO_RESTART_OPENCODE_ON_SKILLS_CHANGE_STORAGE_KEY,
      String(enabled),
    )
  } catch {
    // Keep web fallback best-effort only.
  }
  return enabled
}
```

- [ ] **Step 4: Run frontend setting tests**

Run:

```bash
pnpm --filter app test -- packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit frontend setting API**

```bash
git add packages/app/src/lib/opencode/runtime-settings.ts packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts
git commit -m "feat: add skills restart runtime setting api"
```

---

### Task 3: Runtime Reload Abstraction

**Files:**
- Modify: `packages/app/src/lib/opencode/restart.ts`
- Create: `packages/app/src/lib/opencode/__tests__/restart.test.ts`

- [ ] **Step 1: Write failing reload dedupe tests**

Create `packages/app/src/lib/opencode/__tests__/restart.test.ts`:

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest'

const { invokeMock, workspaceState, initOpenCodeClientMock } = vi.hoisted(() => ({
  invokeMock: vi.fn(),
  workspaceState: {
    setOpenCodeBootstrapped: vi.fn(),
    setOpenCodeReady: vi.fn(),
  },
  initOpenCodeClientMock: vi.fn(),
}))

vi.mock('@tauri-apps/api/core', () => ({ invoke: invokeMock }))
vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: {
    getState: () => workspaceState,
  },
}))
vi.mock('../sdk-client', () => ({ initOpenCodeClient: initOpenCodeClientMock }))

describe('OpenCode runtime reload', () => {
  beforeEach(() => {
    vi.resetModules()
    invokeMock.mockReset()
    workspaceState.setOpenCodeBootstrapped.mockReset()
    workspaceState.setOpenCodeReady.mockReset()
    initOpenCodeClientMock.mockReset()
  })

  it('deduplicates concurrent reload requests for the same runtime', async () => {
    let resolveStart: (value: { url: string }) => void = () => {}
    invokeMock.mockImplementation((command: string) => {
      if (command === 'stop_opencode') return Promise.resolve(undefined)
      if (command === 'start_opencode') {
        return new Promise((resolve) => {
          resolveStart = resolve as (value: { url: string }) => void
        })
      }
      return Promise.resolve(undefined)
    })

    const { requestOpenCodeRuntimeReload } = await import('../restart')
    const first = requestOpenCodeRuntimeReload('/workspace/project', 'skills-file-change')
    const second = requestOpenCodeRuntimeReload('/workspace/project', 'team-skills-sync')

    resolveStart({ url: 'http://127.0.0.1:4096' })

    await expect(Promise.all([first, second])).resolves.toEqual([
      { url: 'http://127.0.0.1:4096' },
      { url: 'http://127.0.0.1:4096' },
    ])

    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(1)
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'start_opencode')).toHaveLength(1)
  })
})
```

- [ ] **Step 2: Run the reload test and verify it fails**

Run:

```bash
pnpm --filter app test -- packages/app/src/lib/opencode/__tests__/restart.test.ts
```

Expected: FAIL because `requestOpenCodeRuntimeReload` is not exported yet.

- [ ] **Step 3: Implement the reload abstraction**

In `packages/app/src/lib/opencode/restart.ts`, add these exports:

```ts
export type OpenCodeReloadReason =
  | 'skills-file-change'
  | 'skills-permission-change'
  | 'team-skills-sync'
  | 'manual'

let runtimeReloadInFlight: Promise<RestartResult> | null = null

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
```

Keep `restartOpencode()` unchanged so existing callers remain compatible.

- [ ] **Step 4: Run reload tests**

Run:

```bash
pnpm --filter app test -- packages/app/src/lib/opencode/__tests__/restart.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit reload abstraction**

```bash
git add packages/app/src/lib/opencode/restart.ts packages/app/src/lib/opencode/__tests__/restart.test.ts
git commit -m "feat: add opencode runtime reload request"
```

---

### Task 4: Skills Settings Toggle And Auto Restart

**Files:**
- Modify: `packages/app/src/components/settings/SkillsSection.tsx`
- Modify: `packages/app/src/components/settings/__tests__/SkillsSection.test.tsx`

- [ ] **Step 1: Extend SkillsSection test mocks**

In `packages/app/src/components/settings/__tests__/SkillsSection.test.tsx`, add hoisted mocks:

```ts
const {
  autoRestartState,
  mockGetAutoRestart,
  mockSetAutoRestart,
  mockRequestRuntimeReload,
} = vi.hoisted(() => ({
  autoRestartState: { enabled: false },
  mockGetAutoRestart: vi.fn(async () => autoRestartState.enabled),
  mockSetAutoRestart: vi.fn(async (enabled: boolean) => {
    autoRestartState.enabled = enabled
    return enabled
  }),
  mockRequestRuntimeReload: vi.fn(async () => ({ url: 'http://127.0.0.1:4096' })),
}))
```

Add module mocks before importing `SkillsSection`:

```ts
vi.mock('@/lib/opencode/runtime-settings', () => ({
  getAutoRestartOpencodeOnSkillsChange: mockGetAutoRestart,
  setAutoRestartOpencodeOnSkillsChange: mockSetAutoRestart,
}))

vi.mock('@/lib/opencode/restart', () => ({
  restartOpencode: mockRequestRuntimeReload,
  requestOpenCodeRuntimeReload: mockRequestRuntimeReload,
}))
```

Reset them in `beforeEach()`:

```ts
autoRestartState.enabled = false
mockGetAutoRestart.mockClear()
mockSetAutoRestart.mockClear()
mockRequestRuntimeReload.mockReset()
mockRequestRuntimeReload.mockResolvedValue({ url: 'http://127.0.0.1:4096' })
```

- [ ] **Step 2: Add failing tests for default-off and toggle persistence**

Add these tests:

```ts
it('loads auto restart disabled by default', async () => {
  workspaceState.workspacePath = '/workspace/project'

  render(<SkillsSection />)

  const toggle = await screen.findByRole('switch', {
    name: 'Auto restart after Skills changes',
  })
  expect(toggle.getAttribute('aria-checked')).toBe('false')
})

it('persists the global auto restart toggle', async () => {
  workspaceState.workspacePath = '/workspace/project'

  render(<SkillsSection />)

  const toggle = await screen.findByRole('switch', {
    name: 'Auto restart after Skills changes',
  })
  fireEvent.click(toggle)

  await waitFor(() => {
    expect(mockSetAutoRestart).toHaveBeenCalledWith(true)
  })
})
```

Run:

```bash
pnpm --filter app test -- packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
```

Expected: FAIL because the switch does not exist.

- [ ] **Step 3: Add the toggle UI and setting load/save**

In `SkillsSection.tsx`, update imports:

```ts
import { RotateCw } from 'lucide-react'
import { ToggleSwitch } from './shared'
import {
  getAutoRestartOpencodeOnSkillsChange,
  setAutoRestartOpencodeOnSkillsChange,
} from '@/lib/opencode/runtime-settings'
```

If `RefreshCw` is already imported, use it instead of adding `RotateCw`.

Add state near the existing restart state:

```ts
const [autoRestartSkillsChanges, setAutoRestartSkillsChanges] = React.useState(false)
const [autoRestartSettingLoaded, setAutoRestartSettingLoaded] = React.useState(false)
const [autoRestartSettingError, setAutoRestartSettingError] = React.useState<string | null>(null)
```

Load the setting:

```ts
React.useEffect(() => {
  let cancelled = false

  void getAutoRestartOpencodeOnSkillsChange()
    .then((enabled) => {
      if (cancelled) return
      setAutoRestartSkillsChanges(enabled)
      setAutoRestartSettingError(null)
    })
    .catch((err) => {
      if (cancelled) return
      setAutoRestartSkillsChanges(false)
      setAutoRestartSettingError(err instanceof Error ? err.message : String(err))
    })
    .finally(() => {
      if (!cancelled) setAutoRestartSettingLoaded(true)
    })

  return () => {
    cancelled = true
  }
}, [])
```

Add a save handler:

```ts
const handleAutoRestartSkillsChangesChange = React.useCallback(async (enabled: boolean) => {
  setAutoRestartSkillsChanges(enabled)
  setAutoRestartSettingError(null)

  try {
    const persisted = await setAutoRestartOpencodeOnSkillsChange(enabled)
    setAutoRestartSkillsChanges(persisted)
  } catch (err) {
    setAutoRestartSkillsChanges((prev) => !prev)
    setAutoRestartSettingError(err instanceof Error ? err.message : String(err))
  }
}, [])
```

Render this `SettingCard` near the top of the installed Skills panel, before restart prompts:

```tsx
{!embeddedConsole && (
  <SettingCard>
    <div className="flex items-center justify-between gap-4">
      <div className="space-y-1">
        <label
          id="auto-restart-skills-label"
          className="text-sm font-medium flex items-center gap-2"
        >
          <RefreshCw className="h-4 w-4 text-muted-foreground" />
          {t('settings.skills.autoRestartOnChange', 'Auto restart after Skills changes')}
        </label>
        <p className="text-xs text-muted-foreground">
          {t(
            'settings.skills.autoRestartOnChangeDesc',
            'Automatically restart OpenCode after skills are installed, edited, deleted, or synced. Disabled by default.',
          )}
        </p>
        {autoRestartSettingError && (
          <p className="text-xs text-destructive" role="alert">
            {autoRestartSettingError}
          </p>
        )}
      </div>
      <ToggleSwitch
        enabled={autoRestartSkillsChanges}
        onChange={handleAutoRestartSkillsChangesChange}
        disabled={!autoRestartSettingLoaded}
        aria-labelledby="auto-restart-skills-label"
      />
    </div>
  </SettingCard>
)}
```

Because `ToggleSwitch` does not currently accept `aria-labelledby`, update `ToggleSwitch` props in `packages/app/src/components/settings/shared/ToggleSwitch.tsx`:

```ts
export function ToggleSwitch({
  enabled,
  onChange,
  disabled = false,
  ...buttonProps
}: {
  enabled: boolean
  onChange: (v: boolean) => void
  disabled?: boolean
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...buttonProps}
      type="button"
      role="switch"
      aria-checked={enabled}
      onClick={() => !disabled && onChange(!enabled)}
      disabled={disabled}
      className={cn(
        "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full border border-border/80 shadow-inner transition-colors",
        enabled ? "bg-primary" : "bg-muted",
        disabled && "cursor-not-allowed opacity-50",
        buttonProps.className,
      )}
    >
```

- [ ] **Step 4: Run SkillsSection tests**

Run:

```bash
pnpm --filter app test -- packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
```

Expected: PASS for the new toggle tests.

- [ ] **Step 5: Add failing tests for Skills change behavior**

Add these tests:

```ts
it('shows manual restart prompt without auto restart when skills change and setting is off', async () => {
  workspaceState.workspacePath = '/workspace/project'
  autoRestartState.enabled = false

  render(<SkillsSection />)

  window.dispatchEvent(new CustomEvent('skills-files-changed'))

  expect(await screen.findByText('Detected Skill Changes')).toBeTruthy()
  expect(mockRequestRuntimeReload).not.toHaveBeenCalled()
})

it('automatically restarts when skills change and setting is on', async () => {
  workspaceState.workspacePath = '/workspace/project'
  autoRestartState.enabled = true

  render(<SkillsSection />)

  await screen.findByRole('switch', { name: 'Auto restart after Skills changes' })
  window.dispatchEvent(new CustomEvent('skills-files-changed'))

  await waitFor(() => {
    expect(mockRequestRuntimeReload).toHaveBeenCalledWith(
      '/workspace/project',
      'skills-file-change',
    )
  })
  expect(screen.queryByText('Detected Skill Changes')).toBeNull()
})

it('keeps manual restart prompt when automatic restart fails', async () => {
  workspaceState.workspacePath = '/workspace/project'
  autoRestartState.enabled = true
  mockRequestRuntimeReload.mockRejectedValueOnce(new Error('restart failed'))

  render(<SkillsSection />)

  await screen.findByRole('switch', { name: 'Auto restart after Skills changes' })
  window.dispatchEvent(new CustomEvent('skills-files-changed'))

  expect(await screen.findByText('Detected Skill Changes')).toBeTruthy()
  expect(await screen.findByText(/restart failed/)).toBeTruthy()
})
```

Run:

```bash
pnpm --filter app test -- packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
```

Expected: FAIL because automatic restart behavior is not implemented.

- [ ] **Step 6: Implement automatic restart behavior**

In `SkillsSection.tsx`, change the restart import:

```ts
import { requestOpenCodeRuntimeReload, type OpenCodeReloadReason } from '@/lib/opencode/restart'
```

Update `RestartOptions`:

```ts
type RestartOptions = {
  preserveChangeFlag?: boolean
  reason?: OpenCodeReloadReason
}
```

Add a ref to avoid stale event-listener state:

```ts
const autoRestartSkillsChangesRef = React.useRef(false)
React.useEffect(() => {
  autoRestartSkillsChangesRef.current = autoRestartSkillsChanges
}, [autoRestartSkillsChanges])
```

Update `restartOpenCodeInstance`:

```ts
const restartOpenCodeInstance = React.useCallback(
  async (options?: RestartOptions) => {
    if (!workspacePath) return
    await requestOpenCodeRuntimeReload(workspacePath, options?.reason ?? 'manual')
    if (!options?.preserveChangeFlag) {
      setHasChanges(false)
    }
  },
  [workspacePath]
)
```

Add a helper for Skills runtime changes:

```ts
const handleSkillsRuntimeChanged = React.useCallback(async () => {
  setHasSkillRuntimeChanges(true)
  setRestartError(null)
  void loadSkills()

  if (!autoRestartSkillsChangesRef.current || !workspacePath) {
    return
  }

  setIsRestarting(true)
  try {
    await restartOpenCodeInstance({
      preserveChangeFlag: true,
      reason: 'skills-file-change',
    })
    setHasSkillRuntimeChanges(false)
  } catch (err) {
    console.error('[SkillsSection] Failed to auto-restart OpenCode:', err)
    setRestartError(err instanceof Error ? err.message : String(err))
  } finally {
    setIsRestarting(false)
  }
}, [loadSkills, restartOpenCodeInstance, workspacePath])
```

Replace the current `onSkillsChanged` listener body:

```ts
const onSkillsChanged = () => {
  void handleSkillsRuntimeChanged()
}
```

Keep `handleRestartOpenCode()` for manual retry, but pass reason:

```ts
await restartOpenCodeInstance({ reason: 'manual' })
```

- [ ] **Step 7: Run SkillsSection tests**

Run:

```bash
pnpm --filter app test -- packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
```

Expected: PASS.

- [ ] **Step 8: Commit SkillsSection behavior**

```bash
git add \
  packages/app/src/components/settings/SkillsSection.tsx \
  packages/app/src/components/settings/shared/ToggleSwitch.tsx \
  packages/app/src/components/settings/__tests__/SkillsSection.test.tsx
git commit -m "feat: auto restart opencode after skills changes"
```

---

### Task 5: Full Verification

**Files:**
- No code files expected unless verification exposes a defect.

- [ ] **Step 1: Run focused frontend tests**

Run:

```bash
pnpm --filter app test -- \
  packages/app/src/components/settings/__tests__/SkillsSection.test.tsx \
  packages/app/src/lib/opencode/__tests__/runtime-settings.test.ts \
  packages/app/src/lib/opencode/__tests__/restart.test.ts
```

Expected: PASS.

- [ ] **Step 2: Run focused backend tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml app_settings
```

Expected: PASS.

- [ ] **Step 3: Run typecheck or the repo's frontend verification command**

Inspect `package.json` scripts. Prefer the narrowest existing typecheck/test command that covers `packages/app`:

```bash
pnpm --filter app typecheck
```

If that script does not exist, run:

```bash
pnpm --filter app test --run
```

Expected: PASS.

- [ ] **Step 4: Check git status**

Run:

```bash
git status --short
```

Expected:

- Only intentional committed changes from the task branch should be present.
- Pre-existing local modifications such as `build.config.local.json` and `opencode.json` may remain unstaged and must not be reverted.

- [ ] **Step 5: Final commit if verification required fixes**

If Step 1-3 required any fixes after Task 4, commit them:

```bash
git add <fixed-files>
git commit -m "fix: stabilize skills auto restart setting"
```

---

## Self-Review

Spec coverage:

- Global setting, default false: Task 1 and Task 2.
- Toggle in settings: Task 4.
- Manual behavior preserved when disabled: Task 4 tests and implementation.
- Auto restart when enabled: Task 3 and Task 4.
- Failure fallback: Task 4.
- Backend-readable path for remote server follow-up: Task 1.
- Duplicate restart prevention: Task 3.

Placeholder scan:

- No TBD, TODO, or unspecified "add tests" steps remain.
- Each code-changing step includes exact code or a concrete target snippet.

Type consistency:

- Backend key is `autoRestartOpencodeOnSkillsChange`.
- Frontend helper names are `getAutoRestartOpencodeOnSkillsChange` and `setAutoRestartOpencodeOnSkillsChange`.
- Runtime reload function is `requestOpenCodeRuntimeReload`.
- Reload reason for Skills file changes is `skills-file-change`.

