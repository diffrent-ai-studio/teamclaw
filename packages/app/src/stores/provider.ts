import { create } from 'zustand'
import { toast } from 'sonner'
import { appShortName } from '@/lib/build-config'
import { invoke } from '@tauri-apps/api/core'
import { workspaceScopedKey } from '@/lib/storage'
import { useWorkspaceStore } from '@/stores/workspace'
import { allAmuxdModels, AMUXD_AGENT_TYPES, availableModelsFor } from '@/lib/amuxd-models'
import {
  type CustomProviderConfig,
  addCustomProviderToConfig,
  updateCustomProviderConfig,
  getCustomProviderConfig,
  removeCustomProviderFromConfig,
  getCustomProviderIds,
  providerApiKeyName,
} from '@/lib/teamclaw-config'

const SELECTED_MODEL_BASE = `${appShortName}-selected-model`

function selectedModelStorageKey(): string {
  return workspaceScopedKey(SELECTED_MODEL_BASE, useWorkspaceStore.getState().workspacePath)
}

// Read the saved model, preferring the workspace-scoped key but falling back
// to the legacy unscoped key for users upgrading from before workspace scoping.
function readSavedSelectedModel(): string | null {
  const scoped = localStorage.getItem(selectedModelStorageKey())
  if (scoped !== null) return scoped
  return localStorage.getItem(SELECTED_MODEL_BASE)
}

// Safe helper: agent client is not wired to the amuxd daemon yet; all
// callers gracefully no-op when this returns null. Type is `any` so the
// `if (!client) return` early-exits typecheck without narrowing the body.
// TODO(amuxd): wire to daemon
function tryGetClient(): any {
  return null
}

export interface ProviderAuthMethod {
  type: 'oauth' | 'api'
  label: string
  prompts?: unknown[]
}

// A model option available for selection in the ChatPanel
export interface ModelOption {
  id: string
  name: string
  provider: string
}

// Provider entry for the Settings provider list
export interface ProviderEntry {
  id: string
  name: string
  configured: boolean // true if in the `connected` list
}

// Configured provider with full model info (from GET /config/providers)
export interface ConfiguredProvider {
  id: string
  name: string
  models: Array<{ id: string; name: string }>
}

export interface ProviderState {
  // All available providers (from GET /provider), with configured status
  providers: ProviderEntry[]
  providersLoading: boolean

  // Configured providers with model details (from GET /config/providers)
  configuredProviders: ConfiguredProvider[]
  configuredProvidersLoading: boolean

  // Flattened model list built from configuredProviders
  models: ModelOption[]

  // Currently selected model (from GET /config)
  currentModelKey: string | null // format: "providerId/modelId"

  // Auth methods per provider (from GET /provider/auth)
  authMethods: Record<string, ProviderAuthMethod[]>

  // Custom provider IDs (defined in the legacy workspace config)
  customProviderIds: string[]

  // Provider IDs disconnected in the current session. The agent runtime reports
  // custom providers (defined in the legacy workspace config) as "connected"
  // even after auth is removed, so we track them here and filter during refreshes.
  _disconnectedIds: Set<string>

  // Actions
  refreshAuthMethods: () => Promise<void>
  connectProviderOAuth: (providerId: string, methodIndex: number) => Promise<
    { status: 'pending'; url: string; instructions: string; methodType: 'auto' | 'code' } |
    { status: 'success' } |
    { status: 'error'; message: string }
  >
  completeOAuthCallback: (providerId: string, methodIndex: number, code?: string) => Promise<boolean>
  refreshProviders: () => Promise<void>
  refreshConfiguredProviders: () => Promise<void>
  refreshCurrentModel: () => Promise<void>
  refreshCustomProviderIds: (workspacePath: string) => Promise<void>
  connectProvider: (providerId: string, apiKey: string) => Promise<boolean>
  disconnectProvider: (providerId: string) => Promise<boolean>
  addCustomProvider: (workspacePath: string, config: CustomProviderConfig, apiKey: string) => Promise<string | null>
  updateCustomProvider: (workspacePath: string, providerId: string, config: CustomProviderConfig) => Promise<boolean>
  getCustomProvider: (workspacePath: string, providerId: string) => Promise<CustomProviderConfig | null>
  removeCustomProvider: (workspacePath: string, providerId: string) => Promise<boolean>
  selectModel: (providerId: string, modelId: string, modelName: string) => Promise<void>
  initAll: () => Promise<void>
}

export const useProviderStore = create<ProviderState>((set, get) => ({
  // Initial state
  authMethods: {},
  providers: [],
  providersLoading: false,
  configuredProviders: [],
  configuredProvidersLoading: false,
  models: [],
  currentModelKey: null,
  customProviderIds: [],
  _disconnectedIds: new Set<string>(),

  refreshAuthMethods: async () => {
    const client = tryGetClient()
    if (!client) return
    try {
      const methods = await client.getAuthMethods()
      set({ authMethods: methods as Record<string, ProviderAuthMethod[]> })
    } catch (err) {
      console.error('Failed to load auth methods:', err)
    }
  },

  // Initiate OAuth for a provider. Returns pending state with url+instructions for the UI to show.
  connectProviderOAuth: async (providerId, methodIndex) => {
    const client = tryGetClient()
    if (!client) return { status: 'error' as const, message: 'Agent runtime not connected' }
    try {
      const result = await client.oauthAuthorize(providerId, methodIndex)
      if (!result) return { status: 'error' as const, message: 'Provider does not support OAuth' }
      return {
        status: 'pending' as const,
        url: result.url,
        instructions: result.instructions ?? '',
        methodType: (result.method ?? 'code') as 'auto' | 'code',
      }
    } catch (err) {
      return { status: 'error' as const, message: err instanceof Error ? err.message : 'Unknown error' }
    }
  },

  // Poll/wait for OAuth callback to complete (call after opening browser).
  // For Device Flow (methodType:"auto") the sidecar polls GitHub internally; this call blocks until done.
  completeOAuthCallback: async (providerId, methodIndex, code) => {
    const client = tryGetClient()
    if (!client) return false
    try {
      await client.oauthCallback(providerId, methodIndex, code)
      set((state) => {
        const newDisconnected = new Set(state._disconnectedIds)
        newDisconnected.delete(providerId)
        return { _disconnectedIds: newDisconnected }
      })
      toast.success('Provider connected', { description: `Successfully connected ${providerId}` })
      await Promise.all([get().refreshProviders(), get().refreshConfiguredProviders()])
      return true
    } catch (err) {
      toast.error('OAuth login failed', { description: err instanceof Error ? err.message : 'Unknown error' })
      return false
    }
  },

  // Refresh all available providers (GET /provider)
  // Response: { all: ProviderObj[], connected: string[], default: Record<string,string> }
  refreshProviders: async () => {
    const client = tryGetClient()
    if (!client) return // Client not ready yet, skip silently
    set({ providersLoading: true })
    try {
      const data = await client.getProviders()
      const connectedSet = new Set(data.connected || [])
      const { _disconnectedIds } = get()
      _disconnectedIds.forEach((id) => connectedSet.delete(id))
      const providers: ProviderEntry[] = (data.all || []).map((p: any) => ({
        id: p.id,
        name: p.name || p.id,
        configured: connectedSet.has(p.id),
      }))
      // Sort: connected first, then alphabetical
      providers.sort((a, b) => {
        if (a.configured !== b.configured) return a.configured ? -1 : 1
        return a.name.localeCompare(b.name)
      })
      set({ providers, providersLoading: false })
    } catch (err) {
      console.error('Failed to load providers:', err)
      // Only show toast if it's not a connection error (agent runtime not ready)
      const isConnectionError = err instanceof Error && (err.message.includes('Cannot connect to agent runtime') || err.message.includes('Load failed'))
      if (!isConnectionError) {
        toast.error('Failed to load providers', {
          id: 'provider-list-error',
          description: err instanceof Error ? err.message : 'Unknown error',
        })
      }
      set({ providersLoading: false })
    }
  },

  // Refresh configured providers with model details (GET /config/providers)
  refreshConfiguredProviders: async () => {
    const client = tryGetClient()
    if (!client) return // Client not ready yet, skip silently
    set({ configuredProvidersLoading: true })
    try {
      const data = await client.getConfigProviders()
      const { _disconnectedIds } = get()

      // Transform providers into our format, excluding disconnected ones
      const configuredProviders: ConfiguredProvider[] = (data.providers || [])
        .filter((p: any) => !_disconnectedIds.has(p.id || p.name))
        .map((p: any) => ({
          id: p.id || p.name,
          name: p.name,
          models: Object.entries(p.models || {}).map(([key, model]: [string, any]) => ({
            id: model.id || key,
            name: model.name || key,
          })),
        }))

      // Build flattened models list
      const models: ModelOption[] = []
      configuredProviders.forEach((p) => {
        p.models.forEach((m) => {
          models.push({
            id: m.id,
            name: m.name,
            provider: p.id,
          })
        })
      })

      set({
        configuredProviders,
        models,
        configuredProvidersLoading: false,
      })
    } catch (err) {
      console.error('Failed to load configured providers:', err)
      // Only show toast if it's not a connection error (agent runtime not ready)
      const isConnectionError = err instanceof Error && (err.message.includes('Cannot connect to agent runtime') || err.message.includes('Load failed'))
      if (!isConnectionError) {
        toast.error('Failed to load model list', {
          id: 'model-list-error',
          description: err instanceof Error ? err.message : 'Unknown error',
        })
      }
      set({ configuredProvidersLoading: false })
    }
  },

  // Refresh current model from agent runtime config (GET /config)
  refreshCurrentModel: async () => {
    const client = tryGetClient()
    if (!client) return // Client not ready yet, skip silently
    try {
      const config = await client.getConfig() as Record<string, unknown>
      if (config.model) {
        set({ currentModelKey: config.model as string })
      }
    } catch (err) {
      console.error('Failed to load current model config:', err)
      // Non-critical, don't toast
    }
  },

  // Connect a provider by setting its API key and validate by fetching provider models.
  // Some providers (e.g. Alibaba Coding) may return models slowly or in a different shape;
  // we retry once and allow "provider found but 0 models" as success with a note.
  connectProvider: async (providerId: string, apiKey: string) => {
    const client = tryGetClient()
    if (!client) {
      toast.error('Agent runtime not connected')
      return false
    }
    try {
      await client.setAuth(providerId, { type: 'api', key: apiKey })
      const delay = (ms: number) => new Promise((r) => setTimeout(r, ms))
      await delay(600)
      let data: { providers?: Array<{ id?: string; name?: string; models?: unknown }> } = {}
      for (let attempt = 0; attempt < 2; attempt++) {
        data = await client.getConfigProviders()
        const providers = data.providers || []
        const provider = providers.find(
          (p: { id?: string; name?: string }) =>
            (p.id && p.id === providerId) ||
            (p.name && p.name === providerId) ||
            (p.id && p.id.toLowerCase() === providerId.toLowerCase()) ||
            (p.name && p.name.toLowerCase() === providerId.toLowerCase())
        )
        if (provider) {
          const models = provider.models
          const modelCount =
            Array.isArray(models) ? models.length : typeof models === 'object' && models ? Object.keys(models).length : 0
          if (import.meta.env.DEV) {
            console.log('[LLM connect] providerId=', providerId, 'found=', true, 'modelCount=', modelCount)
          }
          // Skip toast for team provider — sidebar icon already indicates connection
          if (providerId !== 'team') {
            if (modelCount > 0) {
              toast.success('Provider connected', {
                description: `Successfully connected ${providerId}`,
              })
            } else {
              toast.success('Provider connected', {
                description: 'If no models appear below, the provider may list them later or use a custom model ID.',
              })
            }
          }
          set((state) => {
            const newDisconnected = new Set(state._disconnectedIds)
            newDisconnected.delete(providerId)
            return { _disconnectedIds: newDisconnected }
          })
          await Promise.all([
            get().refreshProviders(),
            get().refreshConfiguredProviders(),
          ])
          return true
        }
        if (attempt === 0) {
          await delay(800)
        }
      }
      const providers = data.providers || []
      console.warn('[LLM connect] Provider not in config list after setAuth (may be valid for some providers).', { providerId, providerIds: providers.map((p: { id?: string; name?: string }) => p.id || p.name) })
      if (providerId !== 'team') {
        toast.success('Provider connected', {
          description: "If no models appear, select the model in chat or check the provider's custom model ID.",
        })
      }
      set((state) => {
        const newDisconnected = new Set(state._disconnectedIds)
        newDisconnected.delete(providerId)
        return { _disconnectedIds: newDisconnected }
      })
      await Promise.all([
        get().refreshProviders(),
        get().refreshConfiguredProviders(),
      ])
      return true
    } catch (err) {
      console.error('[LLM connect] Failed to connect provider:', err)
      toast.error('Failed to connect provider', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
      return false
    }
  },

  // Disconnect a provider by removing its authentication
  disconnectProvider: async (providerId: string) => {
    const client = tryGetClient()
    if (!client) {
      toast.error('Agent runtime not connected')
      return false
    }
    try {
      await client.deleteAuth(providerId)
      toast.success('Provider disconnected', {
        description: `Successfully disconnected ${providerId}`,
      })
      // Track as disconnected so subsequent refreshes from the server
      // don't re-add it as "connected" (the agent runtime reports custom providers
      // as connected even after auth removal).
      set((state) => {
        const newDisconnected = new Set(state._disconnectedIds)
        newDisconnected.add(providerId)
        const updatedProviders = state.providers
          .map((p) => (p.id === providerId ? { ...p, configured: false } : p))
          .sort((a, b) => {
            if (a.configured !== b.configured) return a.configured ? -1 : 1
            return a.name.localeCompare(b.name)
          })
        return {
          _disconnectedIds: newDisconnected,
          providers: updatedProviders,
          configuredProviders: state.configuredProviders.filter((p) => p.id !== providerId),
          models: state.models.filter((m) => m.provider !== providerId),
        }
      })
      return true
    } catch (err) {
      console.error('Failed to disconnect provider:', err)
      toast.error('Failed to disconnect provider', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
      return false
    }
  },

  // Refresh custom provider IDs from the legacy workspace config
  refreshCustomProviderIds: async (workspacePath: string) => {
    try {
      const ids = await getCustomProviderIds(workspacePath)
      set({ customProviderIds: ids })
    } catch (err) {
      console.error('Failed to load custom provider IDs:', err)
    }
  },

  // Add a custom OpenAI-compatible provider
  addCustomProvider: async (workspacePath: string, config: CustomProviderConfig, apiKey: string) => {
    try {
      const providerId = await addCustomProviderToConfig(workspacePath, config)
      // Store raw API key in keychain so ${ref} gets resolved at startup.
      // Skip if the value is already a ${ref} (user referencing an existing secret).
      const isRef = /^\$\{?.+\}?$/.test(apiKey)
      if (apiKey && !isRef) {
        const keyName = providerApiKeyName(providerId)
        await invoke('env_var_set', { key: keyName, value: apiKey, description: `API key for provider ${config.name}` })
      }
      toast.success('Custom provider added', {
        description: `${config.name} has been added. Restarting agent...`,
      })
      return providerId
    } catch (err) {
      console.error('Failed to add custom provider:', err)
      toast.error('Failed to add custom provider', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
      return null
    }
  },

  // Update an existing custom provider
  updateCustomProvider: async (workspacePath: string, providerId: string, config: CustomProviderConfig) => {
    try {
      const success = await updateCustomProviderConfig(workspacePath, providerId, config)
      if (success) {
        // Update API key in keychain if provided (skip ${ref} values)
        if (config.apiKey && !/^\$\{?.+\}?$/.test(config.apiKey)) {
          const keyName = providerApiKeyName(providerId)
          await invoke('env_var_set', { key: keyName, value: config.apiKey, description: `API key for provider ${config.name}` })
        }
        toast.success('Custom provider updated', {
          description: `${config.name} has been updated. Restarting agent...`,
        })
      }
      return success
    } catch (err) {
      console.error('Failed to update custom provider:', err)
      toast.error('Failed to update custom provider', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
      return false
    }
  },

  // Get a custom provider configuration
  getCustomProvider: async (workspacePath: string, providerId: string) => {
    try {
      return await getCustomProviderConfig(workspacePath, providerId)
    } catch (err) {
      console.error('Failed to get custom provider:', err)
      return null
    }
  },

  // Remove a custom provider from the legacy workspace config
  removeCustomProvider: async (workspacePath: string, providerId: string) => {
    try {
      await removeCustomProviderFromConfig(workspacePath, providerId)
      toast.success('Custom provider removed', {
        description: `Provider has been removed. Restarting agent...`,
      })
      return true
    } catch (err) {
      console.error('Failed to remove custom provider:', err)
      toast.error('Failed to remove custom provider', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
      return false
    }
  },

  // Select a model and sync to the agent runtime backend
  selectModel: async (providerId: string, modelId: string, _modelName: string) => {
    const modelKey = `${providerId}/${modelId}`
    set({ currentModelKey: modelKey })

    // Cache in workspace-scoped localStorage as fallback
    localStorage.setItem(selectedModelStorageKey(), modelKey)

    const client = tryGetClient()
    if (!client) return
    try {
      await client.updateConfig({ model: modelKey })
    } catch (err) {
      console.error('Failed to update model config:', err)
      toast.error('Failed to update model', {
        description: err instanceof Error ? err.message : 'Unknown error',
      })
    }
  },

  // Initialize all data at once
  initAll: async () => {
    // v2 Phase 1: providers/models come from amuxd's static available_models
    // list (ported from amux/daemon/src/runtime/models.rs). Phase 2's daemon
    // installer will replace this with live RuntimeInfo per running runtime.
    // We bypass refreshProviders/refreshConfiguredProviders (those still hit
    // legacy SDK stubs) and seed state directly.
    const flat = allAmuxdModels()
    const providers: ProviderEntry[] = AMUXD_AGENT_TYPES.map((id) => ({
      id,
      name: id,
      configured: availableModelsFor(id).length > 0,
    }))
    const configuredProviders: ConfiguredProvider[] = AMUXD_AGENT_TYPES
      .map((id) => ({
        id,
        name: id,
        models: availableModelsFor(id).map((m) => ({ id: m.id, name: m.displayName })),
      }))
      .filter((p) => p.models.length > 0)
    const models: ModelOption[] = flat.map((m) => ({
      id: m.id,
      name: m.displayName,
      provider: m.provider,
    }))
    set({
      providers,
      configuredProviders,
      models,
      providersLoading: false,
      configuredProvidersLoading: false,
    })

    // After loading, resolve selected model:
    // Priority: localStorage > first available model
    const { currentModelKey } = get()
    const availableModels = get().models

    let resolvedKey = currentModelKey

    if (!resolvedKey || !availableModels.find((m) => `${m.provider}/${m.id}` === resolvedKey)) {
      // Try localStorage fallback (workspace-scoped, with legacy fallback)
      const saved = readSavedSelectedModel()
      if (saved && availableModels.find((m) => `${m.provider}/${m.id}` === saved)) {
        resolvedKey = saved
      } else if (availableModels.length > 0) {
        // Last resort: first available model
        resolvedKey = `${availableModels[0].provider}/${availableModels[0].id}`
      }
    }

    if (resolvedKey) {
      set({ currentModelKey: resolvedKey })
      // Sync workspace-scoped localStorage to be consistent
      localStorage.setItem(selectedModelStorageKey(), resolvedKey)
    }
  },
}))

// Helper: split "providerId/modelId" safely – modelId itself may contain '/'
function splitModelKey(key: string): [string, string] | null {
  const idx = key.indexOf('/')
  if (idx === -1) return null
  return [key.substring(0, idx), key.substring(idx + 1)]
}

// Helper: get the currently selected ModelOption from the store
export function getSelectedModelOption(state: ProviderState): ModelOption | null {
  if (!state.currentModelKey) return null
  const parts = splitModelKey(state.currentModelKey)
  if (!parts) return null
  const [providerId, modelId] = parts
  return state.models.find((m) => m.provider === providerId && m.id === modelId) || null
}
