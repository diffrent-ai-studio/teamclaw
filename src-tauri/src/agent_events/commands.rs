use super::db::{AgentEventStore, AgentRuntimeEventRow};
use std::sync::Arc;
use tokio::sync::Mutex;

/// Managed state wrapper for AgentEventStore.
pub struct AgentEventState {
    pub db: Arc<Mutex<Option<AgentEventStore>>>,
}

impl Default for AgentEventState {
    fn default() -> Self {
        Self {
            db: Arc::new(Mutex::new(None)),
        }
    }
}

/// Helper to get (or lazily initialize) the AgentEventStore.
async fn get_db(state: &AgentEventState) -> Result<AgentEventStore, String> {
    let mut db_lock = state.db.lock().await;
    if let Some(ref db) = *db_lock {
        return Ok(db.clone());
    }

    // Initialize the database at ~/.teamclaw/agent-events.db
    let home = dirs_next().ok_or("Failed to determine home directory")?;
    let db_path = home
        .join(crate::commands::TEAMCLAW_DIR)
        .join("agent-events.db");
    let db = AgentEventStore::new(&db_path).await?;
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

// ─── Tauri Commands ──────────────────────────────────────────────────────

/// Upsert a non-canonical agent runtime event into the local libsql cache.
/// Idempotent: duplicate envelope receipts (same id) overwrite the row.
#[tauri::command]
pub async fn agent_runtime_event_insert(
    state: tauri::State<'_, AgentEventState>,
    record: AgentRuntimeEventRow,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.insert(&record).await
}

/// Load all cached agent runtime events for a session, ordered by created_at ASC.
#[tauri::command]
pub async fn agent_runtime_event_load(
    state: tauri::State<'_, AgentEventState>,
    session_id: String,
) -> Result<Vec<AgentRuntimeEventRow>, String> {
    let db = get_db(&state).await?;
    db.load_by_session(&session_id).await
}

/// Delete the oldest rows, keeping at most `max_rows` newest entries (default 5000).
#[tauri::command]
pub async fn agent_runtime_event_prune(
    state: tauri::State<'_, AgentEventState>,
    max_rows: Option<i64>,
) -> Result<(), String> {
    let db = get_db(&state).await?;
    db.prune(max_rows.unwrap_or(5000)).await
}
