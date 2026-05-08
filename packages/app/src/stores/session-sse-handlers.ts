/**
 * session-sse-handlers.ts — Phase 1E stub.
 *
 * OpenCode sidecar removed. The SSE handler sub-modules have been deleted.
 * This file is kept as a stub to maintain module resolution for any remaining
 * imports during the transition to native Tauri-RPC event handling.
 */
import type { SessionState } from "./session-types";

type SessionSet = (fn: ((state: SessionState) => Partial<SessionState>) | Partial<SessionState>) => void;
type SessionGet = () => SessionState;

export function createSSEHandlers(_set: SessionSet, _get: SessionGet) {
  return {};
}
