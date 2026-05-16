use async_trait::async_trait;

/// What a channel needs the Supabase-backed store to do.
/// Concrete impl lives in amuxd (which holds the Supabase client).
#[async_trait]
pub trait ChannelStore: Send + Sync + 'static {
    /// Resolve or create an external actor (e.g., a WeCom user).
    /// `display_name` is updated on every call (cheap UPSERT).
    async fn ensure_external_actor(
        &self,
        team_id: &str,
        source: &str,
        source_id: &str,
        display_name: &str,
    ) -> Result<String /* actor_id */, StoreError>;

    /// Resolve the amuxd session for a gateway binding, creating one if absent.
    /// Returns (session_id, amuxd_acp_session_id, is_new).
    async fn ensure_session(
        &self,
        team_id: &str,
        binding: &str,
        title: &str,
        primary_agent_actor_id: &str,
        owner_member_actor_ids: &[String],
        participant_actor_ids: &[String],
    ) -> Result<EnsureSessionOutcome, StoreError>;

    /// Persist a single chat message to Supabase. Idempotent on (session_id, external_message_id).
    async fn record_message(
        &self,
        session_id: &str,
        sender_actor_id: &str,
        content: &str,
        external_message_id: Option<&str>,
    ) -> Result<String /* message_id */, StoreError>;

    /// Add a participant if not already in session_participants.
    async fn add_participant(&self, session_id: &str, actor_id: &str) -> Result<(), StoreError>;
}

#[derive(Debug, Clone)]
pub struct EnsureSessionOutcome {
    pub session_id: String,
    pub acp_session_id: String,
    pub created: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("supabase store error: {0}")]
    Supabase(String),
}
