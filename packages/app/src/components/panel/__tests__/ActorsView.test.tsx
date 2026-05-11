import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { ActorsView } from '../ActorsView'

const supabaseFrom = vi.fn()
vi.mock('@/lib/supabase-client', () => ({
  supabase: {
    from: (...args: unknown[]) => supabaseFrom(...args),
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: 'u-1' } } }) },
  },
}))

vi.mock('@/stores/session-list-store', () => ({
  useSessionListStore: (sel: any) => sel({ rows: [{ id: 's-1', team_id: 'team-1' }] }),
}))

vi.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (k: string, fallback: string) => fallback }),
}))

beforeEach(() => {
  supabaseFrom.mockReset()
})

function mockActorsRows(rows: any[]) {
  supabaseFrom.mockImplementation((table: string) => {
    if (table === 'actor_directory') {
      return {
        select: () => ({
          eq: () => ({
            order: () => Promise.resolve({ data: rows, error: null }),
          }),
        }),
      }
    }
    return {
      select: () => ({
        eq: () => ({ limit: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: null }) }) }),
      }),
    }
  })
}

describe('ActorsView', () => {
  it('renders members and agents grouped', async () => {
    mockActorsRows([
      {
        id: 'a-1',
        actor_type: 'member',
        display_name: 'Alice',
        member_status: 'active',
        agent_status: null,
        last_active_at: null,
      },
      {
        id: 'a-2',
        actor_type: 'agent',
        display_name: 'Reviewer',
        member_status: null,
        agent_status: 'online',
        last_active_at: null,
      },
    ])
    render(<ActorsView />)
    await waitFor(() => expect(screen.getByText('Alice')).toBeInTheDocument())
    expect(screen.getByText('Reviewer')).toBeInTheDocument()
    expect(screen.getByText(/members/i)).toBeInTheDocument()
    expect(screen.getByText(/agents/i)).toBeInTheDocument()
  })

  it('renders empty state when no actors', async () => {
    mockActorsRows([])
    render(<ActorsView />)
    await waitFor(() => expect(screen.getByText(/no actors in this team yet/i)).toBeInTheDocument())
  })
})
