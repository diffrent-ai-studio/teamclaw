/**
 * sdk-client.ts — Phase 1E stub.
 *
 * OpenCode sidecar removed. All functions throw at runtime.
 * These stubs exist solely to keep TypeScript compilation clean during
 * the transition to native Tauri-RPC session management.
 */

import type {
  OpenCodeConfig,
  Command,
  MCPServerConfig,
  MCPStatusMap,
  SendMessageRequest,
  PermissionReplyRequest,
  PermissionAskedEvent,
  Session,
  SessionListItem,
  Message,
  Project,
} from './sdk-types'

// Re-export Command type for convenience
export type { Command }

// ---------------------------------------------------------------------------
// Stub client interface — covers every method used across all stores
// ---------------------------------------------------------------------------

/** Compatibility interface stub */
export interface OpenCodeClientCompat {
  // Session management
  getSessions(opts?: { workspacePath?: string }): Promise<SessionListItem[]>
  listSessions(opts?: { directory?: string; roots?: boolean; archived?: boolean }): Promise<SessionListItem[]>
  getSession(sessionId: string): Promise<Session | null>
  createSession(opts?: { workspacePath?: string; title?: string }): Promise<Session>
  deleteSession(sessionId: string): Promise<void>
  getMessages(sessionId: string, opts?: { after?: string }): Promise<Message[]>
  loadAllMessages(sessionId: string): Promise<Message[]>
  getSessionChildren(sessionId: string): Promise<SessionListItem[]>
  archiveSession(sessionId: string, directory?: string): Promise<void>
  restoreSession(sessionId: string, directory?: string): Promise<void>
  updateSession(sessionId: string, opts: unknown): Promise<void>

  // Todo / Diff
  getTodos(sessionId: string): Promise<Array<{ id: string; content: string; status: string; priority: string }>>
  getSessionDiff(sessionId: string): Promise<Array<{ file: string; before?: string; after?: string; additions?: number; deletions?: number }>>

  // Message sending
  sendMessage(sessionId: string, request: SendMessageRequest): Promise<void>
  sendMessageAsync(sessionId: string, content: string, model?: unknown, agent?: string, systemPrompt?: string): Promise<string>
  sendMessageWithPartsAsync(sessionId: string, parts: unknown, model?: unknown, agent?: string, systemPrompt?: string): Promise<string>
  abortSession(sessionId: string): Promise<void>

  // Permission
  replyPermission(permissionId: string, request: PermissionReplyRequest): Promise<void>
  listPermissions(sessionId?: string): Promise<PermissionAskedEvent[]>

  // Question
  replyQuestion(
    sessionIdOrQuestionId: string,
    answersOrQuestionId: Record<string, string> | string,
    answers?: Record<string, string>,
  ): Promise<void>
  rejectQuestion(sessionIdOrQuestionId: string, questionId?: string): Promise<void>

  // MCP
  getMCPStatus(): Promise<Record<string, { status: string; error?: string }>>
  addMCPServer(name: string, config: MCPServerConfig): Promise<void>
  removeMCPServer(name: string): Promise<void>
  disconnectMCP(name: string): Promise<void>
  connectMCP(name: string): Promise<void>

  // Provider / Auth
  getAuthMethods(): Promise<unknown>
  getProviders(): Promise<{ all: unknown[]; connected?: string[] }>
  getConfigProviders(): Promise<{ providers?: Array<{ id?: string; name?: string; models?: unknown }> }>
  oauthAuthorize(providerId: string, methodIndex?: unknown): Promise<{ url: string; instructions?: string; method?: string } | null>
  oauthCallback(providerId: string, methodIndex: unknown, code?: string): Promise<void>
  setAuth(providerId: string, auth: unknown): Promise<void>
  deleteAuth(providerId: string): Promise<void>

  // Git
  getFileStatus(): Promise<unknown>

  // Other
  isReady(): boolean
  getConfig(): Promise<unknown>
  updateConfig(config: unknown): Promise<void>
  getProject(): Promise<Project | null>
  listCommands(): Promise<Command[]>
  executeCommand(name: string, sessionId?: string): Promise<void>
}

// ---------------------------------------------------------------------------
// Singleton state
// ---------------------------------------------------------------------------

let _config: OpenCodeConfig | null = null

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Initialize the client configuration (no-op in stub). */
export function initOpenCodeClient(config: OpenCodeConfig): void {
  _config = config
}

/** Get the current config. */
export function getOpenCodeConfig(): OpenCodeConfig | null {
  return _config
}

function notSupported(name: string): never {
  throw new Error(
    `[OpenCode stub] ${name}: OpenCode sidecar removed. This feature is not available in Phase 1E.`,
  )
}

/** Returns a stub client object. All methods throw at runtime. */
export function getOpenCodeClient(): OpenCodeClientCompat {
  return {
    getSessions: () => notSupported('getSessions'),
    listSessions: () => notSupported('listSessions'),
    getSession: () => notSupported('getSession'),
    createSession: () => notSupported('createSession'),
    deleteSession: () => notSupported('deleteSession'),
    getMessages: () => notSupported('getMessages'),
    loadAllMessages: () => notSupported('loadAllMessages'),
    getSessionChildren: () => notSupported('getSessionChildren'),
    archiveSession: () => notSupported('archiveSession'),
    restoreSession: () => notSupported('restoreSession'),
    updateSession: () => notSupported('updateSession'),
    sendMessage: () => notSupported('sendMessage'),
    sendMessageAsync: () => notSupported('sendMessageAsync'),
    sendMessageWithPartsAsync: () => notSupported('sendMessageWithPartsAsync'),
    abortSession: () => notSupported('abortSession'),
    replyPermission: () => notSupported('replyPermission'),
    listPermissions: () => notSupported('listPermissions'),
    replyQuestion: () => notSupported('replyQuestion'),
    rejectQuestion: () => notSupported('rejectQuestion'),
    getTodos: () => notSupported('getTodos'),
    getSessionDiff: () => notSupported('getSessionDiff'),
    getMCPStatus: () => notSupported('getMCPStatus'),
    addMCPServer: () => notSupported('addMCPServer'),
    removeMCPServer: () => notSupported('removeMCPServer'),
    disconnectMCP: () => notSupported('disconnectMCP'),
    connectMCP: () => notSupported('connectMCP'),
    getAuthMethods: () => notSupported('getAuthMethods'),
    getProviders: () => notSupported('getProviders'),
    getConfigProviders: () => notSupported('getConfigProviders'),
    oauthAuthorize: () => notSupported('oauthAuthorize'),
    oauthCallback: () => notSupported('oauthCallback'),
    setAuth: () => notSupported('setAuth'),
    deleteAuth: () => notSupported('deleteAuth'),
    getFileStatus: () => notSupported('getFileStatus'),
    isReady: () => false,
    getConfig: () => notSupported('getConfig'),
    updateConfig: () => notSupported('updateConfig'),
    getProject: () => notSupported('getProject'),
    listCommands: () => notSupported('listCommands'),
    executeCommand: () => notSupported('executeCommand'),
  }
}

// Individual function exports that mirror the old sdk-client API

export async function getSessions(_opts?: { workspacePath?: string }): Promise<SessionListItem[]> {
  return notSupported('getSessions')
}

export async function createSession(_opts?: {
  workspacePath?: string
  title?: string
}): Promise<Session> {
  return notSupported('createSession')
}

export async function deleteSession(_sessionId: string): Promise<void> {
  return notSupported('deleteSession')
}

export async function getMessages(_sessionId: string): Promise<Message[]> {
  return notSupported('getMessages')
}

export async function sendMessage(
  _sessionId: string,
  _request: SendMessageRequest,
): Promise<void> {
  return notSupported('sendMessage')
}

export async function abortSession(_sessionId: string): Promise<void> {
  return notSupported('abortSession')
}

export async function replyPermission(
  _permissionId: string,
  _request: PermissionReplyRequest,
): Promise<void> {
  return notSupported('replyPermission')
}

export async function replyQuestion(
  _sessionId: string,
  _questionId: string,
  _answers: Record<string, string>,
): Promise<void> {
  return notSupported('replyQuestion')
}

export async function getMCPStatus(): Promise<MCPStatusMap> {
  return notSupported('getMCPStatus')
}

export async function getConfig(): Promise<unknown> {
  return notSupported('getConfig')
}

export async function updateConfig(_config: unknown): Promise<void> {
  return notSupported('updateConfig')
}

export async function listCommands(): Promise<Command[]> {
  return notSupported('listCommands')
}

export async function executeCommand(_name: string, _sessionId?: string): Promise<void> {
  return notSupported('executeCommand')
}

export async function addMCPServer(_name: string, _config: MCPServerConfig): Promise<void> {
  return notSupported('addMCPServer')
}

export async function updateMCPServer(_name: string, _config: MCPServerConfig): Promise<void> {
  return notSupported('updateMCPServer')
}

export async function removeMCPServer(_name: string): Promise<void> {
  return notSupported('removeMCPServer')
}

export async function updateSession(_sessionId: string, _opts: unknown): Promise<void> {
  return notSupported('updateSession')
}

export async function sendMessageWithParts(
  _sessionId: string,
  _request: SendMessageRequest,
): Promise<void> {
  return notSupported('sendMessageWithParts')
}

export async function sendMessageAsync(
  _sessionId: string,
  _request: SendMessageRequest,
): Promise<string> {
  return notSupported('sendMessageAsync')
}

export async function sendMessageWithPartsAsync(
  _sessionId: string,
  _request: SendMessageRequest,
): Promise<string> {
  return notSupported('sendMessageWithPartsAsync')
}

export async function getTodos(_sessionId: string): Promise<unknown[]> {
  return notSupported('getTodos')
}

export async function getSessionDiff(_sessionId: string): Promise<unknown[]> {
  return notSupported('getSessionDiff')
}

export async function updateConfig2(_key: string, _value: unknown): Promise<void> {
  return notSupported('updateConfig')
}

export async function setAuth(
  _providerId: string,
  _auth: unknown,
): Promise<void> {
  return notSupported('setAuth')
}

export async function oauthAuthorize(
  _providerId: string,
  _opts?: unknown,
): Promise<{ url: string; state: string }> {
  return notSupported('oauthAuthorize')
}

export async function oauthCallback(_code: string, _state: string): Promise<void> {
  return notSupported('oauthCallback')
}

export async function getProviders(): Promise<unknown[]> {
  return notSupported('getProviders')
}

export async function getProject(): Promise<Project | null> {
  return notSupported('getProject')
}
