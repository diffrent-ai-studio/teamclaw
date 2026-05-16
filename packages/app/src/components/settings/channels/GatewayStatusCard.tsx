/**
 * GatewayStatusCard - Common gateway status display with expand/collapse,
 * start/stop/restart buttons, and toggle switch.
 * Used by all channel settings.
 */
import * as React from 'react'
import { useState, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import {
  Loader2,
  Play,
  Square,
  RefreshCw,
  ChevronDown,
  ChevronRight,
  BookOpen,
  AlertTriangle,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { SettingCard, ToggleSwitch, StatusBadge } from './shared'
import { listChannels, AmuxdUnreachableError } from '@/lib/amuxd-channels'

export interface GatewayStatusCardProps {
  /** The channel icon component */
  icon: React.ReactNode
  /** The gateway display name (e.g., "Discord Gateway") */
  title: string
  /** Gateway status */
  status: 'disconnected' | 'connecting' | 'connected' | 'error'
  /** Optional status detail line (e.g., "Connected as @bot") */
  statusDetail?: React.ReactNode
  /** Optional error message */
  errorMessage?: string
  /** Whether the panel is expanded */
  expanded: boolean
  /** Toggle expanded state */
  onToggleExpanded: () => void
  /** Whether the channel is enabled */
  enabled: boolean
  /** Toggle enabled state */
  onToggleEnabled: (enabled: boolean) => void
  /** Whether the store is loading */
  isLoading: boolean
  /** Whether gateway is connecting */
  isConnecting: boolean
  /** Whether gateway is running (connected or connecting) */
  isRunning: boolean
  /** Whether there are unsaved changes that need a restart */
  hasChanges: boolean
  /** Handle start/stop */
  onStartStop: () => void
  /** Handle restart (stop + save + start) */
  onRestart: () => void
  /** Whether start should be disabled (e.g., missing credentials) */
  startDisabled?: boolean
  /** Optional: show setup wizard button */
  onOpenWizard?: () => void
  /** Collapsible content */
  children?: React.ReactNode
  /**
   * Override: explicitly signal that amuxd is unreachable (e.g. from store
   * state). When omitted the card probes `listChannels()` itself on mount.
   */
  amuxdUnreachable?: boolean
}

export function GatewayStatusCard({
  icon,
  title,
  status,
  statusDetail,
  errorMessage,
  expanded,
  onToggleExpanded,
  enabled,
  onToggleEnabled,
  isLoading,
  isConnecting,
  isRunning,
  hasChanges,
  onStartStop,
  onRestart,
  startDisabled,
  onOpenWizard,
  children,
  amuxdUnreachable: amuxdUnreachableProp,
}: GatewayStatusCardProps) {
  const { t } = useTranslation()

  // Track amuxd reachability. If the parent already knows (via the store's
  // error state), it can pass `amuxdUnreachable` directly and skip the probe.
  const [amuxdUnreachableLocal, setAmuxdUnreachableLocal] = useState(false)

  useEffect(() => {
    // Only probe when the parent hasn't supplied an explicit value.
    if (amuxdUnreachableProp !== undefined) return

    let cancelled = false
    listChannels()
      .then(() => {
        if (!cancelled) setAmuxdUnreachableLocal(false)
      })
      .catch((err) => {
        if (!cancelled && err instanceof AmuxdUnreachableError) {
          setAmuxdUnreachableLocal(true)
        }
      })
    return () => {
      cancelled = true
    }
  }, [amuxdUnreachableProp])

  const amuxdUnreachable =
    amuxdUnreachableProp !== undefined ? amuxdUnreachableProp : amuxdUnreachableLocal

  return (
    <SettingCard>
      {/* amuxd unreachable banner */}
      {amuxdUnreachable && (
        <div
          role="alert"
          className="flex items-start gap-3 rounded-md border border-destructive/50 bg-destructive/10 px-4 py-3 mb-4 text-sm text-destructive"
        >
          <AlertTriangle className="h-4 w-4 mt-0.5 flex-shrink-0" />
          <div>
            <p className="font-semibold">{t('settings.channels.amuxdNotRunning', 'amuxd not running')}</p>
            <p className="mt-0.5 text-destructive/80">
              {t(
                'settings.channels.amuxdNotRunningDesc',
                'Channel features require amuxd. Start it with',
              )}{' '}
              <code className="rounded bg-destructive/20 px-1 font-mono text-xs">pnpm daemon:run</code>{' '}
              {t('settings.channels.amuxdNotRunningOrInstall', 'or install it as a service.')}
            </p>
          </div>
        </div>
      )}
      {/* Header Row - always visible */}
      <div className="flex items-center justify-between">
        <button
          onClick={onToggleExpanded}
          className="flex items-center gap-4 flex-1 text-left"
        >
          {icon}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-medium">{title}</span>
              <StatusBadge status={status} />
            </div>
            {statusDetail}
            {errorMessage && (
              <p className="text-xs text-red-500">{errorMessage}</p>
            )}
          </div>
          {expanded ? (
            <ChevronDown className="h-4 w-4 text-muted-foreground flex-shrink-0" />
          ) : (
            <ChevronRight className="h-4 w-4 text-muted-foreground flex-shrink-0" />
          )}
        </button>
        <div className="flex items-center gap-2 ml-3">
          {onOpenWizard && (
            <Button
              variant="ghost"
              size="sm"
              onClick={onOpenWizard}
              className="h-8 w-8 p-0"
              title={t('settings.channels.startSetup', 'Start Setup')}
            >
              <BookOpen className="h-4 w-4 text-muted-foreground" />
            </Button>
          )}
          <ToggleSwitch
            enabled={enabled}
            onChange={onToggleEnabled}
            disabled={isLoading}
          />
          {isRunning && hasChanges ? (
            <Button
              variant="default"
              size="sm"
              onClick={onRestart}
              disabled={isLoading || isConnecting}
              className="gap-2"
            >
              {isLoading || isConnecting ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <>
                  <RefreshCw className="h-4 w-4" />
                  {t('settings.channels.restart', 'Restart')}
                </>
              )}
            </Button>
          ) : (
            <Button
              variant={isRunning ? 'destructive' : 'default'}
              size="sm"
              onClick={onStartStop}
              disabled={isLoading || isConnecting || (!isRunning && (startDisabled || !enabled))}
              className="gap-2"
            >
              {isLoading || isConnecting ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : isRunning ? (
                <>
                  <Square className="h-4 w-4" />
                  {t('settings.channels.stop', 'Stop')}
                </>
              ) : (
                <>
                  <Play className="h-4 w-4" />
                  {t('settings.channels.start', 'Start')}
                </>
              )}
            </Button>
          )}
        </div>
      </div>

      {/* Collapsible Content */}
      {expanded && children && (
        <div className="mt-5 pt-5 border-t space-y-5">
          {children}
        </div>
      )}
    </SettingCard>
  )
}
