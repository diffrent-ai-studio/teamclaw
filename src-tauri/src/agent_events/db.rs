use libsql::{params, Builder, Connection};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

// ─── Data types ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentRuntimeEventRow {
    pub id: String,
    pub session_id: String,
    pub turn_id: Option<String>,
    pub sender_actor_id: Option<String>,
    pub kind: String,
    pub content: String,
    pub metadata_json: Option<String>,
    pub model: Option<String>,
    pub created_at: String, // ISO 8601 timestamp
}

// ─── Database ────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AgentEventStore {
    conn: Arc<Mutex<Connection>>,
}

impl AgentEventStore {
    /// Create a new AgentEventStore at the given path (e.g. ~/.teamclaw/agent-events.db).
    pub async fn new(db_path: &Path) -> Result<Self, String> {
        // Ensure parent directory exists
        if let Some(parent) = db_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| format!("Failed to create agent-events db directory: {}", e))?;
        }

        let db_path_str = db_path.to_string_lossy().to_string();
        let db = Builder::new_local(db_path_str)
            .build()
            .await
            .map_err(|e| format!("Failed to open agent-events database: {}", e))?;
        let conn = db
            .connect()
            .map_err(|e| format!("Failed to connect to agent-events database: {}", e))?;

        let instance = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        instance.migrate().await?;
        Ok(instance)
    }

    /// Run database migrations (idempotent).
    pub async fn migrate(&self) -> Result<(), String> {
        let conn = self.conn.lock().await;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS agent_runtime_event (
                id              TEXT PRIMARY KEY,
                session_id      TEXT NOT NULL,
                turn_id         TEXT,
                sender_actor_id TEXT,
                kind            TEXT NOT NULL,
                content         TEXT NOT NULL,
                metadata_json   TEXT,
                model           TEXT,
                created_at      TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create agent_runtime_event table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_agent_runtime_event_session
               ON agent_runtime_event(session_id, created_at)",
            (),
        )
        .await
        .ok();

        Ok(())
    }

    /// Upsert an event row (idempotent on duplicate id).
    pub async fn insert(&self, record: &AgentRuntimeEventRow) -> Result<(), String> {
        let conn = self.conn.lock().await;
        conn.execute(
            "INSERT INTO agent_runtime_event
                (id, session_id, turn_id, sender_actor_id, kind, content, metadata_json, model, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                session_id      = excluded.session_id,
                turn_id         = excluded.turn_id,
                sender_actor_id = excluded.sender_actor_id,
                kind            = excluded.kind,
                content         = excluded.content,
                metadata_json   = excluded.metadata_json,
                model           = excluded.model,
                created_at      = excluded.created_at",
            params![
                record.id.clone(),
                record.session_id.clone(),
                record.turn_id.clone().unwrap_or_default(),
                record.sender_actor_id.clone().unwrap_or_default(),
                record.kind.clone(),
                record.content.clone(),
                record.metadata_json.clone().unwrap_or_default(),
                record.model.clone().unwrap_or_default(),
                record.created_at.clone()
            ],
        )
        .await
        .map_err(|e| format!("Failed to insert agent_runtime_event: {}", e))?;
        Ok(())
    }

    /// Load all events for a session, ordered by created_at ASC.
    pub async fn load_by_session(
        &self,
        session_id: &str,
    ) -> Result<Vec<AgentRuntimeEventRow>, String> {
        let conn = self.conn.lock().await;
        let mut rows = conn
            .query(
                "SELECT id, session_id, turn_id, sender_actor_id, kind, content, metadata_json, model, created_at
                 FROM agent_runtime_event
                 WHERE session_id = ?1
                 ORDER BY created_at ASC",
                params![session_id.to_string()],
            )
            .await
            .map_err(|e| format!("Failed to query agent_runtime_event: {}", e))?;

        let mut events = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("Failed to read agent_runtime_event row: {}", e))?
        {
            events.push(AgentRuntimeEventRow {
                id: row.get::<String>(0).unwrap_or_default(),
                session_id: row.get::<String>(1).unwrap_or_default(),
                turn_id: row.get::<String>(2).ok().filter(|s| !s.is_empty()),
                sender_actor_id: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                kind: row.get::<String>(4).unwrap_or_default(),
                content: row.get::<String>(5).unwrap_or_default(),
                metadata_json: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                model: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(8).unwrap_or_default(),
            });
        }
        Ok(events)
    }

    /// Delete the oldest rows, keeping at most `max_rows` newest entries.
    pub async fn prune(&self, max_rows: i64) -> Result<(), String> {
        let conn = self.conn.lock().await;
        conn.execute(
            "DELETE FROM agent_runtime_event WHERE id IN (
                SELECT id FROM agent_runtime_event ORDER BY created_at DESC LIMIT -1 OFFSET ?1
            )",
            params![max_rows],
        )
        .await
        .ok();
        Ok(())
    }
}
