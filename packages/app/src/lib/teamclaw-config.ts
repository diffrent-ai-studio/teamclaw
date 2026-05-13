/**
 * Reader/writer for teamclaw.json — workspace-level config for custom LLM
 * providers and skill permissions.
 */

export interface CustomModelConfig {
  modelId: string
  modelName?: string
  limit?: {
    context?: number
    output?: number
  }
  modalities?: {
    input: string[]
    output: string[]
  }
}

export interface CustomProviderConfig {
  name: string
  baseURL: string
  apiKey?: string
  models: CustomModelConfig[]
}

interface ProviderEntry {
  npm: string
  name?: string
  options?: { baseURL?: string; [key: string]: unknown }
  models?: Record<string, {
    name: string
    limit?: { context?: number; output?: number }
    modalities?: { input: string[]; output: string[] }
  }>
}

export type SkillPermission = 'allow' | 'deny' | 'ask'

export type SkillPermissionMap = Record<string, SkillPermission>

export interface ResolvedPermission {
  permission: SkillPermission
  matchedPattern: string
  isExact: boolean
}

interface TeamclawConfig {
  [key: string]: unknown
  provider?: Record<string, ProviderEntry>
  permission?: {
    skill?: SkillPermissionMap
    [key: string]: unknown
  }
}

export function slugifyProviderId(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

async function readTeamclawConfig(workspacePath: string): Promise<TeamclawConfig> {
  const { readTextFile, exists } = await import('@tauri-apps/plugin-fs')
  const configPath = `${workspacePath}/teamclaw.json`

  if (!(await exists(configPath))) {
    return {}
  }

  const content = await readTextFile(configPath)
  return JSON.parse(content) as TeamclawConfig
}

async function writeTeamclawConfig(workspacePath: string, config: TeamclawConfig): Promise<void> {
  const { writeTextFile } = await import('@tauri-apps/plugin-fs')
  const configPath = `${workspacePath}/teamclaw.json`
  await writeTextFile(configPath, JSON.stringify(config, null, 2))
}

export function providerApiKeyName(providerId: string): string {
  return `${providerId}_api_key`
}

/**
 * Add a custom OpenAI-compatible provider. Returns the generated provider ID.
 *
 * NOTE: The actual API key value is NOT written here — only a `${ref}`
 * placeholder. The caller must store the real value in the keychain
 * via `env_var_set` using the key name from `providerApiKeyName()`.
 */
export async function addCustomProviderToConfig(
  workspacePath: string,
  config: CustomProviderConfig
): Promise<string> {
  const providerId = slugifyProviderId(config.name)
  const teamclawConfig = await readTeamclawConfig(workspacePath)

  if (!teamclawConfig.provider) {
    teamclawConfig.provider = {}
  }

  const modelsObj: Record<string, {
    name: string
    limit?: { context?: number; output?: number }
    modalities?: { input: string[]; output: string[] }
  }> = {}
  for (const model of config.models) {
    const modelEntry: {
      name: string
      limit?: { context?: number; output?: number }
      modalities?: { input: string[]; output: string[] }
    } = {
      name: model.modelName || model.modelId,
    }

    if (model.limit && (model.limit.context !== undefined || model.limit.output !== undefined)) {
      modelEntry.limit = {}
      if (model.limit.context !== undefined) {
        modelEntry.limit.context = model.limit.context
      }
      if (model.limit.output !== undefined) {
        modelEntry.limit.output = model.limit.output
      }
    }

    if (model.modalities) {
      modelEntry.modalities = model.modalities
    }

    modelsObj[model.modelId] = modelEntry
  }

  const providerOptions: { baseURL: string; apiKey?: string } = {
    baseURL: config.baseURL,
  }
  if (config.apiKey) {
    if (/^\$\{.+\}$/.test(config.apiKey) || /^\$.+/.test(config.apiKey)) {
      providerOptions.apiKey = config.apiKey
    } else {
      const keyName = providerApiKeyName(providerId)
      providerOptions.apiKey = `\${${keyName}}`
    }
  }

  teamclawConfig.provider[providerId] = {
    npm: '@ai-sdk/openai-compatible',
    name: config.name,
    options: providerOptions,
    models: modelsObj,
  }

  await writeTeamclawConfig(workspacePath, teamclawConfig)
  return providerId
}

export async function getCustomProviderConfig(
  workspacePath: string,
  providerId: string
): Promise<CustomProviderConfig | null> {
  const teamclawConfig = await readTeamclawConfig(workspacePath)

  const providerEntry = teamclawConfig.provider?.[providerId]
  if (!providerEntry) return null

  const models: CustomModelConfig[] = []
  if (providerEntry.models) {
    for (const [modelId, modelData] of Object.entries(providerEntry.models)) {
      models.push({
        modelId,
        modelName: modelData.name,
        limit: modelData.limit,
        modalities: modelData.modalities,
      })
    }
  }

  return {
    name: providerEntry.name || providerId,
    baseURL: providerEntry.options?.baseURL || '',
    models,
  }
}

export async function updateCustomProviderConfig(
  workspacePath: string,
  providerId: string,
  config: CustomProviderConfig
): Promise<boolean> {
  const teamclawConfig = await readTeamclawConfig(workspacePath)

  if (!teamclawConfig.provider?.[providerId]) {
    return false
  }

  const modelsObj: Record<string, {
    name: string
    limit?: { context?: number; output?: number }
    modalities?: { input: string[]; output: string[] }
  }> = {}
  for (const model of config.models) {
    const modelEntry: {
      name: string
      limit?: { context?: number; output?: number }
      modalities?: { input: string[]; output: string[] }
    } = {
      name: model.modelName || model.modelId,
    }

    if (model.limit && (model.limit.context !== undefined || model.limit.output !== undefined)) {
      modelEntry.limit = {}
      if (model.limit.context !== undefined) {
        modelEntry.limit.context = model.limit.context
      }
      if (model.limit.output !== undefined) {
        modelEntry.limit.output = model.limit.output
      }
    }

    if (model.modalities) {
      modelEntry.modalities = model.modalities
    }

    modelsObj[model.modelId] = modelEntry
  }

  const providerOptions: { baseURL: string; apiKey?: string } = {
    baseURL: config.baseURL,
  }
  if (config.apiKey) {
    if (/^\$\{.+\}$/.test(config.apiKey) || /^\$.+/.test(config.apiKey)) {
      providerOptions.apiKey = config.apiKey
    } else {
      const keyName = providerApiKeyName(providerId)
      providerOptions.apiKey = `\${${keyName}}`
    }
  }

  teamclawConfig.provider[providerId] = {
    npm: '@ai-sdk/openai-compatible',
    name: config.name,
    options: providerOptions,
    models: modelsObj,
  }

  await writeTeamclawConfig(workspacePath, teamclawConfig)
  return true
}

export async function removeCustomProviderFromConfig(
  workspacePath: string,
  providerId: string
): Promise<void> {
  const teamclawConfig = await readTeamclawConfig(workspacePath)

  if (teamclawConfig.provider && teamclawConfig.provider[providerId]) {
    delete teamclawConfig.provider[providerId]

    if (Object.keys(teamclawConfig.provider).length === 0) {
      delete teamclawConfig.provider
    }

    await writeTeamclawConfig(workspacePath, teamclawConfig)
  }
}

export async function getCustomProviderIds(workspacePath: string): Promise<string[]> {
  try {
    const teamclawConfig = await readTeamclawConfig(workspacePath)
    if (!teamclawConfig.provider) return []
    return Object.keys(teamclawConfig.provider)
  } catch {
    return []
  }
}

// ─── Skill Permission Helpers ───────────────────────────────────────────────

function matchesPattern(skillName: string, pattern: string): boolean {
  if (pattern === '*') return true
  if (!pattern.includes('*')) return pattern === skillName
  const prefix = pattern.slice(0, -1)
  return skillName.startsWith(prefix)
}

/**
 * Resolve the effective permission for a skill name against a permission map.
 * Priority: exact match > prefix wildcard (longer prefix wins) > global "*"
 */
export function resolveSkillPermission(
  skillName: string,
  permissions: SkillPermissionMap
): ResolvedPermission {
  if (permissions[skillName]) {
    return { permission: permissions[skillName], matchedPattern: skillName, isExact: true }
  }

  let bestMatch: { pattern: string; prefixLen: number } | null = null
  for (const pattern of Object.keys(permissions)) {
    if (pattern === '*' || pattern === skillName) continue
    if (matchesPattern(skillName, pattern)) {
      const prefixLen = pattern.length
      if (!bestMatch || prefixLen > bestMatch.prefixLen) {
        bestMatch = { pattern, prefixLen }
      }
    }
  }

  if (bestMatch) {
    return { permission: permissions[bestMatch.pattern], matchedPattern: bestMatch.pattern, isExact: false }
  }

  if (permissions['*']) {
    return { permission: permissions['*'], matchedPattern: '*', isExact: false }
  }

  return { permission: 'allow', matchedPattern: '*', isExact: false }
}

export async function readSkillPermissions(workspacePath: string): Promise<SkillPermissionMap> {
  try {
    const config = await readTeamclawConfig(workspacePath)
    return config.permission?.skill ?? {}
  } catch {
    return {}
  }
}

export async function writeSkillPermission(
  workspacePath: string,
  pattern: string,
  permission: SkillPermission
): Promise<void> {
  const config = await readTeamclawConfig(workspacePath)
  if (!config.permission) config.permission = {}
  if (!config.permission.skill) config.permission.skill = {}
  config.permission.skill[pattern] = permission
  await writeTeamclawConfig(workspacePath, config)
}

export async function removeSkillPermission(
  workspacePath: string,
  pattern: string
): Promise<void> {
  const config = await readTeamclawConfig(workspacePath)
  if (!config.permission?.skill) return
  delete config.permission.skill[pattern]
  if (Object.keys(config.permission.skill).length === 0) {
    delete config.permission.skill
  }
  if (Object.keys(config.permission).length === 0) {
    delete config.permission
  }
  await writeTeamclawConfig(workspacePath, config)
}
