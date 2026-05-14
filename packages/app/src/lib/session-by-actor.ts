import { supabase } from '@/lib/supabase-client'
import { isTauri } from '@/lib/utils'

const cache = new Map<string, Set<string>>()

/**
 * Resolve the set of session ids the given actor participates in.
 * Tauri path: read from local cache first if available. Always falls back to
 * Supabase as source of truth. Results are memoized per process by actorId.
 */
export async function loadSessionIdsForActor(actorId: string, _teamId: string): Promise<Set<string>> {
  const cached = cache.get(actorId)
  if (cached) return cached

  const ids = new Set<string>()

  if (isTauri()) {
    try {
      const localMod = await import('@/lib/local-cache')
      const fn = (localMod as unknown as { loadSessionParticipantsByActor?: (a: string) => Promise<Array<{ sessionId: string }>> }).loadSessionParticipantsByActor
      if (typeof fn === 'function') {
        const rows = await fn(actorId)
        for (const row of rows) ids.add(row.sessionId)
      }
    } catch (e) {
      console.warn('[session-by-actor] local cache lookup failed (non-fatal)', e)
    }
  }

  const { data, error } = await supabase
    .from('session_participants')
    .select('session_id')
    .eq('actor_id', actorId)

  if (error) {
    console.error('[session-by-actor] supabase lookup failed', error)
  } else {
    for (const row of (data ?? []) as Array<{ session_id: string }>) {
      ids.add(row.session_id)
    }
  }

  cache.set(actorId, ids)
  return ids
}

/** Test/reset hook — clear the in-memory memo. */
export function clearSessionByActorCache(): void {
  cache.clear()
}
