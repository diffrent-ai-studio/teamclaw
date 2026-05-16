//! `AcpHandle` impl: bridges `teamclaw_gateway` channels to amuxd's
//! in-process `RuntimeManager` so a chat message arriving over Discord /
//! WeCom / Feishu / etc. drives an ACP turn without going through the
//! deprecated opencode HTTP server.

use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::Mutex;

use teamclaw_gateway::{AcpError, AcpHandle, AcpTurnOutcome, AmuxSessionId};

use crate::runtime::RuntimeManager;

pub struct AmuxdAcpHandle {
    pub manager: Arc<Mutex<RuntimeManager>>,
}

#[async_trait]
impl AcpHandle for AmuxdAcpHandle {
    async fn create_session(
        &self,
        team_id: &str,
        binding: &str,
        title: &str,
    ) -> Result<AmuxSessionId, AcpError> {
        let mut mgr = self.manager.lock().await;
        mgr.create_gateway_session(team_id, binding, title)
            .await
            .map_err(|e| AcpError::Create(e.to_string()))
    }

    async fn send_prompt(
        &self,
        session: &AmuxSessionId,
        sender_display: &str,
        text: &str,
    ) -> Result<AcpTurnOutcome, AcpError> {
        let mut mgr = self.manager.lock().await;
        let prompt = format!("[{sender_display}] {text}");
        let reply = mgr
            .send_prompt_and_await_reply(session, &prompt)
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
        let mgr = self.manager.lock().await;
        mgr.inject_context(session, sender_display, text)
            .await
            .map_err(|e| AcpError::Send(e.to_string()))
    }
}
