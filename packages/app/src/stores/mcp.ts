import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import type { MCPRuntimeStatus } from '@/lib/opencode/sdk-types'
import { withAsync } from '@/lib/store-utils'
import { useWorkspaceStore } from './workspace'

function getWorkspaceArgs() {
  const workspacePath = useWorkspaceStore.getState().workspacePath
  return workspacePath ? { workspacePath } : {}
}

// MCP Server configuration types
export interface MCPServerConfig {
  type: 'local' | 'remote'
  enabled?: boolean
  command?: string[]  // for local
  environment?: Record<string, string>
  url?: string  // for remote
  headers?: Record<string, string>
  timeout?: number
}

// MCP Test result types
export interface MCPTestResult {
  success: boolean
  message: string
  details?: string
}

export interface MCPServer {
  name: string
  config: MCPServerConfig
}

interface MCPState {
  servers: Record<string, MCPServerConfig>
  runtimeStatus: Record<string, MCPRuntimeStatus>
  serverTools: Record<string, string[]>  // serverName -> tool names
  isLoading: boolean
  error: string | null
  testingServers: Record<string, boolean>  // Track which servers are being tested
  testResults: Record<string, MCPTestResult>  // Store test results

  // Actions
  loadConfig: () => Promise<void>
  loadRuntimeStatus: () => Promise<void>
  loadTools: () => Promise<void>
  addServer: (name: string, config: MCPServerConfig) => Promise<void>
  updateServer: (name: string, config: MCPServerConfig) => Promise<void>
  removeServer: (name: string) => Promise<void>
  toggleServer: (name: string, enabled: boolean) => Promise<void>
  testServer: (name: string) => Promise<void>
  clearError: () => void
  clearTestResult: (name: string) => void
  syncFromFile: () => Promise<void>
}

export const useMCPStore = create<MCPState>((set) => ({
  servers: {},
  runtimeStatus: {},
  serverTools: {},
  isLoading: false,
  error: null,
  testingServers: {},
  testResults: {},

  loadConfig: async () => {
    await withAsync(set, async () => {
      const config = await invoke<Record<string, MCPServerConfig>>('get_mcp_config', getWorkspaceArgs())
      set({ servers: config })
    })
  },

  loadRuntimeStatus: async () => {
    // OpenCode sidecar removed — runtime status is no longer available via API
    // Status is managed via Tauri commands (list_mcp_tools, test_mcp_server, etc.)
  },

  loadTools: async () => {
    try {
      // Query each MCP server directly for its tools (via Tauri command)
      const toolMap = await invoke<Record<string, string[]>>('list_mcp_tools')
      set({ serverTools: toolMap })
    } catch (error) {
      console.error('Failed to load MCP tools:', error)
    }
  },

  addServer: async (name: string, config: MCPServerConfig) => {
    await withAsync(set, async () => {
      await invoke('add_mcp_server', { name, serverConfig: config, ...getWorkspaceArgs() })
      const updatedConfig = await invoke<Record<string, MCPServerConfig>>('get_mcp_config', getWorkspaceArgs())
      set({ servers: updatedConfig })
    }, { rethrow: true })
  },

  updateServer: async (name: string, config: MCPServerConfig) => {
    await withAsync(set, async () => {
      await invoke('update_mcp_server', { name, serverConfig: config, ...getWorkspaceArgs() })
      const updatedConfig = await invoke<Record<string, MCPServerConfig>>('get_mcp_config', getWorkspaceArgs())
      set({ servers: updatedConfig })
    }, { rethrow: true })
  },

  removeServer: async (name: string) => {
    await withAsync(set, async () => {
      await invoke('remove_mcp_server', { name, ...getWorkspaceArgs() })
      const updatedConfig = await invoke<Record<string, MCPServerConfig>>('get_mcp_config', getWorkspaceArgs())
      set({ servers: updatedConfig })
    }, { rethrow: true })
  },

  toggleServer: async (name: string, enabled: boolean) => {
    await withAsync(set, async () => {
      await invoke('toggle_mcp_server', { name, enabled, ...getWorkspaceArgs() })
      const updatedConfig = await invoke<Record<string, MCPServerConfig>>('get_mcp_config', getWorkspaceArgs())
      set({ servers: updatedConfig })
    }, { rethrow: true })
  },

  testServer: async (name: string) => {
    set((state) => ({
      testingServers: { ...state.testingServers, [name]: true },
    }))
    try {
      const result = await invoke<MCPTestResult>('test_mcp_server', { name, ...getWorkspaceArgs() })
      set((state) => ({
        testingServers: { ...state.testingServers, [name]: false },
        testResults: { ...state.testResults, [name]: result },
      }))
    } catch (error) {
      set((state) => ({
        testingServers: { ...state.testingServers, [name]: false },
        testResults: {
          ...state.testResults,
          [name]: {
            success: false,
            message: error instanceof Error ? error.message : String(error),
            details: undefined,
          },
        },
      }))
    }
  },

  clearError: () => set({ error: null }),
  
  clearTestResult: (name: string) => {
    set((state) => {
      const newResults = { ...state.testResults }
      delete newResults[name]
      return { testResults: newResults }
    })
  },

  syncFromFile: async () => {
    try {
      const newConfig = await invoke<Record<string, MCPServerConfig>>('get_mcp_config')
      // OpenCode sidecar removed — just update local state from file
      set({ servers: newConfig })
    } catch (error) {
      console.error('[MCP] syncFromFile failed:', error)
    }
  },
}))
