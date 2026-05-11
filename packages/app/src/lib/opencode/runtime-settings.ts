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
