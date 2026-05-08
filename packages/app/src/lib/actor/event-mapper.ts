import type { ActorEvent } from "./types";

export interface EnvelopeJson {
  id: string;
  timestamp: number;
  payload: { case: string; value: Record<string, unknown> };
}

export function envelopeJsonToActorEvent(env: EnvelopeJson): ActorEvent | null {
  const ts = Math.round(env.timestamp * 1000);
  switch (env.payload.case) {
    case "chatMessage": {
      const v = env.payload.value as { actorId: string; text: string; mentionActorIds?: string[] };
      return {
        kind: "chat_message",
        actorId: v.actorId,
        timestampMs: ts,
        text: v.text,
        mentionActorIds: v.mentionActorIds ?? [],
      };
    }
    case "actorJoin": {
      const v = env.payload.value as { actor: { actorId: string; actorType: "human" | "agent"; displayName: string; avatarUrl?: string; deviceId?: string } };
      return { kind: "actor_join", actor: v.actor, timestampMs: ts };
    }
    case "actorLeave": {
      const v = env.payload.value as { actorId: string };
      return { kind: "actor_leave", actorId: v.actorId, timestampMs: ts };
    }
    default:
      return null;
  }
}

export function actorEventToEnvelopeJson(ev: ActorEvent): EnvelopeJson {
  const id = crypto.randomUUID();
  const timestamp = ev.timestampMs / 1000;
  switch (ev.kind) {
    case "chat_message":
      return {
        id,
        timestamp,
        payload: {
          case: "chatMessage",
          value: { actorId: ev.actorId, text: ev.text, mentionActorIds: ev.mentionActorIds },
        },
      };
    default:
      throw new Error(`actorEventToEnvelopeJson: cannot serialize kind=${ev.kind} (out of scope for Phase 1)`);
  }
}
