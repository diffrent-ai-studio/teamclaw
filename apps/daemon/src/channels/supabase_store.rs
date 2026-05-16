//! `ChannelStore` impl: adapts amuxd's Supabase client to the
//! `teamclaw_gateway::ChannelStore` trait so channels persist external
//! actors, gateway sessions, and messages through the same Supabase
//! endpoints amuxd already uses for native sessions.

use async_trait::async_trait;
use std::sync::Arc;

use teamclaw_gateway::{AttachmentRecord, ChannelStore, EnsureSessionOutcome, StoreError};

use crate::supabase::SupabaseClient;

pub struct AmuxdChannelStore {
    pub client: Arc<SupabaseClient>,
}

#[async_trait]
impl ChannelStore for AmuxdChannelStore {
    async fn ensure_external_actor(
        &self,
        team_id: &str,
        source: &str,
        source_id: &str,
        display_name: &str,
    ) -> Result<String, StoreError> {
        self.client
            .rpc_upsert_external_actor(team_id, source, source_id, display_name)
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))
    }

    async fn ensure_session(
        &self,
        team_id: &str,
        binding: &str,
        title: &str,
        primary_agent_actor_id: &str,
        owner_member_actor_ids: &[String],
        participant_actor_ids: &[String],
    ) -> Result<EnsureSessionOutcome, StoreError> {
        let (session_id, acp_session_id, created) = self
            .client
            .rpc_ensure_gateway_session(
                team_id,
                binding,
                title,
                primary_agent_actor_id,
                owner_member_actor_ids,
                participant_actor_ids,
            )
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))?;
        Ok(EnsureSessionOutcome {
            session_id,
            acp_session_id,
            created,
        })
    }

    async fn record_message(
        &self,
        session_id: &str,
        sender_actor_id: &str,
        content: &str,
        external_message_id: Option<&str>,
    ) -> Result<String, StoreError> {
        self.client
            .insert_gateway_message(session_id, sender_actor_id, content, external_message_id)
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))
    }

    async fn record_message_with_attachments(
        &self,
        session_id: &str,
        sender_actor_id: &str,
        content: &str,
        external_message_id: Option<&str>,
        attachments: Vec<AttachmentRecord>,
    ) -> Result<String, StoreError> {
        let json_attachments: Vec<serde_json::Value> = attachments
            .into_iter()
            .map(|a| {
                serde_json::json!({
                    "filename": a.filename,
                    "mime": a.mime,
                    "size": a.size,
                    "bucket_path": a.bucket_path,
                    "local_path": a.local_path,
                })
            })
            .collect();

        self.client
            .insert_gateway_message_with_attachments(
                session_id,
                sender_actor_id,
                content,
                external_message_id,
                serde_json::Value::Array(json_attachments),
            )
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))
    }

    async fn upload_attachment(
        &self,
        bucket_path: &str,
        bytes: Vec<u8>,
        mime: &str,
    ) -> Result<String, StoreError> {
        self.client
            .upload_attachment_bytes(bucket_path, bytes, mime)
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))
    }

    async fn add_participant(
        &self,
        session_id: &str,
        actor_id: &str,
    ) -> Result<(), StoreError> {
        self.client
            .upsert_session_participant(session_id, actor_id)
            .await
            .map_err(|e| StoreError::Supabase(e.to_string()))
    }
}
