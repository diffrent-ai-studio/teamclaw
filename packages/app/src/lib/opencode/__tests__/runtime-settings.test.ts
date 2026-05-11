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
