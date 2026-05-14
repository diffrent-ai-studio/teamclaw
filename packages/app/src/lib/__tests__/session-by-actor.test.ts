import { describe, it, expect, vi, beforeEach } from 'vitest'
import { loadSessionIdsForActor, clearSessionByActorCache } from '../session-by-actor'

vi.mock('@/lib/supabase-client', () => ({
  supabase: {
    from: vi.fn(),
  },
}))

vi.mock('@/lib/utils', () => ({
  isTauri: () => false,
}))

import { supabase } from '@/lib/supabase-client'

describe('loadSessionIdsForActor', () => {
  beforeEach(() => {
    clearSessionByActorCache()
    vi.clearAllMocks()
  })

  it('returns set of session_ids from Supabase when not in Tauri', async () => {
    const mockSelect = vi.fn().mockResolvedValue({
      data: [
        { session_id: 's1' },
        { session_id: 's2' },
        { session_id: 's3' },
      ],
      error: null,
    })
    ;(supabase.from as any).mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue(mockSelect()),
      }),
    })

    const result = await loadSessionIdsForActor('actor-1', 'team-1')
    expect(result).toEqual(new Set(['s1', 's2', 's3']))
  })

  it('returns empty set on Supabase error', async () => {
    ;(supabase.from as any).mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ data: null, error: { message: 'boom' } }),
      }),
    })

    const result = await loadSessionIdsForActor('actor-1', 'team-1')
    expect(result).toEqual(new Set())
  })

  it('memoizes results by actorId', async () => {
    const eqFn = vi.fn().mockResolvedValue({ data: [{ session_id: 's1' }], error: null })
    ;(supabase.from as any).mockReturnValue({
      select: vi.fn().mockReturnValue({ eq: eqFn }),
    })

    await loadSessionIdsForActor('actor-1', 'team-1')
    await loadSessionIdsForActor('actor-1', 'team-1')

    expect(eqFn).toHaveBeenCalledTimes(1)
  })
})
