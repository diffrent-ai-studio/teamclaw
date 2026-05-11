import * as React from "react";
import { AlertCircle, CheckCircle2, Circle, Clock3, Loader2, ShieldQuestion, Sparkles } from "lucide-react";
import type { AgentStreamEntry, StreamingTodoItem } from "@/stores/v2-streaming-store";
import { supabase } from "@/lib/supabase-client";
import { cn } from "@/lib/utils";
import { Message, MessageContent, MessageResponse } from "@/packages/ai/message";
import { ThinkingBlock } from "./ThinkingBlock";
import { ToolCallCard } from "./ToolCallCard";

// Module-level cache of actor_id -> display_name. The MQTT envelope only
// carries the actor_id; we resolve the human-readable name from
// public.actor_directory on first sighting. Cache survives component
// re-mounts and is shared across all StreamingAgentBubble instances.
const actorDisplayNameCache = new Map<string, string>();
const inflightLookups = new Map<string, Promise<string | null>>();

async function lookupActorDisplayName(actorId: string): Promise<string | null> {
  const cached = actorDisplayNameCache.get(actorId);
  if (cached) return cached;
  const inflight = inflightLookups.get(actorId);
  if (inflight) return inflight;

  const p = (async () => {
    const { data, error } = await supabase
      .from("actor_directory")
      .select("display_name")
      .eq("id", actorId)
      .maybeSingle();
    if (error || !data) return null;
    const name = (data as { display_name?: string }).display_name ?? null;
    if (name) actorDisplayNameCache.set(actorId, name);
    return name;
  })();
  inflightLookups.set(actorId, p);
  try {
    return await p;
  } finally {
    inflightLookups.delete(actorId);
  }
}

function useActorDisplayName(actorId: string): string {
  const [name, setName] = React.useState<string | null>(
    () => actorDisplayNameCache.get(actorId) ?? null,
  );
  React.useEffect(() => {
    if (name) return;
    let cancelled = false;
    void lookupActorDisplayName(actorId).then((resolved) => {
      if (!cancelled && resolved) setName(resolved);
    });
    return () => {
      cancelled = true;
    };
  }, [actorId, name]);
  return name ?? actorId.slice(0, 8);
}

function TodoStatusIcon({ status }: { status: StreamingTodoItem["status"] }) {
  const cls = "h-3.5 w-3.5 shrink-0";
  if (status === "completed") return <CheckCircle2 className={cn(cls, "text-emerald-500")} />;
  if (status === "in_progress") return <Clock3 className={cn(cls, "text-blue-500")} />;
  return <Circle className={cn(cls, "text-muted-foreground")} />;
}

function InlineTodos({ todos }: { todos: StreamingTodoItem[] }) {
  if (todos.length === 0) return null;
  return (
    <div className="my-1.5 rounded-md border border-border/50 bg-muted/20 p-2.5">
      <div className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground/80 mb-1.5">
        Todos
      </div>
      <ul className="space-y-1">
        {todos.map((t, i) => (
          <li key={i} className="flex items-start gap-2 text-xs">
            <TodoStatusIcon status={t.status} />
            <span className={cn(
              "min-w-0 flex-1",
              t.status === "completed" && "line-through text-muted-foreground",
            )}>{t.content}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function PermissionRequestCard({ entry }: { entry: AgentStreamEntry }) {
  const pr = entry.pendingPermission;
  if (!pr) return null;
  return (
    <div className="my-1.5 rounded-md border border-amber-500/40 bg-amber-500/10 p-2.5 text-xs">
      <div className="flex items-center gap-1.5 text-amber-700 dark:text-amber-300 font-medium mb-1">
        <ShieldQuestion className="h-3.5 w-3.5" />
        Awaiting permission for {pr.toolName || "tool call"}
      </div>
      {pr.description && (
        <div className="text-muted-foreground">{pr.description}</div>
      )}
    </div>
  );
}

function ErrorCard({ message, details }: { message: string; details: string }) {
  return (
    <div className="my-1.5 rounded-md border border-destructive/40 bg-destructive/10 p-2.5 text-xs">
      <div className="flex items-center gap-1.5 text-destructive font-medium mb-1">
        <AlertCircle className="h-3.5 w-3.5" />
        {message}
      </div>
      {details && (
        <pre className="whitespace-pre-wrap font-mono text-[11px] text-muted-foreground max-h-32 overflow-y-auto">
          {details}
        </pre>
      )}
    </div>
  );
}

export function StreamingAgentBubble({ entry }: { entry: AgentStreamEntry }) {
  const displayName = useActorDisplayName(entry.actorId);
  const hasOutput = entry.outputText.length > 0;
  const hasThinking = entry.thinkingText.length > 0;
  const hasToolCalls = entry.toolCalls.length > 0;
  const hasTodos = entry.todos.length > 0;
  const hasPermission = !!entry.pendingPermission;
  const hasError = !!entry.errorMessage;
  const isStreaming = entry.active;

  return (
    <Message from="assistant" className="px-4 py-3">
      <div className="flex w-full items-start gap-2">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
          <Sparkles className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-sm font-medium">{displayName}</span>
            {isStreaming && <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />}
          </div>

          {hasThinking && (
            <ThinkingBlock content={entry.thinkingText} isStreaming={isStreaming} />
          )}

          {hasToolCalls && (
            <div className="space-y-1">
              {entry.toolCalls.map((tc) => (
                <ToolCallCard key={tc.id} toolCall={tc} />
              ))}
            </div>
          )}

          {hasTodos && <InlineTodos todos={entry.todos} />}

          {hasPermission && <PermissionRequestCard entry={entry} />}

          {hasOutput && (
            <MessageContent>
              <MessageResponse>{entry.outputText}</MessageResponse>
            </MessageContent>
          )}

          {hasError && (
            <ErrorCard message={entry.errorMessage!} details={entry.errorDetails ?? ""} />
          )}

          {!hasOutput && !hasThinking && !hasToolCalls && !hasTodos && !hasPermission && !hasError && (
            <div className="text-sm text-muted-foreground italic">Working...</div>
          )}
        </div>
      </div>
    </Message>
  );
}
