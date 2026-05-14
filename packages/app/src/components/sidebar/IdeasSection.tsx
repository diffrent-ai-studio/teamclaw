import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { ChevronDown, ChevronRight, Plus } from 'lucide-react'
import { useIdeasForTeam, type IdeaRow } from '@/components/panel/IdeasView'
import { CreateIdeaDialog } from '@/components/sidebar/CreateIdeaDialog'
import { useUIStore } from '@/stores/ui'
import { cn } from '@/lib/utils'

function ideaStatusLabel(status: IdeaRow['status']): { label: string; tone: string } {
  if (status === 'in_progress') return { label: 'active', tone: 'bg-amber-500/15 text-amber-600 dark:text-amber-400' }
  if (status === 'done') return { label: 'done', tone: 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400' }
  return { label: 'open', tone: 'bg-muted text-muted-foreground' }
}

export function IdeasSection() {
  const { t } = useTranslation()
  const collapsed = useUIStore((s) => s.ideasSectionCollapsed)
  const toggle = useUIStore((s) => s.toggleIdeasSection)
  const filter = useUIStore((s) => s.sidebarFilter)
  const setFilter = useUIStore((s) => s.setSidebarFilter)
  const { ideas, loading, teamId, refetch } = useIdeasForTeam()
  const [createOpen, setCreateOpen] = React.useState(false)

  const handleClickIdea = (idea: IdeaRow) => {
    setFilter({ kind: 'idea', ideaId: idea.id, title: idea.title })
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
          <span>{t('sidebar.ideasSection', 'Ideas')}</span>
          {ideas.length > 0 && (
            <span className="font-mono font-normal normal-case tracking-normal text-faint/80">
              · {ideas.length}
            </span>
          )}
        </button>
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); setCreateOpen(true) }}
          className="rounded-md p-0.5 text-faint hover:bg-selected/60 hover:text-foreground"
          title={t('ideas.newIdea', 'New idea')}
          aria-label={t('ideas.newIdea', 'New idea')}
        >
          <Plus className="h-[11px] w-[11px]" />
        </button>
      </div>
      <CreateIdeaDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        teamId={teamId}
        onCreated={refetch}
      />
      {!collapsed && (
        <div className="flex flex-col">
          {loading && (
            <div className="px-[9px] py-1 text-[12px] text-faint">{t('ideas.loading', 'Loading ideas...')}</div>
          )}
          {!loading && ideas.length === 0 && (
            <div className="px-[9px] py-1 text-[12px] text-faint">{t('ideas.empty', 'No ideas yet')}</div>
          )}
          {ideas.map((idea) => {
            const active = filter.kind === 'idea' && filter.ideaId === idea.id
            const { label, tone } = ideaStatusLabel(idea.status)
            return (
              <button
                key={idea.id}
                type="button"
                onClick={() => handleClickIdea(idea)}
                className={cn(
                  // Direction B row: tight 5×9 padding, selected fill on active,
                  // no left bar (reserved for session list cards). AGENTS.md §2.
                  'flex w-full items-center gap-2 rounded-md px-[9px] py-[5px] text-left text-[12.5px] transition-colors',
                  active
                    ? 'bg-selected font-semibold text-foreground'
                    : 'text-ink-2 hover:bg-selected/60',
                )}
              >
                <span className="min-w-0 flex-1 truncate">{idea.title}</span>
                <span className={cn('shrink-0 rounded-full px-1.5 py-0.5 text-[9px] font-medium', tone)}>{label}</span>
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
