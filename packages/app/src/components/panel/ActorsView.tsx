import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { Loader2, Users, User as UserIcon, Sparkles } from 'lucide-react'
import { supabase } from '@/lib/supabase-client'
import { useSessionListStore } from '@/stores/session-list-store'
import { useUIStore } from '@/stores/ui'
import { cn, isTauri } from '@/lib/utils'
import { loadActorsForTeam, upsertActorsBatch, type ActorRow as CachedActorRow } from '@/lib/local-cache'

export type ActorRow = {
  id: string
  actor_type: 'member' | 'agent'
  display_name: string
  member_status: string | null
  agent_status: string | null
  last_active_at: string | null
}

export interface UseActorsForTeamResult {
  actors: ActorRow[]
  loading: boolean
  error: boolean
  teamId: string | null
}

export function useActorsForTeam(): UseActorsForTeamResult {
  const sessionRows = useSessionListStore((s) => s.rows)
  const [teamId, setTeamId] = React.useState<string | null>(null)
  const [actors, setActors] = React.useState<ActorRow[]>([])
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState(false)

  React.useEffect(() => {
    if (teamId) return
    const fromSession = sessionRows[0]?.team_id
    if (fromSession) {
      setTeamId(fromSession)
      return
    }
    let cancelled = false
    void (async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user || cancelled) return
      const { data: actorRow } = await supabase
        .from('actors')
        .select('id, team_id')
        .eq('user_id', user.id)
        .limit(1)
        .maybeSingle()
      if (!cancelled) setTeamId(actorRow?.team_id ?? null)
    })()
    return () => { cancelled = true }
  }, [sessionRows, teamId])

  React.useEffect(() => {
    if (!teamId) return
    let cancelled = false
    setError(false)

    void (async () => {
      let hadLocal = false
      if (isTauri()) {
        const local = await loadActorsForTeam(teamId)
        if (cancelled) return
        if (local.length > 0) {
          const sorted = [...local].sort((a, b) => a.displayName.localeCompare(b.displayName))
          setActors(sorted.map((r): ActorRow => ({
            id: r.id,
            actor_type: r.actorType === 'agent' ? 'agent' : 'member',
            display_name: r.displayName,
            member_status: r.memberStatus ?? null,
            agent_status: r.agentStatus ?? null,
            last_active_at: null,
          })))
          hadLocal = true
          setLoading(false)
        }
      }
      if (!hadLocal) setLoading(true)

      const { data, error: fetchError } = await supabase
        .from('actor_directory')
        .select('id, actor_type, display_name, member_status, agent_status, last_active_at')
        .eq('team_id', teamId)
        .order('display_name', { ascending: true })
      if (cancelled) return
      if (fetchError) {
        console.error('[useActorsForTeam] fetch failed', fetchError)
        if (!hadLocal) setError(true)
        setLoading(false)
        return
      }
      const rows = (data ?? []) as ActorRow[]
      setActors(rows)
      setLoading(false)

      if (isTauri() && rows.length > 0) {
        const now = new Date().toISOString()
        const cached: CachedActorRow[] = rows.map((r) => ({
          id: r.id,
          teamId,
          actorType: r.actor_type,
          displayName: r.display_name,
          memberStatus: r.member_status,
          agentStatus: r.agent_status,
          createdAt: now,
          updatedAt: now,
          syncedAt: now,
        }))
        await upsertActorsBatch(cached).catch((e) => {
          console.warn('[useActorsForTeam] upsertActorsBatch failed', e)
        })
      }
    })()

    return () => { cancelled = true }
  }, [teamId])

  return { actors, loading, error, teamId }
}

export function isActorOnline(lastActiveAt: string | null): boolean {
  if (!lastActiveAt) return false
  const t = Date.parse(lastActiveAt)
  if (Number.isNaN(t)) return false
  return Date.now() - t < 5 * 60 * 1000
}

function ActorRowView({ actor }: { actor: ActorRow }) {
  const online = isActorOnline(actor.last_active_at)
  const status = actor.actor_type === 'member' ? actor.member_status : actor.agent_status
  const initials = actor.display_name?.slice(0, 2).toUpperCase() || ''
  const isAgent = actor.actor_type === 'agent'
  const enterActorDraft = useUIStore((s) => s.enterActorDraft)
  return (
    <button
      type="button"
      onClick={() => enterActorDraft({ id: actor.id, displayName: actor.display_name, kind: actor.actor_type })}
      className="flex w-full items-center gap-2.5 px-2 py-2 text-left hover:bg-muted/50 focus:outline-none focus-visible:bg-muted/50"
    >
      <div className={cn(
        'relative flex h-8 w-8 shrink-0 items-center justify-center bg-muted text-xs font-medium text-muted-foreground',
        isAgent ? 'rounded-md' : 'rounded-full',
      )}>
        {initials || (isAgent ? <Sparkles className="h-4 w-4" /> : <UserIcon className="h-4 w-4" />)}
        {online && (
          <span className="absolute -bottom-0.5 -right-0.5 h-2 w-2 rounded-full bg-emerald-500 ring-2 ring-background" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium">{actor.display_name}</div>
        {status && <div className="truncate text-[11px] text-muted-foreground">{status}</div>}
      </div>
    </button>
  )
}

export function ActorsView() {
  const { t } = useTranslation()
  const { actors, loading, error } = useActorsForTeam()

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
          {members.map((a) => <ActorRowView key={a.id} actor={a} />)}
        </>
      )}
      {agents.length > 0 && (
        <>
          <div className="px-2 pb-1 pt-3 text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80">
            {t('chat.mentionGroupAgents', 'Agents')}
          </div>
          {agents.map((a) => <ActorRowView key={a.id} actor={a} />)}
        </>
      )}
    </div>
  )
}
