import { describe, it, expect, vi } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'

const mocks = vi.hoisted(() => {
  const providerState = {
    providers: [] as Array<{ id: string; name: string; configured: boolean }>,
    providersLoading: false,
    configuredProviders: [] as Array<{ id: string; name: string; models: Array<{ id: string; name: string }> }>,
    customProviderIds: [] as string[],
    authMethods: {} as Record<string, Array<{ type: 'oauth' | 'api'; label: string }>>,
    refreshAuthMethods: vi.fn(),
    refreshProviders: vi.fn(),
    refreshConfiguredProviders: vi.fn(),
    refreshCustomProviderIds: vi.fn(),
    connectProvider: vi.fn(),
    connectProviderOAuth: vi.fn(),
    completeOAuthCallback: vi.fn(),
    addCustomProvider: vi.fn(),
    updateCustomProvider: vi.fn(),
    getCustomProvider: vi.fn(),
    removeCustomProvider: vi.fn(),
    disconnectProvider: vi.fn(),
    initAll: vi.fn(),
  }
  const workspaceState = { workspacePath: '/test', openCodeReady: true, setOpenCodeBootstrapped: vi.fn() }
  return {
    providerState,
    workspaceState,
    shellOpen: vi.fn(),
    restartOpencode: vi.fn(),
  }
})

vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (k: string, d?: string | { defaultValue?: string }) =>
      typeof d === 'string' ? d : d?.defaultValue ?? k,
    i18n: { language: 'en', changeLanguage: vi.fn() },
  }),
}))
vi.mock('@/stores/provider', () => ({
  useProviderStore: vi.fn((sel: (s: any) => any) => {
    return sel(mocks.providerState)
  }),
}))
vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: vi.fn((sel: (s: any) => any) => {
    return sel(mocks.workspaceState)
  }),
}))
vi.mock('@/stores/team-mode', () => ({
  useTeamModeStore: vi.fn((sel: (s: any) => any) => {
    const state = { teamMode: false, teamModelConfig: null, devUnlocked: false, teamModelOptions: [], switchTeamModel: vi.fn() }
    return sel(state)
  }),
}))
vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn() }))
vi.mock('@tauri-apps/plugin-shell', () => ({ open: mocks.shellOpen }))
vi.mock('@/lib/opencode/sdk-client', () => ({ initOpenCodeClient: vi.fn() }))
vi.mock('@/lib/opencode/restart', () => ({ restartOpencode: mocks.restartOpencode }))
vi.mock('@/lib/utils', () => ({ cn: (...a: string[]) => a.join(' ') }))
vi.mock('../shared', () => ({
  SettingCard: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  SectionHeader: ({ title }: { title: string }) => <h2>{title}</h2>,
}))

import { LLMSection } from '../LLMSection'

describe('LLMSection', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mocks.providerState.providers = []
    mocks.providerState.providersLoading = false
    mocks.providerState.configuredProviders = []
    mocks.providerState.customProviderIds = []
    mocks.providerState.authMethods = {}
    mocks.workspaceState.workspacePath = '/test'
    mocks.workspaceState.openCodeReady = true
  })

  it('renders the LLM Model title', () => {
    render(<LLMSection />)
    expect(screen.getByText('LLM Model')).toBeTruthy()
  })

  it('shows no providers message when empty', () => {
    render(<LLMSection />)
    expect(screen.getByText('No providers available')).toBeTruthy()
  })

  it('waits for an authorization code before completing code-based OAuth providers', async () => {
    mocks.providerState.providers = [{ id: 'openai', name: 'OpenAI', configured: false }]
    mocks.providerState.authMethods = {
      openai: [{ type: 'oauth', label: 'Browser login' }],
    }
    mocks.providerState.connectProviderOAuth.mockResolvedValueOnce({
      status: 'pending',
      url: 'https://auth.example.test/openai',
      instructions: 'Paste the authorization code from the browser.',
      methodType: 'code',
    })
    mocks.providerState.completeOAuthCallback.mockResolvedValueOnce(true)

    render(<LLMSection />)

    fireEvent.click(screen.getByRole('button', { name: 'Connect' }))
    fireEvent.click(screen.getByRole('button', { name: 'Login with browser' }))

    await waitFor(() => {
      expect(mocks.shellOpen).toHaveBeenCalledWith('https://auth.example.test/openai')
    })
    expect(mocks.providerState.completeOAuthCallback).not.toHaveBeenCalled()

    const codeInput = await screen.findByPlaceholderText('Paste authorization code')
    fireEvent.change(codeInput, { target: { value: 'oa-code-123' } })
    fireEvent.click(screen.getByRole('button', { name: 'Complete authorization' }))

    await waitFor(() => {
      expect(mocks.providerState.completeOAuthCallback).toHaveBeenCalledWith('openai', 0, 'oa-code-123')
    })
  })
})
