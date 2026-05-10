import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MentionPopover, __clearCacheForTest } from '../MentionPopover'

const mockSelect = vi.fn()
const supabaseFrom = vi.fn()
vi.mock('@/lib/supabase-client', () => ({
  supabase: { from: (...args: unknown[]) => supabaseFrom(...args) },
}))
vi.mock('@/stores/session-store', () => ({
  useSessionStore: (sel: any) => sel({ currentSessionId: 'sess-1' }),
}))
vi.mock('@/stores/auth-store', () => ({
  useAuthStore: (sel: any) => sel({ session: { user: { id: 'user-1' } } }),
}))
vi.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (k: string, fallback: string) => fallback }),
}))

beforeEach(() => {
  mockSelect.mockReset()
  supabaseFrom.mockReset()
  __clearCacheForTest()
})

function mockParticipants(rows: Array<{ id: string; actor_type: 'member' | 'agent'; display_name: string }>) {
  supabaseFrom.mockImplementation(() => ({
    select: () => ({
      eq: () => Promise.resolve({
        data: rows.map(r => ({ actor_id: r.id, actors: r })),
        error: null,
      }),
    }),
  }))
}

describe('MentionPopover', () => {
  it('renders member and agent groups with icons after fetching session_participants', async () => {
    mockParticipants([
      { id: 'm-1', actor_type: 'member', display_name: 'Alice' },
      { id: 'a-1', actor_type: 'agent', display_name: 'Reviewer Bot' },
    ])
    render(
      <MentionPopover
        open={true}
        onOpenChange={() => {}}
        searchQuery=""
        onSearchChange={() => {}}
        onSelectMember={mockSelect}
        onSelectAgent={vi.fn()}
      />,
    )
    await waitFor(() => expect(screen.getByText('Alice')).toBeInTheDocument())
    expect(screen.getByText('Reviewer Bot')).toBeInTheDocument()
    expect(screen.getByText(/members/i)).toBeInTheDocument()
    expect(screen.getByText(/agents/i)).toBeInTheDocument()
  })

  it('calls onSelectMember when a member is clicked, onSelectAgent when an agent is clicked', async () => {
    const onSelectMember = vi.fn()
    const onSelectAgent = vi.fn()
    mockParticipants([
      { id: 'm-1', actor_type: 'member', display_name: 'Alice' },
      { id: 'a-1', actor_type: 'agent', display_name: 'Reviewer Bot' },
    ])
    const user = userEvent.setup()
    render(
      <MentionPopover
        open={true}
        onOpenChange={() => {}}
        searchQuery=""
        onSearchChange={() => {}}
        onSelectMember={onSelectMember}
        onSelectAgent={onSelectAgent}
      />,
    )
    await waitFor(() => screen.getByText('Alice'))
    await user.click(screen.getByText('Alice'))
    expect(onSelectMember).toHaveBeenCalledWith({ id: 'm-1', name: 'Alice' })
    await user.click(screen.getByText('Reviewer Bot'))
    expect(onSelectAgent).toHaveBeenCalledWith({ id: 'a-1', displayName: 'Reviewer Bot' })
  })

  it('shows empty state when participants list is empty', async () => {
    mockParticipants([])
    render(
      <MentionPopover
        open={true}
        onOpenChange={() => {}}
        searchQuery=""
        onSearchChange={() => {}}
        onSelectMember={vi.fn()}
        onSelectAgent={vi.fn()}
      />,
    )
    await waitFor(() => expect(screen.getByText(/no one to mention/i)).toBeInTheDocument())
  })

  it('shows error state when supabase returns an error', async () => {
    supabaseFrom.mockImplementation(() => ({
      select: () => ({
        eq: () => Promise.resolve({ data: null, error: new Error('rls denied') }),
      }),
    }))
    render(
      <MentionPopover
        open={true}
        onOpenChange={() => {}}
        searchQuery=""
        onSearchChange={() => {}}
        onSelectMember={vi.fn()}
        onSelectAgent={vi.fn()}
      />,
    )
    await waitFor(() => expect(screen.getByText(/failed to load participants/i)).toBeInTheDocument())
  })
})
