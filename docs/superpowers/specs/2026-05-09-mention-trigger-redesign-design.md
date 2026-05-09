# Mention Trigger Redesign — `@` for people/agents, `#` for resources

**Date:** 2026-05-09
**Branch / scope:** `v2/amuxd-architecture`, ChatPanel composer only
**Reference:** amux iOS `MentionsPopup` + `SessionComposer` behavior

## Background

In teamclaw-v2 ChatPanel today, `@` triggers two overlapping popovers — `FileMentionPopover` for files (active code path) and `MentionPopover` for contacts (rendered but never persisted: `mentionActorIds` is hardcoded `[]` at `ChatPanel.tsx:783` and `ActorChatInput.tsx:57`). The placeholder reads `输入 @ 引用文件...`, so users mentally model `@` as "reference a file" — diverging from amux iOS, where `@` mentions humans and agents and `mention_actor_ids` is the routing primitive amuxd uses for selective ACP `send_prompt` dispatch.

This spec swaps the triggers and wires the proto field that's been sitting empty.

## Goals

- `#` becomes the resource trigger; behavior identical to today's `@` resource popover (workspace files, fuzzy match, `[File: path]` serialization).
- `@` becomes the people/agent trigger; opens a unified popover sourced from `session_participants × actors` for the current session, with member and agent visually distinguished, mirroring amux iOS.
- Selecting a **member** inserts an inline `@DisplayName` chip in the composer text.
- Selecting an **agent** strips the `@query` from the text and adds the agent as a removable chip above the composer (does NOT appear in message text).
- On send, `SessionMessageEnvelope.mentionActorIds` is populated with the de-duplicated union of all mentioned member + agent IDs, and persisted to `messages.metadata.mention_actor_ids`.
- Scope: ChatPanel / ChatInputArea only. `ActorChatInput` (Phase 1 stub textarea) is untouched.

## Non-goals

- amuxd-side ACP routing on `mention_actor_ids` (Phase 2 work; daemon already subscribes and parses `IncomingMessage::TeamclawSessionLive` per `amux/daemon/src/mqtt/subscriber.rs:38-49`).
- Reverse rendering of mentioned actors in `MessageList` / `ActorMessageList` (e.g. highlighting `@DisplayName` in received messages). Phase 2 — would need a content parser.
- Migrating historical messages with `[File: path]` text from the old `@` flow. Left as-is.
- Multi-select in the popover (one selection per `@` invocation, like amux iOS).
- Any change to v2's `ActorChatInput`.

## Architecture

### Files touched (≈ 8)

| File | Change |
|---|---|
| `packages/app/src/packages/ai/prompt-input.tsx` (`checkMentionTrigger`, ~322-377) | Recognize both `@` and `#`; return `{ kind: 'resource' \| 'mention', query, range }` |
| `packages/app/src/packages/ai/prompt-input-insert-hooks.ts` (~189-229) | Add `createInsertMemberMention`; rename existing file-insert helper for clarity |
| `packages/app/src/components/chat/FileMentionPopover.tsx` | Header text → "Reference a file (#)"; remove the `@`-specific assumption (data-flow unchanged) |
| `packages/app/src/components/chat/MentionPopover.tsx` | New data source (`session_participants × actors`); render member/agent split; emit `onSelectMember(actor)` or `onSelectAgent(actor)` |
| `packages/app/src/components/chat/ChatInputArea.tsx` | Own `attachedAgents: AttachedAgent[]` state; render `<AgentChipBar />` above the composer |
| `packages/app/src/components/chat/AgentChipBar.tsx` *(new)* | Visual chip per attached agent + `×` remove button |
| `packages/app/src/components/chat/ChatPanel.tsx` (`send`, ~770-810) | Collect member chip IDs + attached agent IDs; populate `mentionActorIds`; persist `metadata.mention_actor_ids`; clear `attachedAgents` after send |
| `packages/app/src/packages/ai/editable-with-file-chips.tsx` (~72-170) | Add a second regex (`/@\{member:[0-9a-f-]{36}:[^}]+\}/`) to render member chips with `data-actor-id` |
| `packages/app/src/locales/{en,zh-CN}.json` | Update `chat.inputPlaceholderMention`; add `chat.mentionPopoverTitle`, `chat.resourcePopoverTitle`, `chat.mentionEmptyState` |

### Data flow

```
Type #         → Trigger { kind: 'resource' } → FileMentionPopover (workspace files)
                  → Select → insert `@{path}` chip text → editable-with-file-chips renders inline chip
                  → ChatPanel.send → text replaces `@{path}` → `[File: path]` (existing)

Type @         → Trigger { kind: 'mention' } → MentionPopover
                  → Query: SELECT actors.* FROM session_participants
                                              JOIN actors ON sp.actor_id = a.id
                                              WHERE session_id = $sid
                  → Render member section + agent section
                  → Select member → insert `@{member:UUID:DisplayName}` chip text
                                  → editable-with-file-chips renders inline chip with data-actor-id
                  → Select agent  → ChatInputArea.attachedAgents.add({ id, displayName })
                                  → query stripped from text, agent appears in AgentChipBar above

Send          → memberIds = querySelectorAll('[data-actor-id][data-mention-kind="member"]')
                agentIds  = attachedAgents.map(a => a.id)
                mentionActorIds = unique([...memberIds, ...agentIds])
                outgoing = inputValue
                            .replace(/@\{member:UUID:Name\}/g, '@Name')
                            .replace(/@\{path\}/g,             '[File: path]')
                Build SessionMessageEnvelope { message, mentionActorIds }
                MQTT publish + Supabase insert (with metadata.mention_actor_ids)
                Reset: input, attachedFiles, attachedAgents
```

## Data model

### Session participants query

```ts
const { data, error } = await supabase
  .from('session_participants')
  .select('actor_id, actors!inner(id, actor_type, display_name)')
  .eq('session_id', currentSessionId);
```

`actors.actor_type` is `'member' | 'agent'` (per `amux/amux-api/supabase/migrations/202604220002_core_schema.sql:9-17`). The `session_participants` table is at line 115. Backend table already exists in the shared Supabase project — no migration needed for this work.

### Cache strategy (in MentionPopover)

- Fetch on first open per session.
- Reuse for 30 seconds while popover is closed (covers rapid retrigger on typing); after 30s, refetch on next open.
- Invalidate on `currentSessionId` change.
- No realtime subscription — keep it simple; participant list changes infrequently in Phase 1.

### Chip text formats

| Kind | Token text in contenteditable | Serialized to `messages.content` |
|---|---|---|
| Resource (file) | `@{path}` *(unchanged from today)* | `[File: path]` |
| Member mention | `@{member:UUID:DisplayName}` | `@DisplayName` |
| Agent mention | *not in contenteditable* | *not in content* |

UUID is the canonical 36-char form (`[0-9a-f-]{36}`). DisplayName may contain spaces but no `}` (sanitize on insert if needed).

### `attachedAgents` state shape

```ts
type AttachedAgent = { id: string; displayName: string };
const [attachedAgents, setAttachedAgents] = useState<AttachedAgent[]>([]);
```

Owned by `ChatInputArea` (mirroring how it already owns `attachedFiles`). Deduped by id on add. Cleared on send and on session change. Not persisted across reloads.

`ChatInputArea` exposes the list to `ChatPanel.send` by extending its existing submit callback payload to include `attachedAgents` alongside `text` and `attachedFiles`. `MentionPopover.onSelectAgent` calls a new `onAttachAgent(actor)` prop on `ChatInputArea`, which routes to the local `setAttachedAgents`.

## Trigger + state machine

### `checkMentionTrigger` extension

Trigger fires when **all** of:

- Cursor's preceding character is `@` or `#`.
- The character before that is start-of-line, whitespace, or newline (skips `email@` patterns).
- Cursor isn't inside a `contenteditable=false` chip (`closest('[contenteditable=false]')` returns null).

Return type:

```ts
type Trigger =
  | null
  | { kind: 'resource'; query: string; range: Range }
  | { kind: 'mention';  query: string; range: Range };
```

### Popover mutual exclusion

- One popover open at most.
- Switching trigger char (e.g. delete `@`, type `#`) closes the old popover before opening the new one.
- Spacebar closes the popover (queries do not contain spaces).

### Keyboard

| Key | Behavior |
|---|---|
| `↑` / `↓` | Move highlight |
| `Enter` / `Tab` | Confirm selection (insert chip / attach agent) |
| `Esc` | Close popover; `@` or `#` plus the typed query stays as plain text |
| `Backspace` (query empty) | Close popover; subsequent backspaces delete normally |
| `Backspace` (over inline chip) | Delete the entire chip (existing chip behavior) |

### Empty / error states

- Query returns 0 participants → popover renders `chat.mentionEmptyState`; Enter does nothing.
- Query has only members or only agents → render only the populated section.
- Query fails (network / RLS) → popover renders error message + retry button; logs to console; never blocks typing.

### Repeat mention

Selecting an agent already in `attachedAgents` is a no-op (still strips `@query` from text). Selecting the same member twice inserts two chips — that's fine; `mentionActorIds` is deduped on send.

### Session switch

`useEffect` on `currentSessionId`: clear `attachedAgents`, drop participant cache, close any open popover.

## Send / Wire format

### `ChatPanel.send` changes (around lines 685-810)

```ts
// 1. Collect member mention IDs from inline chips
const memberIds = Array.from(
  inputDiv.querySelectorAll('[data-actor-id][data-mention-kind="member"]')
).map(el => el.getAttribute('data-actor-id')!);

// 2. Collect agent mention IDs from ChatInputArea-owned state
const agentIds = attachedAgents.map(a => a.id);

// 3. De-dup
const mentionActorIds = Array.from(new Set([...memberIds, ...agentIds]));

// 4. Serialize text (extend existing replacement chain)
const outgoing = inputValue
  .replace(/@\{member:[0-9a-f-]{36}:([^}]+)\}/g, '@$1')   // NEW
  .replace(/@\{([^:}]+\/[^}]+)\}/g, '[File: $1]');         // EXISTING (file paths)

// 5. Populate proto envelope
const sessionMsg = createMessage(SessionMessageEnvelopeSchema, {
  message,
  mentionActorIds,   // was always []
});

// 6. Persist with metadata
await supabase.from('messages').insert({
  id: messageId,
  team_id, session_id, sender_actor_id,
  kind: 'text',
  content: outgoing,
  metadata: { mention_actor_ids: mentionActorIds },   // NEW
});

// 7. Reset
setAttachedAgents([]);
```

Order of regex replacement matters: replace member chip token before file chip token, since the member token also starts with `@{` and could otherwise be partially eaten by the file regex. The file regex specifically requires a `/` (path separator) so they're effectively disjoint, but the explicit order documents intent.

### Message rendering (out of scope, noted)

`MessageList` / `ActorMessageList` continue to render `messages.content` verbatim. `@DisplayName` and `[File: path]` appear as plain text. Reverse rendering (clickable chips, member highlight) lands in Phase 2.

### amuxd interop

amuxd's `subscriber.rs:38-49` already routes `amux/{team}/session/{id}/live` payloads to `IncomingMessage::TeamclawSessionLive`. The proto already has `mention_actor_ids` (per amux's vendored `amux.proto` + `teamclaw.proto`). After this change, amuxd starts receiving non-empty mention lists. Phase 2 (ACP `start_agent` / `send_prompt`) will consume them; until then amuxd persists them with the message but does not act.

## Tests

| File | What's covered |
|---|---|
| `packages/ai/__tests__/prompt-input.test.tsx` | `checkMentionTrigger` returns correct kind for `@` and `#`; `email@example` does not trigger; chip-internal triggers don't fire |
| `packages/ai/__tests__/editable-with-file-chips.test.tsx` | Member chip token renders as `data-actor-id`-bearing span; Backspace deletes whole chip |
| `components/chat/__tests__/MentionPopover.test.tsx` *(new)* | Mocked supabase: member section, agent section, icons, ordering; selecting member fires `onSelectMember(actor)`, selecting agent fires `onSelectAgent(actor)`; empty result renders empty state; failed query renders retry |
| `components/chat/__tests__/ChatPanel-submission.test.tsx` *(extend)* | Composer with 1 member chip + 1 attached agent: `mentionActorIds` is deduped union; `messages.insert` `metadata.mention_actor_ids` matches; outgoing content has `@DisplayName` inline and no agent reference; send clears `attachedAgents` |

**Out of scope for tests:** end-to-end browser test (the v2 dev environment is unstable when multiple sessions are active; covered indirectly by unit tests). amuxd-side ACP routing tests live in the daemon repo, Phase 2.

## i18n

| Key | zh-CN | en |
|---|---|---|
| `chat.inputPlaceholderMention` *(modify)* | 输入 @ 提及人或 agent，# 引用文件... | Mention with @, reference files with #... |
| `chat.mentionPopoverTitle` *(new)* | 提及人或 agent | Mention people or agents |
| `chat.resourcePopoverTitle` *(new)* | 引用文件 | Reference a file |
| `chat.mentionEmptyState` *(new)* | 当前会话还没有可 @ 的人或 agent | No one to mention in this session yet |

## Rollback

A `VITE_MENTION_REDESIGN` env flag (default `true` once landed) gates the new behavior in `prompt-input.tsx`. If a regression slips, flip the flag in `.env.development.local` / build config to fall back to the old single-`@`-for-files behavior without redeploying.

## Open questions

None at spec time. All routing and rendering follow-ups are explicitly Phase 2.
