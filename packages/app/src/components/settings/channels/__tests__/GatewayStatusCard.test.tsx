import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'

// ── hoisted mocks ────────────────────────────────────────────────────────────

vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (_k: string, d?: string) => d ?? _k,
    i18n: { language: 'en', changeLanguage: vi.fn() },
  }),
}))

vi.mock('../shared', () => ({
  SettingCard: ({ children }: { children: React.ReactNode }) => (
    <div data-testid="setting-card">{children}</div>
  ),
  ToggleSwitch: ({ enabled }: { enabled: boolean }) => (
    <input type="checkbox" checked={enabled} readOnly />
  ),
  StatusBadge: ({ status }: { status: string }) => <span>{status}</span>,
}))

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn() }))

vi.mock('@/lib/amuxd-channels', async () => {
  const actual = await vi.importActual<typeof import('@/lib/amuxd-channels')>(
    '@/lib/amuxd-channels',
  )
  return {
    ...actual,
    listChannels: vi.fn(),
  }
})

// ── imports after mocks ──────────────────────────────────────────────────────

import * as api from '@/lib/amuxd-channels'
import { GatewayStatusCard } from '../GatewayStatusCard'

// ── shared props ─────────────────────────────────────────────────────────────

const noop = () => {}

const baseProps = {
  icon: <span data-testid="icon" />,
  title: 'Discord Gateway',
  status: 'disconnected' as const,
  expanded: false,
  onToggleExpanded: noop,
  enabled: false,
  onToggleEnabled: noop,
  isLoading: false,
  isConnecting: false,
  isRunning: false,
  hasChanges: false,
  onStartStop: noop,
  onRestart: noop,
}

// ── tests ────────────────────────────────────────────────────────────────────

describe('GatewayStatusCard', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it("shows 'amuxd not running' banner when amuxd is unreachable", async () => {
    vi.mocked(api.listChannels).mockRejectedValue(new api.AmuxdUnreachableError())
    render(<GatewayStatusCard {...baseProps} />)
    await waitFor(() => {
      expect(screen.getByText(/amuxd not running/i)).toBeTruthy()
    })
  })

  it('does not show the banner when amuxd returns statuses successfully', async () => {
    vi.mocked(api.listChannels).mockResolvedValue([
      { platform: 'discord', enabled: true, connected: false, lastError: null },
    ])
    render(<GatewayStatusCard {...baseProps} title="Discord Gateway" />)
    // Title should be visible
    await waitFor(() => {
      expect(screen.getByText('Discord Gateway')).toBeTruthy()
    })
    // Banner must NOT be present
    expect(screen.queryByText(/amuxd not running/i)).toBeNull()
  })

  it('shows the banner immediately when amuxdUnreachable prop is true (no fetch needed)', () => {
    // listChannels should NOT be called when prop is provided
    render(<GatewayStatusCard {...baseProps} amuxdUnreachable={true} />)
    expect(screen.getByText(/amuxd not running/i)).toBeTruthy()
    expect(api.listChannels).not.toHaveBeenCalled()
  })
})
