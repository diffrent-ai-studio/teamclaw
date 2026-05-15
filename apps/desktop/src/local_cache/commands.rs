use super::store::{
    ActorRow, AgentRuntimeEventRow, ClaimRow, IdeaRow, LocalCacheStore, MessageRow,
    SessionParticipantRow, SessionRow, SubmissionRow,
};
use std::sync::Arc;
use tokio::sync::Mutex;

// ─── Managed state ────────────────────────────────────────────────────────

pub struct LocalCacheState {
    pub db: Arc<Mutex<Option<LocalCacheStore>>>,
}

impl Default for LocalCacheState {
    fn default() -> Self {
        Self {
            db: Arc::new(Mutex::new(None)),
        }
    }
}

/// Lazily open the LocalCacheStore on first call.
async fn get_db(state: &LocalCacheState) -> Result<LocalCacheStore, String> {
    let mut db_lock = state.db.lock().await;
    if let Some(ref db) = *db_lock {
        return Ok(db.clone());
    }
    let home = dirs_next().ok_or("Failed to determine home directory")?;
    let db_path = home
        .join(crate::commands::TEAMCLAW_DIR)
        .join("local-cache.db");
    let db = LocalCacheStore::new(&db_path).await?;
    *db_lock = Some(db.clone());
    Ok(db)
}

fn dirs_next() -> Option<std::path::PathBuf> {
    std::env::var("HOME")
        .ok()
        .map(std::path::PathBuf::from)
        .or_else(|| {
            #[cfg(target_os = "windows")]
            {
                std::env::var("USERPROFILE")
                    .ok()
                    .map(std::path::PathBuf::from)
            }
            #[cfg(not(target_os = "windows"))]
            {
                None
            }
        })
}

// ─── actor commands ───────────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_actor_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<ActorRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.actor_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_actor_load_team(
    state: tauri::State<'_, LocalCacheState>,
    team_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<ActorRow>, String> {
    let db = get_db(&state).await?;
    db.actor_load_team(&team_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_actor_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.actor_soft_delete(&id, &deleted_at).await
}

#[tauri::command]
pub async fn local_cache_actor_load_by_ids(
    state: tauri::State<'_, LocalCacheState>,
    ids: Vec<String>,
) -> Result<Vec<ActorRow>, String> {
    let db = get_db(&state).await?;
    db.actor_load_by_ids(&ids).await
}

// ─── session commands ─────────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_session_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<SessionRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.session_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_session_load_team(
    state: tauri::State<'_, LocalCacheState>,
    team_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<SessionRow>, String> {
    let db = get_db(&state).await?;
    db.session_load_team(&team_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_session_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.session_soft_delete(&id, &deleted_at).await
}

// ─── session_participant commands ─────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_session_participant_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<SessionParticipantRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.session_participant_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_session_participant_load_session(
    state: tauri::State<'_, LocalCacheState>,
    session_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<SessionParticipantRow>, String> {
    let db = get_db(&state).await?;
    db.session_participant_load_session(&session_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_session_participant_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.session_participant_soft_delete(&id, &deleted_at).await
}

// ─── message commands ─────────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_message_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<MessageRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.message_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_message_load_session(
    state: tauri::State<'_, LocalCacheState>,
    session_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<MessageRow>, String> {
    let db = get_db(&state).await?;
    db.message_load_session(&session_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_message_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.message_soft_delete(&id, &deleted_at).await
}

// ─── idea commands ────────────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_idea_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<IdeaRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.idea_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_idea_load_team(
    state: tauri::State<'_, LocalCacheState>,
    team_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<IdeaRow>, String> {
    let db = get_db(&state).await?;
    db.idea_load_team(&team_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_idea_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.idea_soft_delete(&id, &deleted_at).await
}

// ─── claim commands ───────────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_claim_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<ClaimRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.claim_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_claim_load_idea(
    state: tauri::State<'_, LocalCacheState>,
    idea_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<ClaimRow>, String> {
    let db = get_db(&state).await?;
    db.claim_load_idea(&idea_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_claim_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.claim_soft_delete(&id, &deleted_at).await
}

// ─── submission commands ──────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_submission_upsert_batch(
    state: tauri::State<'_, LocalCacheState>,
    rows: Vec<SubmissionRow>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.submission_upsert_batch(&rows).await
}

#[tauri::command]
pub async fn local_cache_submission_load_idea(
    state: tauri::State<'_, LocalCacheState>,
    idea_id: String,
    include_deleted: Option<bool>,
) -> Result<Vec<SubmissionRow>, String> {
    let db = get_db(&state).await?;
    db.submission_load_idea(&idea_id, include_deleted.unwrap_or(false))
        .await
}

#[tauri::command]
pub async fn local_cache_submission_soft_delete(
    state: tauri::State<'_, LocalCacheState>,
    id: String,
    deleted_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.submission_soft_delete(&id, &deleted_at).await
}

// ─── agent_runtime_event commands ─────────────────────────────────────────

/// Upsert a single agent runtime event (idempotent on duplicate id).
#[tauri::command]
pub async fn local_cache_agent_runtime_event_insert(
    state: tauri::State<'_, LocalCacheState>,
    record: AgentRuntimeEventRow,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.agent_runtime_event_upsert(&record).await
}

/// Load all agent runtime events for a session, ordered by created_at ASC.
#[tauri::command]
pub async fn local_cache_agent_runtime_event_load(
    state: tauri::State<'_, LocalCacheState>,
    session_id: String,
) -> Result<Vec<AgentRuntimeEventRow>, String> {
    let db = get_db(&state).await?;
    db.agent_runtime_event_load_session(&session_id).await
}

/// Prune oldest rows, keeping at most `max_rows` entries (default 5000).
#[tauri::command]
pub async fn local_cache_agent_runtime_event_prune(
    state: tauri::State<'_, LocalCacheState>,
    max_rows: Option<i64>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.agent_runtime_event_prune(max_rows.unwrap_or(5000)).await
}

// ─── sync watermark commands ──────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_watermark_get(
    state: tauri::State<'_, LocalCacheState>,
    table_name: String,
    team_id: String,
) -> Result<Option<String>, String> {
    let db = get_db(&state).await?;
    db.watermark_get(&table_name, &team_id).await
}

#[tauri::command]
pub async fn local_cache_watermark_set(
    state: tauri::State<'_, LocalCacheState>,
    table_name: String,
    team_id: String,
    last_sync_at: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.watermark_set(&table_name, &team_id, &last_sync_at).await
}

// ─── clear_team command ───────────────────────────────────────────────────

#[tauri::command]
pub async fn local_cache_clear_team(
    state: tauri::State<'_, LocalCacheState>,
    team_id: String,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.clear_team(&team_id).await
}
