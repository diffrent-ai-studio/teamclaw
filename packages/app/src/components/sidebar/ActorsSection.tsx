import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, ChevronRight, Plus, Sparkles, User as UserIcon } from 'lucide-react'
import { useActorsForTeam, isActorOnline, type ActorRow } from '@/components/panel/ActorsView'
import { InviteActorDialog } from '@/components/sidebar/InviteActorDialog'
import { useUIStore } from '@/stores/ui'
import { cn } from '@/lib/utils'

export function ActorsSection() {
  const { t } = useTranslation()
  const collapsed = useUIStore((s) => s.actorsSectionCollapsed)
  const toggle = useUIStore((s) => s.toggleActorsSection)
  const filter = useUIStore((s) => s.sidebarFilter)
  const setFilter = useUIStore((s) => s.setSidebarFilter)
  const { actors, loading, teamId } = useActorsForTeam()
  const [inviteOpen, setInviteOpen] = React.useState(false)

  const handleClick = (actor: ActorRow) => {
    setFilter({
      kind: 'actor',
      actorId: actor.id,
      displayName: actor.display_name,
      actorType: actor.actor_type,
    })
  }

  return (
    <div className="flex flex-col">
      <div className="flex items-center gap-1 pr-1">
        <button
          type="button"
          onClick={toggle}
          className="group flex flex-1 items-center gap-1 px-2 py-1 text-left text-[11px] font-semibold uppercase tracking-wide text-muted-foreground/80 hover:text-foreground"
        >
          {collapsed ? <ChevronRight className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
          <span>{t('sidebar.actorsSection', 'Actors')}</span>
        </button>
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); setInviteOpen(true) }}
          className="rounded-md p-0.5 text-muted-foreground hover:bg-muted/60 hover:text-foreground"
          title={t('invite.title', 'Invite to team')}
          aria-label={t('invite.title', 'Invite to team')}
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>
      <InviteActorDialog open={inviteOpen} onOpenChange={setInviteOpen} teamId={teamId} />
      {!collapsed && (
        <div className="flex flex-col">
          {loading && (
            <div className="px-2 py-1 text-[11px] text-muted-foreground">{t('actors.loading', 'Loading actors...')}</div>
          )}
          {!loading && actors.length === 0 && (
            <div className="px-2 py-1 text-[11px] text-muted-foreground">{t('actors.empty', 'No actors in this team yet')}</div>
          )}
          {actors.map((actor) => {
            const active = filter.kind === 'actor' && filter.actorId === actor.id
            const online = isActorOnline(actor.last_active_at)
            const isAgent = actor.actor_type === 'agent'
            return (
              <button
                key={actor.id}
                type="button"
                onClick={() => handleClick(actor)}
                className={cn(
                  'relative flex w-full items-center gap-2 px-2 py-1.5 text-left text-sm hover:bg-muted/50',
                  active && 'bg-muted/40 font-medium before:absolute before:left-0 before:top-1/2 before:h-[72%] before:w-0.5 before:-translate-y-1/2 before:rounded-full before:bg-primary',
                )}
              >
                <div className={cn(
                  'relative flex h-5 w-5 shrink-0 items-center justify-center bg-muted text-[10px] font-medium text-muted-foreground',
                  isAgent ? 'rounded' : 'rounded-full',
                )}>
                  {actor.display_name?.slice(0, 1).toUpperCase() || (isAgent ? <Sparkles className="h-3 w-3" /> : <UserIcon className="h-3 w-3" />)}
                  {online && (
                    <span className="absolute -bottom-0.5 -right-0.5 h-1.5 w-1.5 rounded-full bg-emerald-500 ring-2 ring-background" />
                  )}
                </div>
                <span className="min-w-0 flex-1 truncate">{actor.display_name}</span>
                {isAgent && (
                  <span className="shrink-0 rounded bg-violet-500/15 px-1 py-0.5 text-[9px] font-medium text-violet-600 dark:text-violet-300">AI</span>
                )}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
