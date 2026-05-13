import { useState } from "react";
import { create as createMessage, toBinary } from "@bufbuild/protobuf";
import {
  MessageSchema,
  SessionMessageEnvelopeSchema,
  LiveEventEnvelopeSchema,
  MessageKind,
} from "@/lib/proto/teamclaw_pb";
import { mqttPublish } from "@/lib/mqtt-bridge";
import { supabase } from "@/lib/supabase-client";
import { useAuthStore } from "@/stores/auth-store";
import { useSessionStore } from "@/stores/session-store";
import { useSessionListStore } from "@/stores/session-list-store";

export function ActorChatInput() {
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const sid = useSessionStore((s) => s.currentSessionId);
  const session = useAuthStore((s) => s.session);
  const sessionRow = useSessionListStore((s) => s.rows.find((r) => r.id === sid));

  const send = async () => {
    if (!session || !sid || !sessionRow || !text.trim()) return;
    setSending(true);
    setError(null);
    try {
      // Resolve sender actor_id: look up the member row for this user in this team.
      // For Phase 1, use a heuristic — query members by user_id, find the actor in current team.
      const { data: actorRows, error: actorErr } = await supabase
        .from("actors")
        .select("id, team_id")
        .eq("user_id", session.user.id);
      if (actorErr) throw actorErr;
      const matching = (actorRows ?? []).find((a) => a.team_id === sessionRow.team_id);
      if (!matching) {
        throw new Error(`No actor found for user in team ${sessionRow.team_id}`);
      }
      const senderActorId = matching.id as string;

      const messageId = crypto.randomUUID();
      const createdAt = BigInt(Math.floor(Date.now() / 1000));
      const content = text;

      // Build proto chain
      const message = createMessage(MessageSchema, {
        messageId,
        sessionId: sid,
        senderActorId,
        kind: MessageKind.TEXT,
        content,
        createdAt,
      });
      const sessionMsg = createMessage(SessionMessageEnvelopeSchema, {
        message,
        mentionActorIds: [],
      });
      const live = createMessage(LiveEventEnvelopeSchema, {
        eventId: crypto.randomUUID(),
        eventType: "message.created",
        sessionId: sid,
        actorId: senderActorId,
        sentAt: createdAt,
        body: toBinary(SessionMessageEnvelopeSchema, sessionMsg),
      });

      const topic = `amux/${sessionRow.team_id}/session/${sid}/live`;
      await mqttPublish(topic, toBinary(LiveEventEnvelopeSchema, live), false);

      // Supabase persistence — DB id matches our messageId
      const { error: insErr } = await supabase.from("messages").insert({
        id: messageId,
        team_id: sessionRow.team_id,
        session_id: sid,
        sender_actor_id: senderActorId,
        kind: "text",
        content,
        // created_at default
      });
      if (insErr) throw insErr;

      // Optimistic local append — broker doesn't echo back to publisher and
      // single-window scope means we won't get a remote echo either.
      useSessionStore.getState().appendMessage(sid, message);

      setText("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSending(false);
    }
  };

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send();
    }
  };

  return (
    <div className="border-t bg-background p-2">
      {error && <div className="mb-2 text-xs text-red-600">{error}</div>}
      <textarea
        className="w-full resize-none rounded border bg-background px-3 py-2 text-sm"
        rows={2}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        disabled={sending}
        placeholder={sid ? "Send a message" : "Pick a session first"}
      />
    </div>
  );
}
