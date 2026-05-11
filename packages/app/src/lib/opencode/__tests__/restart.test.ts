import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

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
    vi.useFakeTimers()
    invokeMock.mockReset()
    workspaceState.setOpenCodeBootstrapped.mockReset()
    workspaceState.setOpenCodeReady.mockReset()
    initOpenCodeClientMock.mockReset()
  })

  afterEach(() => {
    vi.useRealTimers()
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

    await vi.advanceTimersByTimeAsync(500)
    resolveStart({ url: 'http://127.0.0.1:4096' })

    await expect(Promise.all([first, second])).resolves.toEqual([
      { url: 'http://127.0.0.1:4096' },
      { url: 'http://127.0.0.1:4096' },
    ])

    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(1)
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'start_opencode')).toHaveLength(1)
  })

  it('does not deduplicate concurrent reload requests for different workspaces', async () => {
    const startResolvers = new Map<string, (value: { url: string }) => void>()
    invokeMock.mockImplementation((command: string, args: { config?: { workspace_path?: string } }) => {
      if (command === 'stop_opencode') return Promise.resolve(undefined)
      if (command === 'start_opencode') {
        const workspacePath = args.config?.workspace_path ?? ''
        return new Promise((resolve) => {
          startResolvers.set(workspacePath, resolve as (value: { url: string }) => void)
        })
      }
      return Promise.resolve(undefined)
    })

    const { requestOpenCodeRuntimeReload } = await import('../restart')
    const first = requestOpenCodeRuntimeReload('/workspace/alpha', 'skills-file-change')
    const second = requestOpenCodeRuntimeReload('/workspace/beta', 'team-skills-sync')

    await vi.advanceTimersByTimeAsync(500)

    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(2)
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'start_opencode')).toHaveLength(2)

    startResolvers.get('/workspace/alpha')?.({ url: 'http://127.0.0.1:4096' })
    startResolvers.get('/workspace/beta')?.({ url: 'http://127.0.0.1:4097' })

    await expect(Promise.all([first, second])).resolves.toEqual([
      { url: 'http://127.0.0.1:4096' },
      { url: 'http://127.0.0.1:4097' },
    ])
  })
})
