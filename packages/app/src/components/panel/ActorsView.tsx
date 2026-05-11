import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { Loader2, Users, User as UserIcon, Sparkles } from 'lucide-react'
import { supabase } from '@/lib/supabase-client'
import { useSessionListStore } from '@/stores/session-list-store'
import { cn } from '@/lib/utils'

type ActorRow = {
  id: string
  actor_type: 'member' | 'agent'
  display_name: string
  member_status: string | null
  agent_status: string | null
  last_active_at: string | null
}

function isOnline(lastActiveAt: string | null): boolean {
  if (!lastActiveAt) return false
  const t = Date.parse(lastActiveAt)
  if (Number.isNaN(t)) return false
  return Date.now() - t < 5 * 60 * 1000
}

function ActorRowView({ actor }: { actor: ActorRow }) {
  const online = isOnline(actor.last_active_at)
  const status = actor.actor_type === 'member' ? actor.member_status : actor.agent_status
  const initials = actor.display_name?.slice(0, 2).toUpperCase() || ''
  const isAgent = actor.actor_type === 'agent'
  return (
    <div className="flex items-center gap-2.5 px-2 py-2">
      <div
        className={cn(
          'relative flex h-8 w-8 shrink-0 items-center justify-center bg-muted text-xs font-medium text-muted-foreground',
          isAgent ? 'rounded-md' : 'rounded-full',
        )}
      >
        {initials || (isAgent ? <Sparkles className="h-4 w-4" /> : <UserIcon className="h-4 w-4" />)}
        {online && (
          <span className="absolute -bottom-0.5 -right-0.5 h-2 w-2 rounded-full bg-emerald-500 ring-2 ring-background" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium">{actor.display_name}</div>
        {status && <div className="truncate text-[11px] text-muted-foreground">{status}</div>}
      </div>
    </div>
  )
}

export function ActorsView() {
  const { t } = useTranslation()
  const sessionRows = useSessionListStore((s) => s.rows)
  const [teamId, setTeamId] = React.useState<string | null>(null)
  const [actors, setActors] = React.useState<ActorRow[]>([])
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState(false)

  // Resolve team_id: prefer existing session row, otherwise query Supabase once.
  React.useEffect(() => {
    if (teamId) return
    const fromSession = sessionRows[0]?.team_id
    if (fromSession) {
      setTeamId(fromSession)
      return
    }
    let cancelled = false
    void (async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user || cancelled) return
      const { data: actorRow } = await supabase
        .from('actors')
        .select('id, team_id')
        .eq('user_id', user.id)
        .limit(1)
        .maybeSingle()
      if (!cancelled) setTeamId(actorRow?.team_id ?? null)
    })()
    return () => {
      cancelled = true
    }
  }, [sessionRows, teamId])

  // Fetch actors for the resolved team_id.
  React.useEffect(() => {
    if (!teamId) return
    let cancelled = false
    setLoading(true)
    setError(false)
    void (async () => {
      const { data, error: fetchError } = await supabase
        .from('actor_directory')
        .select('id, actor_type, display_name, member_status, agent_status, last_active_at')
        .eq('team_id', teamId)
        .order('display_name', { ascending: true })
      if (cancelled) return
      if (fetchError) {
        console.error('[ActorsView] fetch failed', fetchError)
        setError(true)
      } else {
        setActors((data ?? []) as ActorRow[])
      }
      setLoading(false)
    })()
    return () => {
      cancelled = true
    }
  }, [teamId])

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-sm text-muted-foreground">
        <Loader2 className="mb-2 h-5 w-5 animate-spin" />
        <span>{t('actors.loading', 'Loading actors...')}</span>
      </div>
    )
  }

  if (error) {
    return (
      <div className="px-4 py-3 text-sm text-destructive">{t('actors.error', 'Failed to load actors')}</div>
    )
  }

  const members = actors.filter((a) => a.actor_type === 'member')
  const agents = actors.filter((a) => a.actor_type === 'agent')

  if (members.length === 0 && agents.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center text-sm text-muted-foreground">
        <Users className="mb-2 h-8 w-8 text-muted-foreground" />
        <span>{t('actors.empty', 'No actors in this team yet')}</span>
      </div>
    )
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden">
      {members.length > 0 && (
        <>
          <div className="px-2 pb-1 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80">
            {t('chat.mentionGroupMembers', 'Members')}
          </div>
          {members.map((a) => (
            <ActorRowView key={a.id} actor={a} />
          ))}
        </>
      )}
      {agents.length > 0 && (
        <>
          <div className="px-2 pb-1 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80">
            {t('chat.mentionGroupAgents', 'Agents')}
          </div>
          {agents.map((a) => (
            <ActorRowView key={a.id} actor={a} />
          ))}
        </>
      )}
    </div>
  )
}
