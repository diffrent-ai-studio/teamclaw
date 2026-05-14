import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { Loader2, Lightbulb } from 'lucide-react'
import { supabase } from '@/lib/supabase-client'
import { useSessionListStore } from '@/stores/session-list-store'
import { formatRelativeTime } from '@/lib/date-format'
import { cn } from '@/lib/utils'

export type IdeaRow = {
  id: string
  title: string
  status: 'open' | 'in_progress' | 'done' | null
  created_by_actor_id: string
  updated_at: string
}

export type IdeaCreatorMap = Map<string, string>

export interface UseIdeasForTeamResult {
  ideas: IdeaRow[]
  creators: IdeaCreatorMap
  loading: boolean
  error: boolean
  teamId: string | null
  refetch: () => void
}

export function useIdeasForTeam(): UseIdeasForTeamResult {
  const sessionRows = useSessionListStore(s => s.rows)
  const [teamId, setTeamId] = React.useState<string | null>(null)
  const [ideas, setIdeas] = React.useState<IdeaRow[]>([])
  const [creators, setCreators] = React.useState<IdeaCreatorMap>(new Map())
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState(false)
  const [refreshTick, setRefreshTick] = React.useState(0)

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
      if (!user) return
      const { data: actorRow } = await supabase.from('actors').select('id, team_id').eq('user_id', user.id).limit(1).maybeSingle()
      if (cancelled) return
      if (actorRow?.team_id) setTeamId(actorRow.team_id as string)
    })()
    return () => { cancelled = true }
  }, [sessionRows, teamId])

  React.useEffect(() => {
    if (!teamId) return
    let cancelled = false
    setLoading(true)
    setError(false)
    void (async () => {
      const { data, error } = await supabase
        .from('ideas')
        .select('id, title, status, created_by_actor_id, updated_at')
        .eq('team_id', teamId)
        .eq('archived', false)
        .order('updated_at', { ascending: false })
      if (cancelled) return
      if (error) { setError(true); setLoading(false); return }
      const rows = (data ?? []) as IdeaRow[]
      setIdeas(rows)
      const creatorIds = Array.from(new Set(rows.map(r => r.created_by_actor_id).filter(Boolean)))
      if (creatorIds.length > 0) {
        const { data: actorRows } = await supabase
          .from('actors')
          .select('id, display_name')
          .in('id', creatorIds)
        if (cancelled) return
        const map = new Map<string, string>()
        for (const r of (actorRows ?? []) as { id: string; display_name: string }[]) {
          map.set(r.id, r.display_name)
        }
        setCreators(map)
      } else {
        setCreators(new Map())
      }
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [teamId, refreshTick])

  const refetch = React.useCallback(() => setRefreshTick((n) => n + 1), [])

  return { ideas, creators, loading, error, teamId, refetch }
}

function StatusBadge({ status }: { status: IdeaRow['status'] }) {
  if (!status) return null
  const styles =
    status === 'in_progress' ? 'bg-amber-500/10 text-amber-600 dark:text-amber-400'
    : status === 'done' ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
    : 'bg-muted text-muted-foreground'
  const label =
    status === 'in_progress' ? 'In progress'
    : status === 'done' ? 'Done'
    : 'Open'
  return <span className={cn('shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium', styles)}>{label}</span>
}

function IdeaRowView({ idea, creatorName }: { idea: IdeaRow; creatorName: string | undefined }) {
  const relative = formatRelativeTime(new Date(idea.updated_at))
  return (
    <div className="flex items-start gap-2 px-2 py-2.5 hover:bg-muted/50 cursor-pointer">
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium">{idea.title}</div>
        <div className="truncate text-[11px] text-muted-foreground">
          {creatorName ? `${creatorName} · ${relative}` : relative}
        </div>
      </div>
      <StatusBadge status={idea.status} />
    </div>
  )
}

export function IdeasView() {
  const { t } = useTranslation()
  const { ideas, creators, loading, error } = useIdeasForTeam()

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-sm text-muted-foreground">
        <Loader2 className="mb-2 h-5 w-5 animate-spin" />
        <span>{t('ideas.loading', 'Loading ideas...')}</span>
      </div>
    )
  }

  if (error) {
    return <div className="px-4 py-3 text-sm text-destructive">{t('ideas.error', 'Failed to load ideas')}</div>
  }

  if (ideas.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center text-sm text-muted-foreground">
        <Lightbulb className="mb-2 h-8 w-8 text-muted-foreground" />
        <span>{t('ideas.empty', 'No ideas yet')}</span>
      </div>
    )
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden">
      {ideas.map(idea => (
        <IdeaRowView key={idea.id} idea={idea} creatorName={creators.get(idea.created_by_actor_id)} />
      ))}
    </div>
  )
}
