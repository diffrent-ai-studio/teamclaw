import * as React from 'react'
import { User, Sparkles, Search } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandList,
} from '@/components/ui/command'
import { supabase } from '@/lib/supabase-client'
import { useSessionStore } from '@/stores/session-store'
import { type MentionedPerson } from '@/packages/ai/prompt-input'
import type { AttachedAgent } from '@/packages/ai/prompt-input-insert-hooks'

export type { MentionedPerson }

interface MentionPopoverProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  searchQuery: string
  onSearchChange: (query: string) => void
  onSelectMember: (person: MentionedPerson) => void
  onSelectAgent: (agent: AttachedAgent) => void
}

type ParticipantRow = {
  id: string
  actor_type: 'member' | 'agent'
  display_name: string
}

const cache = new Map<string, { fetchedAt: number; rows: ParticipantRow[] }>()
const CACHE_TTL_MS = 30_000

/** @internal — test helper only */
export function __clearCacheForTest() { cache.clear() }

async function fetchParticipants(sessionId: string): Promise<ParticipantRow[]> {
  const hit = cache.get(sessionId)
  if (hit && Date.now() - hit.fetchedAt < CACHE_TTL_MS) return hit.rows
  const { data, error } = await supabase
    .from('session_participants')
    .select('actor_id, actors!inner(id, actor_type, display_name)')
    .eq('session_id', sessionId)
  if (error) throw error
  if (!data) return []
  const rows: ParticipantRow[] = data
    .map((d: any) => d.actors as ParticipantRow)
    .filter((a): a is ParticipantRow => !!a)
  cache.set(sessionId, { fetchedAt: Date.now(), rows })
  return rows
}

function filter(rows: ParticipantRow[], query: string): ParticipantRow[] {
  if (!query) return rows
  const q = query.toLowerCase()
  return rows.filter(r => r.display_name.toLowerCase().includes(q))
}

export function MentionPopover({
  open,
  onOpenChange,
  searchQuery,
  onSearchChange,
  onSelectMember,
  onSelectAgent,
}: MentionPopoverProps) {
  const { t } = useTranslation()
  const sessionId = useSessionStore(s => s.currentSessionId)
  const [rows, setRows] = React.useState<ParticipantRow[]>([])
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState(false)
  const inputRef = React.useRef<HTMLInputElement>(null)

  React.useEffect(() => {
    if (!open || !sessionId) return
    let cancelled = false
    setLoading(true)
    setError(false)
    fetchParticipants(sessionId)
      .then(r => { if (!cancelled) setRows(r) })
      .catch(() => { if (!cancelled) setError(true) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [open, sessionId])

  React.useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 50)
  }, [open])

  if (!open) return null

  const filtered = filter(rows, searchQuery)
  const members = filtered.filter(r => r.actor_type === 'member')
  const agents = filtered.filter(r => r.actor_type === 'agent')
  const isEmpty = !loading && !error && filtered.length === 0

  return (
    <div
      className="absolute bottom-full left-0 mb-2 w-80 rounded-lg border bg-popover shadow-lg z-50"
      onKeyDown={(e) => { if (e.key === 'Escape') { e.preventDefault(); onOpenChange(false) } }}
    >
      <Command shouldFilter={false}>
        <div className="flex items-center gap-2 border-b px-3 py-2">
          <Search className="h-4 w-4 text-muted-foreground shrink-0" />
          <input
            ref={inputRef}
            type="text"
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder={t('chat.mentionPopoverTitle', 'Mention people or agents')}
            className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
        <CommandList className="max-h-60 overflow-y-auto">
          {loading && (
            <div className="py-4 text-center text-sm text-muted-foreground">…</div>
          )}
          {error && (
            <CommandEmpty>{t('chat.mentionPopoverError', 'Failed to load participants')}</CommandEmpty>
          )}
          {isEmpty && (
            <CommandEmpty>{t('chat.mentionEmptyState', 'No one to mention in this session yet')}</CommandEmpty>
          )}
          {members.length > 0 && (
            <CommandGroup heading={t('chat.mentionGroupMembers', 'Members')}>
              {members.map(m => (
                <CommandItem
                  key={m.id}
                  value={`m:${m.id}`}
                  onSelect={() => {
                    onSelectMember({ id: m.id, name: m.display_name })
                    onOpenChange(false)
                  }}
                  className="flex items-center gap-2 cursor-pointer"
                >
                  <User className="h-4 w-4 text-muted-foreground shrink-0" />
                  <span className="text-sm font-medium truncate">{m.display_name}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          )}
          {agents.length > 0 && (
            <CommandGroup heading={t('chat.mentionGroupAgents', 'Agents')}>
              {agents.map(a => (
                <CommandItem
                  key={a.id}
                  value={`a:${a.id}`}
                  onSelect={() => {
                    onSelectAgent({ id: a.id, displayName: a.display_name })
                    onOpenChange(false)
                  }}
                  className="flex items-center gap-2 cursor-pointer"
                >
                  <Sparkles className="h-4 w-4 text-orange-500 shrink-0" />
                  <span className="text-sm font-medium truncate">{a.display_name}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          )}
        </CommandList>
      </Command>
    </div>
  )
}
