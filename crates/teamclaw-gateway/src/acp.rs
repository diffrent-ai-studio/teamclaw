use async_trait::async_trait;

/// Identifier of an amuxd session that a gateway channel is conversing with.
/// Opaque to the gateway; resolved against amuxd's runtime manager.
pub type AmuxSessionId = String;

/// Describes a model the daemon can drive, returned by `list_models`.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ModelInfo {
    pub provider: String,
    pub model: String,
    pub display_name: String,
}

/// Outcome of a single ACP turn driven by a gateway message.
#[derive(Debug, Clone)]
pub struct AcpTurnOutcome {
    pub reply_text: String,
    pub completed: bool,
}

/// Abstraction over amuxd's in-process ACP runtime. Channels call this
/// instead of POSTing to opencode's HTTP server.
#[async_trait]
pub trait AcpHandle: Send + Sync + 'static {
    /// Create a new ACP-backed session for a freshly-bound gateway conversation.
    /// Returns the amuxd session id to persist on the gateway's `Binding`.
    async fn create_session(
        &self,
        team_id: &str,
        binding: &str,
        title: &str,
    ) -> Result<AmuxSessionId, AcpError>;

    /// Send a user prompt and wait for the agent's reply text. Equivalent to
    /// v1's `prompt_async` + SSE polling, but synchronous and in-process.
    async fn send_prompt(
        &self,
        session: &AmuxSessionId,
        sender_display: &str,
        text: &str,
    ) -> Result<AcpTurnOutcome, AcpError>;

    /// Inject context without triggering a reply (v1 `noReply: true`).
    /// Kept on the trait for future use; not called by v1-of-port channels.
    async fn inject_context(
        &self,
        session: &AmuxSessionId,
        sender_display: &str,
        text: &str,
    ) -> Result<(), AcpError>;

    /// Cancel any in-flight turn on this session. Used by /stop.
    async fn cancel(&self, session: &AmuxSessionId) -> Result<(), AcpError>;

    /// Drop the runtime context for this session — next send_prompt re-spawns
    /// a fresh agent under the same logical id. Used by /reset.
    async fn reset_session(&self, session: &AmuxSessionId) -> Result<(), AcpError>;

    /// List available models the daemon can drive. Used by /model (no arg).
    async fn list_models(&self) -> Result<Vec<ModelInfo>, AcpError>;

    /// Pin a model for this session. Restarts the underlying agent —
    /// conversation context is lost. Used by /model X.
    async fn set_model(
        &self,
        session: &AmuxSessionId,
        provider: &str,
        model: &str,
    ) -> Result<(), AcpError>;
}

#[derive(Debug, thiserror::Error)]
pub enum AcpError {
    #[error("acp session creation failed: {0}")]
    Create(String),
    #[error("acp send failed: {0}")]
    Send(String),
    #[error("acp turn timed out")]
    Timeout,
}
