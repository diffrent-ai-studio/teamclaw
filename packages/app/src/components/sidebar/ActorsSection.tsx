import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, ChevronRight, Plus, Sparkles, User as UserIcon } from 'lucide-react'
import { useActorsForTeam, isActorOnline, type ActorRow } from '@/components/panel/ActorsView'
import { InviteActorDialog } from '@/components/sidebar/InviteActorDialog'
import { useUIStore } from '@/stores/ui'
import { cn } from '@/lib/utils'
import { actorAvatarColor } from '@/lib/actor-color'

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
      {/* Group header: 10.5px faint, count suffix `· N`. AGENTS.md §2. */}
      <div className="flex items-center gap-1 pr-1">
        <button
          type="button"
          onClick={toggle}
          className="group flex flex-1 items-center gap-1.5 rounded-md px-[9px] py-1 text-left text-[10.5px] font-semibold uppercase tracking-[0.08em] text-faint hover:text-foreground"
        >
          {collapsed ? <ChevronRight className="h-[10px] w-[10px]" /> : <ChevronDown className="h-[10px] w-[10px]" />}
          <span>{t('sidebar.actorsSection', 'Actors')}</span>
          {actors.length > 0 && (
            <span className="font-mono font-normal normal-case tracking-normal text-faint/80">
              · {actors.length}
            </span>
          )}
        </button>
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); setInviteOpen(true) }}
          className="rounded-md p-0.5 text-faint hover:bg-selected/60 hover:text-foreground"
          title={t('invite.title', 'Invite to team')}
          aria-label={t('invite.title', 'Invite to team')}
        >
          <Plus className="h-[11px] w-[11px]" />
        </button>
      </div>
      <InviteActorDialog open={inviteOpen} onOpenChange={setInviteOpen} teamId={teamId} />
      {!collapsed && (
        <div className="flex flex-col">
          {loading && (
            <div className="px-[9px] py-1 text-[12px] text-faint">{t('actors.loading', 'Loading actors...')}</div>
          )}
          {!loading && actors.length === 0 && (
            <div className="px-[9px] py-1 text-[12px] text-faint">{t('actors.empty', 'No actors in this team yet')}</div>
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
                  // Direction B row: tight 5×9 padding, selected fill on active,
                  // no left bar (reserved for session list cards). AGENTS.md §2.
                  'flex w-full items-center gap-[9px] rounded-md px-[9px] py-[5px] text-left text-[12.5px] transition-colors',
                  active
                    ? 'bg-selected font-semibold text-foreground'
                    : 'text-ink-2 hover:bg-selected/60',
                )}
              >
                <div
                  className={cn(
                    'relative flex h-5 w-5 shrink-0 items-center justify-center text-[10px] font-semibold',
                    isAgent ? 'rounded' : 'rounded-full',
                  )}
                  style={(() => {
                    const c = actorAvatarColor(actor.id)
                    return { background: c.bg, color: c.fg }
                  })()}
                >
                  {actor.display_name?.slice(0, 1).toUpperCase() || (isAgent ? <Sparkles className="h-3 w-3" /> : <UserIcon className="h-3 w-3" />)}
                  {online && (
                    <span className="absolute -bottom-0.5 -right-0.5 h-1.5 w-1.5 rounded-full bg-emerald-500 ring-2 ring-paper" />
                  )}
                </div>
                <span className="min-w-0 flex-1 truncate">{actor.display_name}</span>
                {isAgent && (
                  <span className="shrink-0 font-mono text-[9px] font-semibold tracking-wider text-coral">
                    AI
                  </span>
                )}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
