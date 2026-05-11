import { supabase } from '@/lib/supabase-client'
import { runtimeStart } from '@/lib/teamclaw-rpc'
import { AgentType } from '@/lib/proto/amux_pb'

export interface CreateSessionArgs {
  teamId: string
  creatorActorId: string
  title: string
  /** Actor IDs to add as participants alongside the creator. */
  additionalActorIds: string[]
  /** Subset of additionalActorIds that are AGENT-type (will receive runtimeStart). */
  agentActorIds: string[]
}

export interface CreateSessionResult {
  sessionId: string
  /** Map of agentActorId -> runtimeStart outcome (true if accepted). */
  runtimeStartOutcomes: Record<string, { accepted: boolean; runtimeId?: string; reason?: string }>
}

export async function createSessionWithParticipants(args: CreateSessionArgs): Promise<CreateSessionResult> {
  const sessionId = crypto.randomUUID()
  const trimmedTitle = (args.title.split('\n')[0] || args.title).trim().slice(0, 80) || 'New chat'

  // 1. INSERT sessions
  const { error: sessionErr } = await supabase
    .from('sessions')
    .insert({
      id: sessionId,
      team_id: args.teamId,
      created_by_actor_id: args.creatorActorId,
      mode: 'collab',
      title: trimmedTitle,
    })
  if (sessionErr) throw new Error(`Failed to create session: ${sessionErr.message}`)

  // 2. INSERT session_participants (self + additional)
  const participantActorIds = Array.from(new Set([args.creatorActorId, ...args.additionalActorIds]))
  if (participantActorIds.length > 0) {
    const rows = participantActorIds.map(actorId => ({ session_id: sessionId, actor_id: actorId }))
    const { error: partErr } = await supabase.from('session_participants').insert(rows)
    if (partErr) throw new Error(`Failed to add participants: ${partErr.message}`)
  }

  // 3. For each agent, call runtimeStart. Don't await sequentially — fan out + collect.
  const runtimeStartOutcomes: CreateSessionResult['runtimeStartOutcomes'] = {}

  // Look up each agent's prior workspace from agent_runtimes history (one query, fanned by id)
  const priorByAgent = new Map<string, { workspace_id: string | null }>()
  if (args.agentActorIds.length > 0) {
    const { data: priorRows } = await supabase
      .from('agent_runtimes')
      .select('agent_id, workspace_id, updated_at')
      .in('agent_id', args.agentActorIds)
      .eq('team_id', args.teamId)
      .order('updated_at', { ascending: false })
    // Take the most-recent row per agent
    for (const r of priorRows ?? []) {
      if (!priorByAgent.has(r.agent_id)) {
        priorByAgent.set(r.agent_id, { workspace_id: r.workspace_id })
      }
    }
  }

  await Promise.all(args.agentActorIds.map(async (agentActorId) => {
    const prior = priorByAgent.get(agentActorId)
    try {
      // For now, assume daemon device_id == agent actor_id (current
      // amuxd convention: one daemon = one actor, MQTT username = actor_id
      // and is used as device_id in topic routing). If iOS later needs to
      // disambiguate across multi-daemon teams, look up via a separate
      // (actor -> deviceId) table or RPC.
      const result = await runtimeStart({
        targetDeviceId: agentActorId,
        workspaceId: prior?.workspace_id ?? '',
        worktree: '',
        sessionId,
        agentType: AgentType.CLAUDE_CODE,
        initialPrompt: '',
      })
      runtimeStartOutcomes[agentActorId] = {
        accepted: result.accepted,
        runtimeId: result.runtimeId,
        reason: result.rejectedReason || undefined,
      }
      if (!result.accepted) {
        console.error('[session-create] runtimeStart rejected', {
          agentActorId,
          reason: result.rejectedReason,
        })
      } else {
        console.info('[session-create] runtimeStart accepted', {
          agentActorId,
          runtimeId: result.runtimeId,
        })
      }
    } catch (e) {
      const reason = e instanceof Error ? e.message : String(e)
      runtimeStartOutcomes[agentActorId] = { accepted: false, reason }
      console.error('[session-create] runtimeStart threw', {
        agentActorId,
        reason,
      })
    }
  }))

  return { sessionId, runtimeStartOutcomes }
}
