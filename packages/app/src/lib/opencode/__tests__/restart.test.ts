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

    await new Promise((resolve) => setTimeout(resolve, 550))
    resolveStart({ url: 'http://127.0.0.1:4096' })

    await expect(Promise.all([first, second])).resolves.toEqual([
      { url: 'http://127.0.0.1:4096' },
      { url: 'http://127.0.0.1:4096' },
    ])

    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'stop_opencode')).toHaveLength(1)
    expect(invokeMock.mock.calls.filter(([cmd]) => cmd === 'start_opencode')).toHaveLength(1)
  })
})
