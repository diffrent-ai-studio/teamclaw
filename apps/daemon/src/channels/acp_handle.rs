//! `AcpHandle` impl: bridges `teamclaw_gateway` channels to amuxd's
//! in-process `RuntimeManager` so a chat message arriving over Discord /
//! WeCom / Feishu / etc. drives an ACP turn without going through the
//! deprecated opencode HTTP server.
//!
//! ## Logical vs real ACP session ids
//!
//! Channels persist the SQL-minted `acp_session_id` (random hex from
//! `ensure_gateway_session`) on the `sessions` row and then pass it to
//! `send_prompt`. That string is a *logical* id — it was never registered
//! with amuxd's `RuntimeManager`, which only knows real ACP UUIDs returned
//! by `session/new`.
//!
//! To bridge the two, this handle keeps an in-memory `logical_to_acp` map.
//! On `send_prompt`, if the logical id has no entry, we lazy-spawn a fresh
//! agent via `create_gateway_session` and remember the mapping. On amuxd
//! restart the map is empty, so the first prompt for each persisted session
//! re-spawns; old conversation history stays in Supabase regardless.

use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use teamclaw_gateway::{AcpError, AcpHandle, AcpTurnOutcome, AmuxSessionId};

use crate::runtime::RuntimeManager;

pub struct AmuxdAcpHandle {
    pub manager: Arc<Mutex<RuntimeManager>>,
    /// Logical (SQL-minted) acp_session_id → real ACP UUID returned by
    /// `RuntimeManager::create_gateway_session`. In-memory only.
    pub logical_to_acp: Arc<Mutex<HashMap<String, String>>>,
    /// Team id used when lazy-spawning a runtime on first `send_prompt`.
    /// Set by the F4 wiring layer when the handle is constructed.
    pub team_id: String,
}

impl AmuxdAcpHandle {
    /// Resolve the caller-supplied `session` (a logical id persisted on the
    /// `sessions` row) to a real ACP UUID, spawning a runtime on first use.
    async fn resolve_or_spawn(&self, session: &AmuxSessionId) -> Result<String, AcpError> {
        let mut map = self.logical_to_acp.lock().await;
        if let Some(existing) = map.get(session) {
            return Ok(existing.clone());
        }
        let real = {
            let mut mgr = self.manager.lock().await;
            mgr.create_gateway_session(&self.team_id, session, "Gateway session")
                .await
                .map_err(|e| AcpError::Create(e.to_string()))?
        };
        map.insert(session.to_string(), real.clone());
        Ok(real)
    }
}

#[async_trait]
impl AcpHandle for AmuxdAcpHandle {
    async fn create_session(
        &self,
        _team_id: &str,
        binding: &str,
        _title: &str,
    ) -> Result<AmuxSessionId, AcpError> {
        // Channels never call this in the gateway-port architecture — the
        // SQL store mints the logical acp_session_id via
        // `ensure_gateway_session`. We keep a consistent implementation in
        // case future callers use it: hand back the binding as the logical
        // id; `send_prompt` will lazy-spawn on first use.
        Ok(binding.to_string())
    }

    async fn send_prompt(
        &self,
        session: &AmuxSessionId,
        sender_display: &str,
        text: &str,
    ) -> Result<AcpTurnOutcome, AcpError> {
        let real_acp_sid = self.resolve_or_spawn(session).await?;

        let mut mgr = self.manager.lock().await;
        let prompt = format!("[{sender_display}] {text}");
        let reply = mgr
            .send_prompt_and_await_reply(&real_acp_sid, &prompt)
            .await
            .map_err(|e| AcpError::Send(e.to_string()))?;
        Ok(AcpTurnOutcome {
            reply_text: reply,
            completed: true,
        })
    }

    async fn inject_context(
        &self,
        session: &AmuxSessionId,
        sender_display: &str,
        text: &str,
    ) -> Result<(), AcpError> {
        let real_acp_sid = self.resolve_or_spawn(session).await?;
        let mgr = self.manager.lock().await;
        mgr.inject_context(&real_acp_sid, sender_display, text)
            .await
            .map_err(|e| AcpError::Send(e.to_string()))
    }
}
