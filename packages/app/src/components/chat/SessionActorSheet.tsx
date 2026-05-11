import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { Loader2, Users, User as UserIcon, Sparkles } from 'lucide-react'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { supabase } from '@/lib/supabase-client'
import { cn } from '@/lib/utils'

// ── Types ──────────────────────────────────────────────────────────────────

type Row = {
  id: string
  actor_type: 'member' | 'agent'
  display_name: string
  member_status: string | null
  agent_status: string | null
  agent_kind: string | null
  last_active_at: string | null
}

// ── Helpers ────────────────────────────────────────────────────────────────

function isOnline(lastActiveAt: string | null): boolean {
  if (!lastActiveAt) return false
  const t = Date.parse(lastActiveAt)
  if (Number.isNaN(t)) return false
  return Date.now() - t < 5 * 60 * 1000
}

function computeDotColor(actor: Row): string {
  if (actor.actor_type === 'member') {
    return isOnline(actor.last_active_at) ? 'bg-emerald-500' : 'bg-muted-foreground/40'
  }
  // agent
  const s = actor.agent_status
  if (s === 'active' || s === 'idle') return 'bg-emerald-500'
  if (s === 'error') return 'bg-red-500'
  return 'bg-muted-foreground/40'
}

// ── ActorRowView ───────────────────────────────────────────────────────────

function ActorRowView({ actor }: { actor: Row }) {
  const isAgent = actor.actor_type === 'agent'
  const initials = actor.display_name?.slice(0, 2).toUpperCase() || ''
  const dotColor = computeDotColor(actor)
  const subline = isAgent ? (actor.agent_kind || '') : (actor.member_status || '')

  return (
    <div className="flex items-center gap-3 px-4 py-2.5">
      <div
        className={cn(
          'relative flex h-8 w-8 shrink-0 items-center justify-center bg-muted text-xs font-medium text-muted-foreground',
          isAgent ? 'rounded-md' : 'rounded-full',
        )}
      >
        {initials || (isAgent ? <Sparkles className="h-4 w-4" /> : <UserIcon className="h-4 w-4" />)}
        <span
          className={cn(
            'absolute -bottom-0.5 -right-0.5 h-2 w-2 rounded-full ring-2 ring-background',
            dotColor,
          )}
        />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium">{actor.display_name}</div>
        {subline && (
          <div className="truncate text-[11px] text-muted-foreground">{subline}</div>
        )}
      </div>
    </div>
  )
}

// ── SessionActorSheet ──────────────────────────────────────────────────────

export interface SessionActorSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  sessionId: string | null
}

export function SessionActorSheet({ open, onOpenChange, sessionId }: SessionActorSheetProps) {
  const { t } = useTranslation()
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState(false)
  const [actors, setActors] = React.useState<Row[]>([])

  React.useEffect(() => {
    if (!open || !sessionId) return
    let cancelled = false
    setLoading(true)
    setError(false)
    void (async () => {
      // Step 1: get actor_id list for the session
      const { data: participantData, error: participantError } = await supabase
        .from('session_participants')
        .select('actor_id')
        .eq('session_id', sessionId)

      if (cancelled) return
      if (participantError) {
        console.error('[SessionActorSheet] fetch failed', participantError)
        setError(true)
        setLoading(false)
        return
      }

      const actorIds = (participantData ?? []).map((r: { actor_id: string }) => r.actor_id)

      if (actorIds.length === 0) {
        setActors([])
        setLoading(false)
        return
      }

      // Step 2: fetch actor_directory rows
      const { data: actorData, error: actorError } = await supabase
        .from('actor_directory')
        .select('id, actor_type, display_name, member_status, agent_status, agent_kind, last_active_at')
        .in('id', actorIds)

      if (cancelled) return
      if (actorError) {
        console.error('[SessionActorSheet] fetch failed', actorError)
        setError(true)
        setLoading(false)
        return
      }

      setActors((actorData ?? []) as Row[])
      setLoading(false)
    })()
    return () => {
      cancelled = true
    }
  }, [open, sessionId])

  const members = actors.filter((a) => a.actor_type === 'member')
  const agents = actors.filter((a) => a.actor_type === 'agent')

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="w-full sm:w-96 p-0 flex flex-col">
        <SheetHeader className="px-4 py-3 border-b">
          <SheetTitle>{t('chat.actorSheet.title', 'Actors')}</SheetTitle>
        </SheetHeader>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {loading && (
            <div className="flex flex-col items-center justify-center py-12 text-sm text-muted-foreground">
              <Loader2 className="mb-2 h-5 w-5 animate-spin" />
              <span>{t('chat.actorSheet.loading', 'Loading actors...')}</span>
            </div>
          )}

          {!loading && error && (
            <div className="px-4 py-3 text-sm text-destructive">
              {t('chat.actorSheet.error', 'Failed to load actors')}
            </div>
          )}

          {!loading && !error && members.length === 0 && agents.length === 0 && (
            <div className="flex flex-col items-center justify-center py-12 text-center text-sm text-muted-foreground">
              <Users className="mb-2 h-8 w-8 text-muted-foreground" />
              <span>{t('chat.actorSheet.empty', 'No participants in this session')}</span>
            </div>
          )}

          {!loading && !error && (members.length > 0 || agents.length > 0) && (
            <>
              {members.length > 0 && (
                <>
                  <div className="px-4 pb-1 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80">
                    {t('chat.mentionGroupMembers', 'Members')}
                  </div>
                  {members.map((m) => (
                    <ActorRowView key={m.id} actor={m} />
                  ))}
                </>
              )}
              {agents.length > 0 && (
                <>
                  <div className="px-4 pb-1 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80">
                    {t('chat.mentionGroupAgents', 'Agents')}
                  </div>
                  {agents.map((a) => (
                    <ActorRowView key={a.id} actor={a} />
                  ))}
                </>
              )}
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  )
}
