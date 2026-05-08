# TeamClaw v2 Architecture: amuxd-based Agent Dispatch

**Date:** 2026-05-08
**Status:** Approved (pending implementation plan)
**Target version:** v2.0.0

## Overview

Replace the tightly coupled OpenCode sidecar with an architecture where TeamClaw is a thin client, agents are independent `amuxd` daemon processes, and all communication flows over a single MQTT topic per session using the actor model. Sessions and identities move to Supabase; the existing FC backend shrinks to managed-git, Pro distribution, and a future AI proxy.

## Goals

- Decouple TeamClaw from the OpenCode binary: no sidecar in `src-tauri/binaries/`, no `OpenCodeClient` references in stores
- Unify human and agent participants under a single `Actor` model so multi-person × multi-agent collaboration becomes a topology in one shared topic, not a special case
- Adopt `amuxd` (`/Volumes/openbeta/workspace/amux/daemon`) as the canonical agent host — TeamClaw drives ACP through the daemon over MQTT, never spawns an agent process itself
- Move session list, identity, and team membership to Supabase + EMQX; let Aliyun FC serve only the things it does well (managed-git, Pro distribution, future AI proxy)
- Keep the things users see: ChatPanel layout, Tiptap / CodeMirror editors, workspace picker, OSS / iroh team sync
- Ship as v2.0.0 via a `git worktree` so v1 stays patchable on `main`

This spec covers the **TeamClaw desktop client only**. Other clients (e.g., web) are out of scope.

## Non-Goals (v1)

- **Cloud-hosted agents.** Agents run wherever a daemon runs. No serverless agent execution (e.g., FC-hosted Claude Code) in v1.
- **Lease-based host migration.** Daemon offline = agent offline. No automatic host hand-off when a daemon disconnects.
- **Cross-machine workspace path translation.** A daemon receives a `workspace_path` and either has it on its filesystem or rejects the invite. No NFS/sync indirection.
- **FC AI proxy (Q7-B path).** Daemons use BYOK (user's own Anthropic key in `~/.config/amux/keys.toml`) in v1. The FC `/ai/*` proxy endpoints are reserved for v2.
- **Multi-daemon per machine.** One daemon = one agent identity. v1 does not support running two amuxd processes on a single host.
- **Windows one-click installer.** Windows users follow the manual install path; the auto-installer covers Mac and Linux only in v1.
- **Sub-task delegation between agents.** "Agent A delegates to Agent B" is a v2+ feature; the actor model leaves protocol space for it but v1 ships with chat-only and direct user→agent invocation.
- **In-place v1 → v2 data migration.** v2 ships as a clean break; v1 chat history is not auto-imported.

## Decision Log

| ID | Question | Decision |
|---|---|---|
| Q1 | Where does `amuxd` live in the architecture? | Daemon is independent — not bundled in TeamClaw. TeamClaw is a human client; the daemon is an agent host. |
| Q2 | What does "multi-person × multi-agent collab" mean concretely? | Unified actor model (`human` / `agent`); single topic `session/{id}/live` per session. |
| Q3 | How do we reconcile teamclaw's FC stack with amuxd's Supabase + EMQX stack? | Adopt Supabase + EMQX wholesale. FC shrinks to managed-git, Pro distribution, future AI proxy. |
| Q4 | Where does the agent process actually run in a multi-actor session? | Agent runs wherever its daemon runs. Daemon offline ⇒ agent offline. No host migration. |
| Q5 | How does workspace context flow? | Single-machine assumption. TeamClaw passes `workspace_path` in the `AgentInvoke` envelope; daemon validates against its filesystem. |
| Q6 | Onboarding path for first-time users? | macOS / Linux: TeamClaw bundles a one-click installer that fetches the `amuxd` binary, registers it as a launchd / systemd user service, and pairs it with the user's Supabase identity. Windows: manual install (download + `amuxd init` + Task Scheduler) until amuxd Windows is verified. |
| Q7 | Who pays / authenticates when the daemon spawns Claude Code? | v1: BYOK — user provides their own Anthropic key during `amuxd init`. v2: optional FC AI proxy path with Supabase-JWT auth. |
| Q8 | How do we sequence the migration from current state? | Big-bang switch via `git worktree`. v1 frozen on `main` for patches; v2 develops on `v2/amuxd-architecture` branch. v2.0 is a major version bump. No in-place data migration. |
| — | Where does the MQTT client live? | Rust side (`rumqttc`, same as amuxd). Frontend exposes a thin TS bridge over Tauri commands and events. Protobuf decoding also happens in Rust. |

---

## Section 1 — High-Level Architecture

### 1.1 Topology

```
┌─────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│  teamclaw       │         │  Supabase        │         │  amuxd daemon    │
│  (human client) │◄────────┤  (auth + DB)     ├────────►│  (agent host)    │
│                 │         │                  │         │                  │
│ • ChatPanel UI  │         │ • users          │         │ • ACP subprocess │
│ • Tiptap/CM     │         │ • sessions       │         │   (Claude Code)  │
│ • workspace     │         │ • actors         │         │ • workspace cwd  │
│   picker        │         │ • agent_runtimes │         │ • BYOK API key   │
└────────┬────────┘         └──────────────────┘         └────────┬─────────┘
         │                                                        │
         │              ┌────────────────────┐                    │
         │              │  EMQX MQTT broker  │                    │
         └─────────────►│                    │◄───────────────────┘
                        │  topic:            │
                        │  session/{id}/live │
                        └────────────────────┘
```

### 1.2 Core Propositions

1. **Actor is a first-class concept.** Supabase `actors` table holds both human and agent records. Each row carries `actor_id`, `actor_type` (`human` / `agent`), `display_name`, and `device_id` (agent only). The set of actors in a session lives in `session_actors`.

2. **There is no sidecar.** `src-tauri/binaries/opencode-*` and `src-tauri/src/commands/opencode.rs` are removed. The Tauri backend is a Supabase / MQTT client plus filesystem operations and a daemon installer (Mac / Linux only).

3. **The daemon is an independent process.** On Mac and Linux the TeamClaw installer wires it to launchd or systemd-user. On Windows users install it manually. A daemon is bound to a host machine; if the daemon is offline, the agent is offline — exactly the same failure mode as a human participant going offline.

4. **The session bus is one MQTT topic.** Each session has a single `session/{id}/live` topic. Every actor — human and agent alike — subscribes and publishes. Messages are Protobuf `Envelope` records (extending amuxd's `amux.proto`). Payload variants include `ChatMessage`, `AgentInvoke`, `ActorJoin` / `ActorLeave`, `AcpThinking`, `AcpOutput`, `AcpToolUse`, `AcpToolResult`, `AcpPermissionRequest` / `AcpPermissionGrant` / `AcpPermissionDeny`, `AcpAvailableCommands`, `AcpStatusChange`, `AcpError`.

5. **Workspace flows through ACP arguments, not over MQTT topics.** When a TeamClaw user invites a local agent into a session, the `AgentInvoke` envelope carries `workspace_path` as a payload field. The daemon calls ACP's `NewSessionRequest::new(PathBuf)` with that path. A remote daemon receiving a path it cannot `stat` rejects the invite with `AcpError{code: WORKSPACE_NOT_AVAILABLE_HERE}`. Workspace-less invokes are also legal — they use the daemon's configured `default_workspace`.

6. **FC contracts.** v2 keeps `/managed-git/create-repo` and Pro-distribution endpoints. `/register`, `/token`, `/reset-secret`, `/apply`, `/ai/setup-team`, `/ai/add-member`, `/ai/remove-member` are removed. `/ai/keys`, `/ai/usage`, `/ai/budget` are frozen as deprecated endpoints; v1 BYOK does not call them, and v2 will revive them as Supabase-JWT-authenticated AI proxy.

---

## Section 2 — Component Inventory

### 2.1 Removed

| Path | Reason |
|---|---|
| `src-tauri/binaries/opencode-*` (all platforms) | No more sidecar. Removes ~360 MB from installer payloads. |
| `src-tauri/src/commands/opencode.rs` (~2900 lines, 7 Tauri commands) | Replaced by MQTT bus + Supabase auth + daemon installer commands. |
| `packages/app/src/lib/opencode/` (sdk-client.ts, sdk-types.ts, sdk-sse.ts) | Frontend no longer talks to OpenCode. |
| `@opencode-ai/sdk` npm dependency | Drops the SDK from `package.json`. |
| `~/.opencode/` access code paths | Permission allowlist no longer lives in `opencode.db`. |
| `tauri.conf.json` `externalBin` entry for `binaries/opencode` | Keep `binaries/teamclaw-introspect`. |

### 2.2 Changed

| Module | New behavior |
|---|---|
| `stores/session-store.ts` | Holds `ActorEvent[]` (not `OpenCodeMessage[]`). Streaming buffer remains; the source becomes envelope decode output, not SSE. |
| `stores/session-loader.ts` | Calls Supabase REST for session metadata; subscribes to `session/{id}/live` for history via `AcpRequestHistory`. |
| `stores/session-sse-lifecycle-handlers.ts`, `session-sse-message-handlers.ts`, `session-sse-tool-handlers.ts` | Deleted; replaced with a single `lib/actor/event-handlers.ts` driven by Tauri `mqtt:envelope` events. |
| `stores/session-messages.ts` | `sendMessage` publishes a `ChatMessage` envelope through the Rust MQTT bus. |
| `stores/session-permissions.ts` | Listens for `AcpPermissionRequest` envelopes; publishes `AcpPermissionGrant` / `AcpPermissionDeny`. No `opencode.db` access. |
| `stores/mcp.ts` | MCP status comes from the daemon's retained `RuntimeInfo` message; no `client.getMCPStatus()` call. |
| `stores/team-mode.ts` | Workspace lifecycle calls daemon installer + Supabase team binding. Drops `invoke('start_opencode')`. |
| `stores/provider.ts` | Model list comes from `AcpAvailableCommands` events (the daemon advertises `available_models`). |
| Frontend message type | `Message {role: 'user' \| 'assistant'}` becomes `ActorEvent {actor_id, actor_type, payload}` rendered against `actors` map. |

### 2.3 Kept

- ChatPanel layout shell (constraint #1)
- Tiptap (markdown / HTML) editors and CodeMirror code editor — these are pure-client features
- Workspace picker UI and `~/.teamclaw/last-workspace.json`
- Iroh / OSS team sync (constraint #3) — `skills/`, `.mcp/`, `knowledge/` continue to sync to `<workspace>/`
- RAG (Tantivy) and STT (Whisper) — local capabilities, agent-independent
- Tauri shell `fs` watch / file IO — required by the editor
- `binaries/teamclaw-introspect` — independent introspection tool

### 2.4 Added

| Module | Purpose |
|---|---|
| `packages/app/src/lib/supabase-client.ts` | `@supabase/supabase-js` wrapper: auth, sessions / actors queries. |
| `packages/app/src/lib/mqtt-bridge.ts` | Thin TS wrapper around `invoke('mqtt_subscribe', ...)`, `invoke('mqtt_publish', ...)`, `listen('mqtt:envelope', ...)`. |
| `packages/app/src/lib/proto/` | Generated Protobuf bindings (from amuxd's `amux.proto`) using `@bufbuild/protobuf` — used for typing only; decode happens in Rust. |
| `packages/app/src/lib/actor/` | `ActorEvent` types and envelope-to-event mappers. |
| `src-tauri/src/commands/mqtt_bus.rs` | `rumqttc` 0.24 client (matches amuxd). One connection per Tauri process; events fan out to windows via `app_handle.emit_to`. Handles reconnection, retained messages, LWT. |
| `src-tauri/src/commands/daemon_installer.rs` | Fetches and verifies amuxd binary, generates launchd plist (Mac) / systemd user unit (Linux), pairs daemon with Supabase identity. |
| `src-tauri/src/commands/supabase_auth_bridge.rs` | OAuth deeplink handling, token refresh, persistence in `~/.teamclaw/auth.json`. |

---

## Section 3 — Data Flows

### 3.1 Cold start — open app, see session list

```
teamclaw launches
  ↓
Rust reads ~/.teamclaw/auth.json (Supabase refresh token)
  ↓ missing → OAuth deeplink → Supabase auth → write auth.json
  ↓ present → refresh access token
  ↓
Tauri command list_sessions(supabase_user_id):
  Rust calls Supabase REST: GET /rest/v1/sessions?actor_id=eq.{me}
  → returns sessions[]
  ↓
Frontend ChatPanel sidebar renders the list
  ↓
User selects a session → invoke('mqtt_subscribe', session_id)
  Rust mqtt_bus subscribes to session/{id}/live
    (cleanSession=false, QoS 1, retainHandling=SendAtSubscribe)
  → receives retained RuntimeInfo + recent N events
  → emits 'mqtt:envelope' to that window
```

**Constraint:** MQTT clean session = false with a persistent `client_id` (derived from `device_id`) ensures short disconnections do not lose messages, and the retained `RuntimeInfo` makes "joining a session immediately shows agent online status" hold.

### 3.2 Inviting an agent into a session

```
User clicks "+ Add agent" in a session
  ↓
Picker: select daemon (from Supabase agent_runtimes for current user)
  ↓
Workspace picker: select local path (existing component reused)
  ↓
Frontend invoke('mqtt_publish', envelope = AgentInvoke {
  target_daemon_id, workspace_path, agent_type: ClaudeCode, model
})
Rust publishes to session/{id}/live (QoS 1)
  ↓
Daemon subscribed to topic, receives AgentInvoke
  → verify target_daemon_id == self → yes
  → verify publisher's actor_id has can_invite_agent=true in session_actors
    (rejects unauthorized invitations from session participants — see §5.1)
  → verify Path::new(workspace_path).is_dir() → yes
    (remote daemon would fail here and publish AcpError back)
  → ACP NewSessionRequest::new(workspace_path) spawns Claude Code
  → publishes RuntimeInfo (status=running, available_commands, models)
    as retained to device/{daemon_id}/runtime/{rid}/state
  → publishes ActorJoin {actor_id=agent_xxx, actor_type=agent}
    on session/{id}/live
  ↓
All subscribers receive ActorJoin
  → UI participants list adds "Claude (online)" actor
```

### 3.3 Send message → agent streaming response

```
User types "重构 foo.ts" and presses send
  ↓
Frontend publishes ChatMessage {actor_id=me, text, mentions: [agent_xxx]}
  ↓ MQTT broadcast on session topic
  ↓
All actors receive (humans + agent's daemon)
  → Human UI: renders the message under the user's avatar
  → Daemon: sees mentions includes its agent_id → ACP send_prompt(text)
  ↓
Claude Code starts streaming
  Daemon translates ACP SessionUpdate → AcpEvent envelope:
    - AcpThinking
    - AcpOutput (text_delta, ~tens per second under load)
    - AcpToolUse (Edit, Bash, Read, ...)
    - AcpToolResult
    - AcpAvailableCommands (cached slash commands)
  Each envelope published to the same session topic
  ↓
All clients receive; route by actor_id=agent_xxx to that actor's stream
Render through STREAMING_ARCHITECTURE.md's pipeline:
  delta buffer → streamingContent → on completion → message.parts[]
```

The "single source of truth" rule from `STREAMING_ARCHITECTURE.md` is preserved — the delta buffer source becomes `ActorEvent` instead of SSE, but the buffer / content / parts contract is unchanged.

### 3.4 Permission flow with multiple humans present

```
Agent calls the Edit tool
  Daemon receives ACP request_permission → publishes AcpPermissionRequest:
    {request_id, actor_id=agent_xxx, tool=Edit, params={file, diff}, ttl=60s}
  ↓
Every human in the session sees "Claude wants to edit foo.ts; preview diff..."
Approval is restricted to mentioned humans (or first responder); others see read-only
  ↓
Zhang San clicks Approve → publishes AcpPermissionGrant {request_id, granted_by=zhangsan}
Li Si also clicks Approve concurrently → second envelope is idempotent at the daemon
Daemon, on first grant, calls ACP grant_permission(request_id)
  ↓
Claude continues; AcpToolResult is broadcast
All participants see the diff applied
```

v1 enforces "first responder wins". The `permission_policy` field on `session_actors` is reserved for v2 (`owner_only`, `quorum`, `auto_grant`); v1 reads but does not enforce it.

---

## Section 4 — Daemon Installer

### 4.1 Mac / Linux one-click path

**Frontend entry:** Settings → Agents → "Enable local Claude" button
**Tauri command:** `install_local_daemon(supabase_jwt) -> DaemonInstallStatus`

**Sequence:**

1. **Probe:** Check `~/.teamclaw/bin/amuxd` and version. If `>= MIN_AMUXD_VERSION`, jump to step 4.

2. **Download amuxd binary:**
   - URL template: `${AMUXD_RELEASE_BASE_URL}/v${VERSION}/amuxd-${PLATFORM}.tar.gz` where the base URL is a build-time constant baked into TeamClaw (the canonical amuxd release host)
   - Platform mapping: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`
   - Verify SHA256 against the release's `checksums.txt`
   - Extract to `~/.teamclaw/bin/amuxd`, `chmod +x`

3. **Register the system service:**
   - **macOS:** Write `~/Library/LaunchAgents/cc.ucar.amuxd.plist` (`KeepAlive=true`, `RunAtLoad=true`, `StandardOutPath=~/Library/Logs/amuxd.log`); `launchctl load -w` the plist.
   - **Linux:** Write `~/.config/systemd/user/amuxd.service`; run `systemctl --user daemon-reload && systemctl --user enable --now amuxd.service`.

4. **Pair daemon to Supabase account:**
   - TeamClaw calls Supabase RPC `create_daemon_pairing_token(user_id)` → 60s TTL token
   - Exec `~/.teamclaw/bin/amuxd init --pairing-token=<token> --supabase-url=...`
   - amuxd swaps the pairing token for a long-lived refresh token, persisted in `~/.config/amux/supabase.toml`
   - amuxd publishes `DeviceState` retained → Supabase trigger writes a new `agent_runtimes` row

5. **Health probe:** TeamClaw subscribes to `device/{expected_daemon_id}/state`, polling 1× / second up to 30 s, awaiting `status=online`. Timeout reports "daemon failed to start, check `~/Library/Logs/amuxd.log`".

6. **BYOK key entry:** Modal collects the user's Anthropic key. Tauri command `set_daemon_anthropic_key(key)` writes `~/.config/amux/keys.toml`. Daemon reloads on `SIGHUP`; the next agent spawn passes `ANTHROPIC_API_KEY` as an env var to Claude Code.

### 4.2 Windows manual path

The Settings page renders a documentation card:
- Step 1: Download `amuxd-x86_64-pc-windows-msvc.zip` and extract to `%LOCALAPPDATA%\teamclaw\bin\`
- Step 2: From a terminal, run `amuxd init --pairing-token=<displayed_token>`
- Step 3: Register `amuxd start` as a login-time task using a provided `schtasks.exe` snippet
- Step 4: Return to TeamClaw and click "I have installed it"; this kicks off step 5 from the auto path (health probe)

When amuxd publishes a verified Windows release, this path becomes a one-click branch in `daemon_installer.rs` (registry Run-key or Task Scheduler API). That work is captured as a follow-up issue, not in v1's scope.

### 4.3 Upgrade and uninstall

**Upgrade:**
- TeamClaw, on launch, fetches the amuxd latest-version manifest (24 h cache).
- If the local daemon is older, a toast prompts "amuxd update available". Confirming reruns step 2–3 and reloads the system service.

**Uninstall:**
- Settings → Agents → "Remove local Claude"
- `launchctl unload` / `systemctl --user disable`
- Delete `~/.teamclaw/bin/amuxd` and `~/.config/amux/`
- Supabase RPC `revoke_daemon(daemon_id)` marks the `agent_runtimes` row as deleted

### 4.4 Multi-daemon

One machine = one daemon = one agent identity in v1. Adding a second daemon (for example, a "work persona" alongside a "personal persona") is reserved for v2. The data model permits it (each daemon has its own `device_id` in `agent_runtimes`); the installer simply does not branch on it yet.

---

## Section 5 — Workspace and Filesystem Semantics

### 5.1 Path passing and validation

`AgentInvoke` envelope schema:

```protobuf
message AgentInvoke {
  string target_daemon_id = 1;     // routing
  string workspace_path = 2;       // absolute, daemon perspective; optional
  AgentType agent_type = 3;        // ClaudeCode (v1) | OpenCode | Codex (v2+)
  string model = 4;                // optional, defaults from daemon config
  map<string, string> env = 5;     // optional override env (e.g., ANTHROPIC_BASE_URL)
}
```

Daemon validation:
1. `target_daemon_id == self.id`? If not, ignore.
2. `Path::new(workspace_path).is_dir()`? If not, publish `AcpError{code: WORKSPACE_NOT_FOUND, request_id}`.
3. `workspace_path` under the daemon's allowed roots? Daemon config maintains a whitelist (default `~`); editable in daemon settings. Without this check, a malicious envelope could try to spawn an agent in `/etc`.

**Injection defense:** Because MQTT is a broadcast bus, any session participant can publish `AgentInvoke`. The daemon must not trust the sender blindly. Beyond the path whitelist, the daemon checks that the publisher's `actor_id` carries `can_invite_agent=true` in `session_actors` (a Supabase RLS-enforced flag).

### 5.2 Cross-machine invite fallback

**Scenario:** Zhang San opens a session on Machine A and invites a "team agent" hosted on Server B. The picker carries `workspace_path=/Users/zhangsan/code/foo` (path on A).

Server B's daemon validates `is_dir("/Users/zhangsan/code/foo")` → false → publishes:

```json
AcpError {
  code: WORKSPACE_NOT_AVAILABLE_HERE,
  message: "Path '/Users/zhangsan/code/foo' does not exist on this daemon's filesystem",
  suggestion: "Either invoke this agent from the same machine, or use a workspace-less prompt"
}
```

**Workspace-less invite:** v1 supports `AgentInvoke` with no `workspace_path`. The daemon falls back to its `default_workspace` (set during `amuxd init`). This path covers "team agent on a fixed server with its own working directory" — a clean coexistence with personal-machine agents.

### 5.3 File coordination — TeamClaw editor vs daemon writes

**Premise:** Single-machine case — TeamClaw and daemon share the same filesystem and workspace.

**Direction 1: Agent edits a file**
```
Agent ACP Edit tool → daemon performs fs::write directly
  ↓
TeamClaw fs watcher (chokidar / notify) detects mtime change
  ↓
If CodeMirror has the file open:
  - clean buffer (user has not edited) → auto-reload buffer
  - dirty buffer (user is editing) → show conflict resolution UI
    (reuses logic that exists today for the OpenCode mode)
```

**Direction 2: User edits in CodeMirror**
- Save → daemon needs no signaling.
- The next time the agent runs a Read tool, it sees the latest content.

No additional coordination protocol is required; the filesystem plus mtime plus the existing conflict-resolution UI is sufficient. This is the largest architectural payoff of the single-machine assumption.

### 5.4 Team shared directory and the daemon (constraint #3)

**Fact:** TeamClaw's team sync covers `<workspace>/.claude/skills/`, `<workspace>/.mcp/`, `<workspace>/knowledge/`.

**v2 behavior:**
- TeamClaw client continues to drive OSS / iroh sync (unchanged from v1)
- Synced content lands at `<workspace>/.claude/skills/`, etc.
- The daemon spawns Claude Code with `cwd = workspace_path`
- Claude Code reads `.claude/skills/`, `.mcp/config.json` etc. from its cwd as it does today
- The daemon is unaware of "team sync" — it forwards ACP events; skills and MCP servers are content the agent process reads from the workspace

Consequence: adding a new team skill requires no daemon changes; only TeamClaw clients need to sync.

### 5.5 Explicit non-goals for v1

- No remote workspace handling (container / VM daemon serving remote code) — `AcpError` rejection is final
- No multi-workspace single session — each `AgentInvoke` has one workspace; multiple agents in a session may use different workspaces (front-end agent in `frontend/`, back-end in `backend/`)
- No workspace sandboxing beyond the daemon's allow-list — no chroot or namespace
- No diff streaming over MQTT — `AcpToolUse` carries file path and operation type; clients fetch diffs from local fs

---

## Section 6 — Migration and Release Strategy

### 6.1 Development isolation: git worktree

```bash
git worktree add ../teamclaw-v2 -b v2/amuxd-architecture
cd ../teamclaw-v2
# v2 evolves independently; main remains patchable for v1
```

**Main-branch policy:** While v2 is under development, `main` continues to ship v1 patches. Protocol-layer code is **not** back-ported from v2 to main.
**v2 sync cadence:** Once a week, cherry-pick non-protocol fixes from main (chat rendering, CodeMirror, items on the "kept" list) into v2. Lint-only and formatting PRs are not cherry-picked.
**Owner:** A single person owns the cherry-pick rhythm to prevent drift.

### 6.2 Versioning

- v1 final patch line: `v1.X.Y` continues until v2 GA
- v2 first release: **v2.0.0** — major bump; the changelog explicitly states "breaking architecture change"
- No in-place v1 → v2 upgrade flow

### 6.3 User data: clean break

**v1 data is not migrated.** Specifically:
- Old session history in `~/.opencode/data/opencode/opencode.db` — v2 does not read it
- Old permission allowlist — re-formed in the daemon, per-agent
- `last-workspace.json` — readable, path format is unchanged

**User experience:** Upgrading to v2 means re-authenticating (OAuth into Supabase), an empty session list, and no carry-over chat history. v1 ships an "Export v1 history" feature in Settings (markdown / json) so users can keep what they want before upgrading. The export tool is a v1 main-branch task tracked separately from this spec; its scope is limited to read-only export and does not touch protocol code.

**Why:**
- v1 schema (OpenCode `Message[]`) and v2 schema (`ActorEvent[]`) are structurally incompatible
- A one-time migration script costs a week or more for low payoff (chat history is conversational, not artifactual)
- Team shared content (skills / MCP / knowledge) is on OSS / iroh and is not affected (constraint #3)

### 6.4 FC endpoint deprecation timeline

| Endpoint | v2 status | Notes |
|---|---|---|
| `/register`, `/token`, `/reset-secret` | Removed | Supabase OAuth replaces |
| `/apply` (team token verify) | Removed | `session_actors` + Supabase RLS |
| `/ai/setup-team`, `/add-member`, `/remove-member` | Removed | Supabase `teams` + `team_members` tables |
| `/ai/keys`, `/ai/usage`, `/ai/budget` | Frozen, code retained | v2 will revive as Supabase-JWT-authenticated AI proxy |
| `/managed-git/create-repo` | Kept | Independent of agent architecture |

**FC v1 endpoints' true delete date:** 3 months after v2.0 GA, to allow migration. During that window FC runs both endpoint sets; the deprecated ones return 200 with a `Deprecation: true` header before later returning `410 Gone`.

### 6.5 Release phases

| Phase | Duration | Scope |
|---|---|---|
| 0 — Setup | 1 week | Worktree creation; proto bindings; Tauri command skeletons; frontend `lib/actor` types |
| 1 — Core data flow | 3–4 weeks | MQTT bus + Supabase auth + ChatPanel wired to actor model. Local human↔human ChatMessage round-trip works. Agents not yet integrated. |
| 2 — Daemon integration | 3–4 weeks | Installer + ACP `start_agent` + end-to-end streaming + permission flow |
| 3 — Feature parity | 3–4 weeks | MCP / skills / slash commands rendering; multi-actor view; editor coordination; performance baseline |
| 4 — Migration / beta | 2–3 weeks | Docs; v1 export tool; internal beta; bug fixing |
| 5 — GA | — | v2.0.0 release |

**Total:** 12–16 weeks including buffer.

### 6.6 Beta and rollback

- 2–3 weeks of internal use (team daily-drives v2)
- 5–10 v1 users opt into beta
- v2.0.0-beta.X via GitHub pre-release; minimum two pre-releases before GA
- **No rollback mechanism.** v2 is a one-way upgrade (data store paths differ). Documentation states this explicitly.

### 6.7 Documentation deliverables

Three documents ship with v2 GA:
1. `docs/UPGRADING.md` — user-facing upgrade guide (data loss, re-login, rationale)
2. `docs/architecture/agents.md` — replaces `STREAMING_ARCHITECTURE.md`; restates the "single source of truth" principle in the actor model
3. `docs/architecture/mqtt-protocol.md` — envelope schema reference, with cross-references to amuxd's `amux.proto`

---

## Section 7 — Error Handling, Offline, Degradation

By failure layer, outermost first.

### 7.1 Supabase

| Failure | Behavior |
|---|---|
| Access token expired (60 min) | Refresh transparently; if refresh fails, toast "please re-login" and trigger OAuth |
| Refresh token revoked (device removed remotely) | Full logout, clear `~/.teamclaw/auth.json`, return to OAuth |
| Supabase unreachable | Show cached session list; top banner "cloud unreachable, some features unavailable"; MQTT also unreachable because the JWT cannot be refreshed |
| Session list fetch fails | Sidebar renders skeleton + retry button; existing MQTT subscriptions continue |

### 7.2 MQTT broker

| Failure | Behavior |
|---|---|
| Cannot reach EMQX | Exponential backoff (1 → 2 → 5 → 10 → 30 → 60 s, capped); top banner "connecting..." |
| Disconnect mid-session (network change, sleep) | rumqttc auto-reconnects; clean session=false + persistent client_id keeps server-side queue |
| Suspect missed messages after reconnect | Trigger `AcpRequestHistory` on each subscribed session by `last_seen_sequence`; UI reconciles by inserting missing events |
| Broker rate-limits / auth-rejects | Distinguish CONNACK 4xx vs 5xx; 4xx → re-auth flow; 5xx → backoff retry; persistent failure → top banner |

The recent `ba7b8f2` "fix webview recovery after sleep" applies here: with MQTT in the Rust process, the Tauri main process can listen for `NSWorkspaceDidWakeNotification` (macOS) or systemd suspend / resume signals (Linux) and force-reconnect — more reliable than relying on webview lifecycle hooks.

### 7.3 Daemon

| Failure | Behavior |
|---|---|
| Daemon process not running | `device/{id}/state` retained absent → UI shows agent actor as "offline" with restart button (Mac/Linux: launchctl/systemctl; Windows: instructions) |
| Daemon crashes (panic) | LWT publishes `DeviceState{status=offline}`; participants see agent go offline within ~5 s; launchd/systemd `KeepAlive=true` restarts the daemon; reconnection self-heals |
| Daemon protocol too old | TeamClaw checks daemon version against `MIN_AMUXD_VERSION` on startup; if low, prompts upgrade (4.3) |
| Daemon rejects with `WORKSPACE_NOT_FOUND` | Per-message red banner: "Cannot access path; is the daemon on the same machine?" with retry to re-pick workspace |

### 7.4 Agent subprocess (Claude Code)

| Failure | Behavior |
|---|---|
| API key invalid (401/403 from Anthropic) | Daemon translates to `AcpError{code: AGENT_AUTH_FAILED}`; UI shows "your Anthropic key is invalid" with a deep link to the BYOK setup |
| Rate limit / quota exhausted | `AcpError{code: AGENT_RATE_LIMITED, retry_after}` → UI shows countdown + retry button |
| Agent crashes mid-turn | Daemon detects stdio EOF → publishes `AcpError{code: AGENT_CRASHED}` + `RuntimeInfo{status=crashed}`; UI marks the streaming message "interrupted" and offers resend |
| Tool call timeout | ACP enforces timeout; result becomes `AcpToolResult{error: TIMEOUT}`; agent decides whether to retry |
| Permission unanswered for 60 s | `AcpPermissionRequest.ttl` expires → daemon treats it as deny; UI greys the request |

### 7.5 Multi-actor concurrency edges

| Scenario | Behavior |
|---|---|
| Two humans grant the same permission | Daemon treats the second envelope as idempotent (request_id seen); both UIs show "approved" |
| One grants, one denies (race) | First-wins by daemon's receive order; UI shows `granted_by` (or `denied_by`) for transparency |
| Same agent invited twice into one session | `session_actors` unique constraint on `daemon_id` blocks; UI shows "agent already in session" |
| Same daemon serves two sessions concurrently | Fully supported; amuxd's `RuntimeManager` is multi-runtime by design |
| User publishes ChatMessage while offline | MQTT publish queued locally; flushes on reconnect; > 24 h queued → marked failed, prompt to resend |

### 7.6 Workspace edges

| Scenario | Behavior |
|---|---|
| Agent edits while user edits same file in CodeMirror | Existing conflict UI (dirty buffer + fs change) handles it |
| Workspace directory deleted while agent is running | Next fs op fails → daemon emits `AcpError`; UI prompts to re-pick |
| Path with non-ASCII or spaces | rumqttc and ACP are UTF-8 safe; included in test cases. Windows separators handled by Rust `PathBuf` |

### 7.7 Single principle

**All errors flow as envelopes on the session topic**, not as Tauri command failures. Reasoning:
- All session participants (not just the originator) see the failure
- UI rendering is uniform — errors are events on the actor timeline
- Reconnection + history replay restores the full failure context

The single exception: client-local errors (fs read failure, auth refresh failure) before the session layer surface as Tauri errors.

---

## Section 8 — Testing Strategy

### 8.1 Rust unit tests (`src-tauri/`)

**Added:**
- `commands/mqtt_bus.rs` — envelope encode / decode, topic naming, subscribe / publish routing
- `commands/daemon_installer.rs` — platform-specific (plist generation, systemd unit generation, path resolution); mock fs via `tempfile`
- `commands/supabase_auth_bridge.rs` — token refresh, deeplink callback parsing

**Removed:**
- `commands/opencode.rs` test suite — deleted with the code

**Coverage targets:** protocol layer (envelope codec, error translation) ≥ 80 %; installer logic ≥ 70 %; UI bridge layer covered by integration tests, not units.

### 8.2 TypeScript unit tests (`packages/app/`)

**Added:**
- `lib/actor/event-mapper.spec.ts` — Protobuf JSON ↔ ActorEvent round-trip
- `lib/mqtt-bridge.spec.ts` — mock Tauri invoke / listen, subscription lifecycle
- `stores/session-store.spec.ts` — rewritten: actor model, streaming buffer, concurrent actor rendering
- `stores/session-permissions.spec.ts` — first-wins, idempotent grant, TTL expiry

**Removed:**
- `lib/opencode/sdk-*.spec.ts`
- `stores/session-sse-*.spec.ts`

**New fixtures:** `tests/fixtures/envelopes/` carries amuxd-captured envelope sequences (cold start, streaming, permission, error). Unit tests load these to enforce cross-implementation consistency.

### 8.3 Integration tests (new layer)

**Goal:** Run the path "frontend → Tauri command → MQTT bus → mock daemon → Tauri event → frontend" without launching Tauri or connecting to a real broker.

**Stack:**
- Vitest with `@tauri-apps/api/mocks` substituting `invoke` and `listen`
- Rust side: `mqtt_bus` is trait-abstracted; tests inject a `MockBroker` rather than connecting to EMQX
- Mock daemon: a TypeScript class implementing "receive `AgentInvoke` → reply with scripted `AcpThinking` / `AcpOutput` / completion"

**Representative cases:**
1. Invite agent → `RuntimeInfo` retained within 60 s
2. Send message → streaming deltas → completion → `message.parts[]` finalized
3. Permission request → simulated two-human grant race → daemon issues exactly one ACP grant call
4. Simulated 5 s MQTT disconnect → reconnect → missed envelopes recovered via `RequestHistory`

**Budget:** 30–50 cases, ~3 weeks to write.

### 8.4 E2E tests (existing tauri-mcp infrastructure)

The existing four directories (`tests/smoke/`, `regression/`, `performance/`, `functional/`) are reused; cases are nearly fully rewritten:

| Category | v2 focus |
|---|---|
| smoke | Launch → OAuth → session list visible → select session → MQTT subscription succeeds (banner reflects state) |
| regression | ChatPanel layout unchanged (constraint #1 verified); workspace picker; CodeMirror file IO; OSS / iroh sync |
| functional | Invite daemon → spawn agent → send message → streaming → tool call → permission flow → file modified → CodeMirror auto-reload |
| performance | Single session sustaining ~100 streaming deltas/s with frame budget < 16 ms; four windows, four concurrent subscriptions, CPU < 30 % |

**New E2E infrastructure:**
- `tests/helpers/mock-daemon.ts` — Node process speaking to a real EMQX dev broker, mocking amuxd; CI manages lifecycle
- `tests/helpers/dev-supabase.ts` — supabase-js operations on a dev project; each test suite seeds a clean user / session
- Optional: a local EMQX docker container in CI to avoid depending on the cloud broker

**Budget:** 4–6 weeks for E2E rewrite plus mock daemon plus dev infra.

### 8.5 Daemon-integration tests (new)

**Problem:** v1 has no such layer — the sidecar runs in-process. v2's standalone daemon needs explicit integration coverage.

**Approach:**
- New directory `tests/daemon-integration/`
- Real amuxd binary + real Claude Code (low-cost model + short prompts to control spend) + real EMQX dev broker + real Supabase dev project
- Nightly run (not on PR CI — too slow, too expensive)
- Three watchdogs: protocol compatibility (no envelope breaks across amuxd upgrades), liveness (no test exceeds 30 minutes), exhaustive error-code translation

### 8.6 Tests retained as-is

- ESLint, TypeScript strict, `cargo clippy -- -D warnings`
- `cargo fmt --check`
- `pnpm test:e2e:smoke` entrypoint name (cases swap, name does not)

### 8.7 Performance baseline (new)

Established before v2 GA; PRs may not regress:
- Cold-start to first paint with cached OAuth: < 2.5 s
- Session switch to first historical message rendered: < 200 ms
- Single streaming delta end-to-end (broker publish → UI render): < 100 ms p50
- Idle CPU (4 sessions subscribed, no traffic): < 5 %

---

## Section 9 — Open Questions and v2+ Items

These are documented as out of scope for v1 but anticipated:

1. **FC AI proxy with Supabase JWT (Q7-B path).** Required for team / enterprise customers who do not want BYOK. Implementation requires FC adoption of long-running connections (SAE container or WebSocket gateway) to handle Anthropic streaming.
2. **Lease-based host migration.** When a daemon goes offline, another participant's daemon could pick up the agent runtime (resuming via ACP `ResumeSession`). Useful for "always-on team agents" but depends on amuxd's `unstable_session_resume` becoming stable.
3. **Cloud-hosted agents.** Running Claude Code in FC / containers, with the workspace mounted from OSS or fetched from a Git repository. Required for any client that lacks a local filesystem; requires a separate workstream.
4. **Windows one-click installer.** Once amuxd has verified Windows support, replace the manual flow with registry Run-key or Task Scheduler API automation in `daemon_installer.rs`.
5. **Multi-daemon per machine.** "Work persona vs personal persona" agent identities. Data model already supports it via distinct `device_id`s; installer needs branching.
6. **Sub-task delegation between agents.** Agent A delegates to Agent B (matches the project memory note on task decomposition). Requires an `AgentInvoke` chain and an idempotency mechanism for cycles.
7. **OpenCode and Codex agent types.** amuxd's `AgentType` enum reserves these; v1 only ships `ClaudeCode`. Adding them requires writing ACP shims for agents that do not natively speak ACP.
8. **`permission_policy` enforcement.** v1 reads but does not enforce policies (`owner_only`, `quorum`, `auto_grant`). v2 implements them server-side via Supabase RLS or daemon-side checks.
9. **Linux Wayland support for daemon installer.** systemd user units assume a logged-in session; headless Linux server scenarios may need a different approach.

## References

- `CLAUDE.md` — project overview, commands, streaming architecture pointer
- `packages/app/src/stores/STREAMING_ARCHITECTURE.md` — single-source-of-truth principle preserved in v2
- `/Volumes/openbeta/workspace/amux/daemon` — amuxd source; canonical ACP host implementation
- `/Volumes/openbeta/workspace/amux/proto/amux.proto` — protocol definitions; v2 envelope schema extends this
- `/Volumes/openbeta/workspace/amux/docs/specs/2026-04-15-amux-architecture.md` — amuxd architecture design
- `docs/superpowers/specs/2026-04-04-mqtt-protobuf-migration-design.md` — earlier MQTT effort (parked); informs but does not constrain v2
- Recent commits: `b0937c7` (multi-window workspace isolation), `ba7b8f2` (webview recovery after sleep) — load-bearing for §7 reconnection logic
