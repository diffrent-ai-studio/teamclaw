import * as React from 'react'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Loader2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { supabase } from '@/lib/supabase-client'

interface CreateIdeaDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  teamId: string | null
  /** Called after a successful create so callers can refetch the ideas list. */
  onCreated?: () => void
}

export function CreateIdeaDialog({ open, onOpenChange, teamId, onCreated }: CreateIdeaDialogProps) {
  const { t } = useTranslation()
  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [submitting, setSubmitting] = React.useState(false)

  React.useEffect(() => {
    if (!open) {
      setTitle('')
      setDescription('')
      setSubmitting(false)
    }
  }, [open])

  const trimmed = title.trim()
  const canSubmit = !!trimmed && !!teamId && !submitting

  const submit = async () => {
    if (!canSubmit) return
    setSubmitting(true)
    try {
      const { error } = await supabase.rpc('create_idea', {
        team_id: teamId,
        workspace_id: '',
        title: trimmed,
        description: description.trim() || null,
      })
      if (error) {
        toast.error(t('ideas.createFailed', 'Failed to create idea: {{msg}}', { msg: error.message }))
        return
      }
      toast.success(t('ideas.created', 'Idea created'))
      onCreated?.()
      onOpenChange(false)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      toast.error(t('ideas.createFailed', 'Failed to create idea: {{msg}}', { msg }))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('ideas.newIdea', 'New idea')}</DialogTitle>
          <DialogDescription>
            {t('ideas.newIdeaDescription', 'Capture an idea, problem, or proposal for the team.')}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-muted-foreground">
              {t('ideas.titleLabel', 'Title')}
            </label>
            <Input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={t('ideas.titlePlaceholder', 'Idea title')}
              disabled={submitting}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey && (e.metaKey || e.ctrlKey)) {
                  e.preventDefault()
                  void submit()
                }
              }}
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-muted-foreground">
              {t('ideas.descriptionLabel', 'Description')}
            </label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t('ideas.descriptionPlaceholder', "What's the constraint, what's the win?")}
              disabled={submitting}
              rows={4}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={submitting}>
            {t('common.cancel', 'Cancel')}
          </Button>
          <Button onClick={() => void submit()} disabled={!canSubmit}>
            {submitting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {t('ideas.createButton', 'Create')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
