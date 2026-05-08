/**
 * App-level types for the agent session system.
 *
 * Phase 1E: @opencode-ai/sdk removed. All types are now hand-crafted
 * or stubbed for compilation. These will be replaced with native
 * Tauri-RPC types in Phase 3.
 */

// ---------------------------------------------------------------------------
// Core session / message types
// ---------------------------------------------------------------------------

export interface Session {
  id: string
  title?: string
  path?: string
  directory?: string
  time?: { created: number; updated?: number; archived?: number | null }
  parentID?: string
  summary?: {
    diffs?: Array<{ file: string; before?: string; after?: string; additions?: number; deletions?: number }>
    [key: string]: unknown
  }
}

export interface SnapshotFileDiff {
  file: string
  before: string
  after: string
  additions: number
  deletions: number
}

export interface FileDiff {
  file: string
  before: string
  after: string
  additions: number
  deletions: number
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

export interface MessageInfo {
  id: string
  sessionID: string
  role: 'user' | 'assistant'
  time: {
    created: number
    completed?: number
  }
  parentID?: string
  modelID?: string
  providerID?: string
  mode?: string
  agent?: string
  path?: {
    cwd: string
    root: string
  }
  cost?: number
  tokens?: {
    input: number
    output: number
    reasoning: number
    cache: {
      read: number
      write: number
    }
  }
  finish?: string
  summary?: boolean
  synthetic?: boolean
  metadata?: Record<string, unknown>
}

export interface MessagePart {
  id: string
  sessionID: string
  messageID: string
  type: string
  text?: string
  toolCall?: ToolCallInfo
  toolResult?: ToolResult
  tool?: string
  callID?: string
  state?: {
    status: 'pending' | 'running' | 'completed' | 'error'
    input: Record<string, unknown>
    raw?: string
    output?: unknown
    result?: unknown
  }
  time?: {
    start: number
    end?: number
  }
  snapshot?: string
  reason?: string
  cost?: number
  tokens?: {
    input: number
    output: number
    reasoning: number
    cache: {
      read: number
      write: number
    }
  }
  auto?: boolean
  overflow?: boolean
  completed?: boolean
  tail_start_id?: string
}

export interface Message {
  info: MessageInfo
  parts: MessagePart[]
}

export interface ToolCallInfo {
  name: string
  id: string
  input: Record<string, unknown>
}

export interface ToolResult {
  type: 'text' | 'error'
  content: string
  error?: string
}

// ---------------------------------------------------------------------------
// Aliases / compat shims
// ---------------------------------------------------------------------------

export type SessionListItem = Session

export type ToolCallStatus = 'calling' | 'completed' | 'failed' | 'waiting'

// ---------------------------------------------------------------------------
// Handler event types (used by SSE handlers and stores)
// ---------------------------------------------------------------------------

export interface MessageCreatedEvent {
  id: string
  sessionId: string
  role: 'user' | 'assistant'
  createdAt: string
}

export interface MessagePartCreatedEvent {
  messageId: string
  partId: string
  type: 'text' | 'tool_call' | 'tool_result' | 'text_delta' | 'reasoning' | 'step-start' | 'step-finish' | 'compaction'
  content?: string
  text?: string
  auto?: boolean
  overflow?: boolean
  completed?: boolean
  tool?: ToolCallInfo
  result?: ToolResult
  duration?: number
}

export interface MessagePartUpdatedEvent {
  messageId: string
  partId: string
  type: 'text_delta' | 'reasoning_delta'
  delta: string
  stopReason?: 'end_turn' | 'max_tokens' | null
  usage?: TokenUsage
}

export interface MessageCompletedEvent {
  messageId: string
  sessionId: string
  finalContent: string
  usage: TokenUsage
  tokens?: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
  cost?: number
}

export interface ToolExecutingEvent {
  toolCallId: string
  toolName: string
  status: 'running' | 'completed' | 'failed'
  arguments?: Record<string, unknown>
  result?: string
  duration?: number
  sessionId?: string
  messageId?: string
  title?: string
  metadata?: {
    title?: string
    sessionId?: string
    model?: { providerID: string; modelID: string }
    summary?: Array<{
      id: string
      tool: string
      state: {
        status: string
        title?: string
      }
    }>
  }
}

export interface PermissionAskedEvent {
  id: string
  sessionID: string
  permission: string
  patterns: string[]
  always?: string[]
  metadata?: Record<string, unknown>
  tool?: {
    callID: string
    messageID: string
  }
}

export interface PermissionReplyRequest {
  reply: 'once' | 'always' | 'reject'
}

export interface ErrorEvent {
  code: string
  message: string
  details?: Record<string, unknown>
}

export interface SessionErrorEvent {
  sessionId?: string
  error?: {
    name: string
    data: {
      message: string
      providerID?: string
      statusCode?: number
      isRetryable?: boolean
    }
  }
}

export interface TokenUsage {
  inputTokens: number
  outputTokens: number
  cacheCreationInputTokens?: number
  cacheReadInputTokens?: number
}

// ---------------------------------------------------------------------------
// Todo / Question / Command (app-level shapes)
// ---------------------------------------------------------------------------

export interface Todo {
  id: string
  content: string
  status: 'pending' | 'in_progress' | 'completed' | 'cancelled'
  priority: 'high' | 'medium' | 'low'
}

export interface QuestionOption {
  id?: string
  label: string
  value?: string
}

export interface Question {
  id?: string
  question: string
  header?: string
  options: QuestionOption[]
}

export interface Command {
  name: string
  description?: string
  template?: string
  agent?: string
  model?: string
  subtask?: boolean
}

// ---------------------------------------------------------------------------
// MCP types (app-level)
// ---------------------------------------------------------------------------

export interface MCPServerConfig {
  type: 'local' | 'remote'
  enabled?: boolean
  command?: string[]
  environment?: Record<string, string>
  url?: string
  headers?: Record<string, string>
  timeout?: number
}

export type MCPServerStatus = 'connected' | 'disabled' | 'failed' | 'needs_auth' | 'needs_client_registration'

export interface MCPRuntimeStatus {
  status: MCPServerStatus
  error?: string
}

export type MCPStatusMap = Record<string, MCPRuntimeStatus>

// ---------------------------------------------------------------------------
// Project type (app-level)
// ---------------------------------------------------------------------------

export interface Project {
  path: string
  name: string
  version?: string
  git?: {
    branch: string
    remote: string
    hasUncommitted: boolean
  }
}

// ---------------------------------------------------------------------------
// SSE event types
// ---------------------------------------------------------------------------

export type SSEEventType =
  | 'message.created'
  | 'message.part.created'
  | 'message.part.updated'
  | 'message.completed'
  | 'tool.executing'
  | 'permission.asked'
  | 'permission.replied'
  | 'session.created'
  | 'session.updated'
  | 'session.deleted'
  | 'error'
  | 'server.ready'

export interface OpenCodeSSEEvent<T = unknown> {
  type: SSEEventType
  data: T
}

// ---------------------------------------------------------------------------
// Message part input types for sending messages (app-level)
// ---------------------------------------------------------------------------

export type SendMessageTextPart = {
  type: 'text'
  text: string
}

export type SendMessageFilePart = {
  type: 'file'
  url: string
  mime: string
  filename?: string
}

export interface SendMessageRequest {
  parts: Array<SendMessageTextPart | SendMessageFilePart>
  agent?: string
  systemPrompt?: string
}

// SSE event types used by session store handlers

export interface QuestionAskedEvent {
  id: string
  sessionId: string
  questions: Question[]
  tool?: {
    callId: string
    messageId: string
  }
}

export interface QuestionToolInput {
  questions: Question[]
}

export interface TodoUpdatedEvent {
  sessionId: string
  todos: Todo[]
}

export interface SessionDiffEvent {
  sessionId: string
  diff: FileDiff[]
}

// ---------------------------------------------------------------------------
// OpenCode config type (kept for compat; config.ts no longer needs sdk)
// ---------------------------------------------------------------------------

export interface OpenCodeConfig {
  baseUrl: string
  password?: string
  workspacePath?: string
}
