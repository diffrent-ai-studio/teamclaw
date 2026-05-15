use libsql::{params, Builder, Connection, Value};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Convert an `Option<String>` to a libsql `Value`, producing `Value::Null` for `None`
/// and `Value::Text(s)` for `Some(s)`.  This is the correct way to insert nullable
/// TEXT columns so that SQLite sees NULL (not an empty string).
fn opt_val(v: &Option<String>) -> Value {
    match v {
        Some(s) => Value::Text(s.clone()),
        None => Value::Null,
    }
}

// ─── Row types ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActorRow {
    pub id: String,
    pub team_id: String,
    pub actor_type: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub member_status: Option<String>,
    pub agent_status: Option<String>,
    pub metadata_json: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRow {
    pub id: String,
    pub team_id: String,
    pub title: Option<String>,
    pub mode: Option<String>,
    pub primary_agent_id: Option<String>,
    pub idea_id: Option<String>,
    pub summary: Option<String>,
    pub last_message_preview: Option<String>,
    pub last_message_at: Option<String>,
    pub created_by: Option<String>,
    pub metadata_json: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionParticipantRow {
    pub id: String,
    pub session_id: String,
    pub actor_id: String,
    pub joined_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageRow {
    pub id: String,
    pub team_id: String,
    pub session_id: String,
    pub turn_id: Option<String>,
    pub sender_actor_id: Option<String>,
    pub reply_to_message_id: Option<String>,
    pub kind: String,
    pub content: String,
    pub metadata_json: Option<String>,
    pub model: Option<String>,
    pub mentions_json: Option<String>,
    pub origin: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaRow {
    pub id: String,
    pub team_id: String,
    pub workspace_id: Option<String>,
    pub parent_id: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub status: Option<String>,
    pub created_by: Option<String>,
    pub archived: i64,
    pub metadata_json: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimRow {
    pub id: String,
    pub idea_id: String,
    pub actor_id: String,
    pub claimed_at: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubmissionRow {
    pub id: String,
    pub idea_id: String,
    pub actor_id: String,
    pub content: Option<String>,
    pub submitted_at: String,
    pub created_at: String,
    pub updated_at: String,
    pub deleted_at: Option<String>,
    pub synced_at: String,
}

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
    pub created_at: String,
}

// ─── Store ────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct LocalCacheStore {
    conn: Arc<Mutex<Connection>>,
}

impl LocalCacheStore {
    // TODO(migrate-orphan): The old ~/.teamclaw/agent-events.db is left alone.
    // A future cleanup pass can delete it once all users have updated past this version.

    /// Create (or open) the local cache database at the given path.
    pub async fn new(db_path: &Path) -> Result<Self, String> {
        if let Some(parent) = db_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| format!("Failed to create local-cache db directory: {}", e))?;
        }

        let db_path_str = db_path.to_string_lossy().to_string();
        let db = Builder::new_local(db_path_str)
            .build()
            .await
            .map_err(|e| format!("Failed to open local-cache database: {}", e))?;
        let conn = db
            .connect()
            .map_err(|e| format!("Failed to connect to local-cache database: {}", e))?;

        let instance = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        instance.migrate().await?;
        Ok(instance)
    }

    /// Get a locked reference to the raw connection (rarely needed externally).
    pub async fn conn(&self) -> tokio::sync::MutexGuard<'_, Connection> {
        self.conn.lock().await
    }

    /// Run all DDL migrations (idempotent).
    async fn migrate(&self) -> Result<(), String> {
        let conn = self.conn.lock().await;

        // ── actor ─────────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS actor (
                id            TEXT PRIMARY KEY,
                team_id       TEXT NOT NULL,
                actor_type    TEXT NOT NULL,
                display_name  TEXT NOT NULL,
                avatar_url    TEXT,
                member_status TEXT,
                agent_status  TEXT,
                metadata_json TEXT,
                created_at    TEXT NOT NULL,
                updated_at    TEXT NOT NULL,
                deleted_at    TEXT,
                synced_at     TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create actor table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_actor_team ON actor(team_id)",
            (),
        )
        .await
        .ok();

        // ── session ───────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS session (
                id                   TEXT PRIMARY KEY,
                team_id              TEXT NOT NULL,
                title                TEXT,
                mode                 TEXT,
                primary_agent_id     TEXT,
                idea_id              TEXT,
                summary              TEXT,
                last_message_preview TEXT,
                last_message_at      TEXT,
                created_by           TEXT,
                metadata_json        TEXT,
                created_at           TEXT NOT NULL,
                updated_at           TEXT NOT NULL,
                deleted_at           TEXT,
                synced_at            TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create session table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_session_team ON session(team_id, last_message_at)",
            (),
        )
        .await
        .ok();

        // ── session_participant ────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS session_participant (
                id         TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                actor_id   TEXT NOT NULL,
                joined_at  TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                synced_at  TEXT NOT NULL,
                UNIQUE(session_id, actor_id)
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create session_participant table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_sp_session ON session_participant(session_id)",
            (),
        )
        .await
        .ok();

        // ── message ───────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS message (
                id                  TEXT PRIMARY KEY,
                team_id             TEXT NOT NULL,
                session_id          TEXT NOT NULL,
                turn_id             TEXT,
                sender_actor_id     TEXT,
                reply_to_message_id TEXT,
                kind                TEXT NOT NULL,
                content             TEXT NOT NULL,
                metadata_json       TEXT,
                model               TEXT,
                mentions_json       TEXT,
                origin              TEXT NOT NULL,
                created_at          TEXT NOT NULL,
                updated_at          TEXT NOT NULL,
                deleted_at          TEXT,
                synced_at           TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create message table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_message_session ON message(session_id, created_at)",
            (),
        )
        .await
        .ok();

        // ── idea ──────────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS idea (
                id            TEXT PRIMARY KEY,
                team_id       TEXT NOT NULL,
                workspace_id  TEXT,
                parent_id     TEXT,
                title         TEXT NOT NULL,
                description   TEXT,
                status        TEXT,
                created_by    TEXT,
                archived      INTEGER NOT NULL DEFAULT 0,
                metadata_json TEXT,
                created_at    TEXT NOT NULL,
                updated_at    TEXT NOT NULL,
                deleted_at    TEXT,
                synced_at     TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create idea table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_idea_team ON idea(team_id)",
            (),
        )
        .await
        .ok();

        // ── claim ─────────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS claim (
                id         TEXT PRIMARY KEY,
                idea_id    TEXT NOT NULL,
                actor_id   TEXT NOT NULL,
                claimed_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                synced_at  TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create claim table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_claim_idea ON claim(idea_id)",
            (),
        )
        .await
        .ok();

        // ── submission ────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS submission (
                id           TEXT PRIMARY KEY,
                idea_id      TEXT NOT NULL,
                actor_id     TEXT NOT NULL,
                content      TEXT,
                submitted_at TEXT NOT NULL,
                created_at   TEXT NOT NULL,
                updated_at   TEXT NOT NULL,
                deleted_at   TEXT,
                synced_at    TEXT NOT NULL
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create submission table: {}", e))?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_submission_idea ON submission(idea_id)",
            (),
        )
        .await
        .ok();

        // ── agent_runtime_event ───────────────────────────────────────────
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
            "CREATE INDEX IF NOT EXISTS idx_are_session ON agent_runtime_event(session_id, created_at)",
            (),
        )
        .await
        .ok();

        // ── sync_state ────────────────────────────────────────────────────
        conn.execute(
            "CREATE TABLE IF NOT EXISTS sync_state (
                table_name   TEXT NOT NULL,
                team_id      TEXT NOT NULL,
                last_sync_at TEXT NOT NULL,
                PRIMARY KEY (table_name, team_id)
            )",
            (),
        )
        .await
        .map_err(|e| format!("Failed to create sync_state table: {}", e))?;

        Ok(())
    }

    // ─── actor ────────────────────────────────────────────────────────────

    pub async fn actor_upsert_batch(&self, rows: &[ActorRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO actor
                    (id, team_id, actor_type, display_name, avatar_url, member_status,
                     agent_status, metadata_json, created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)
                 ON CONFLICT(id) DO UPDATE SET
                    team_id       = excluded.team_id,
                    actor_type    = excluded.actor_type,
                    display_name  = excluded.display_name,
                    avatar_url    = excluded.avatar_url,
                    member_status = excluded.member_status,
                    agent_status  = excluded.agent_status,
                    metadata_json = excluded.metadata_json,
                    created_at    = excluded.created_at,
                    updated_at    = excluded.updated_at,
                    deleted_at    = excluded.deleted_at,
                    synced_at     = excluded.synced_at
                 WHERE excluded.updated_at >= actor.updated_at",
                params![
                    r.id.clone(),
                    r.team_id.clone(),
                    r.actor_type.clone(),
                    r.display_name.clone(),
                    opt_val(&r.avatar_url),
                    opt_val(&r.member_status),
                    opt_val(&r.agent_status),
                    opt_val(&r.metadata_json),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("actor_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn actor_load_team(
        &self,
        team_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<ActorRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, team_id, actor_type, display_name, avatar_url, member_status,
                    agent_status, metadata_json, created_at, updated_at, deleted_at, synced_at
             FROM actor WHERE team_id = ?1"
        } else {
            "SELECT id, team_id, actor_type, display_name, avatar_url, member_status,
                    agent_status, metadata_json, created_at, updated_at, deleted_at, synced_at
             FROM actor WHERE team_id = ?1 AND deleted_at IS NULL"
        };
        let mut rows = conn
            .query(sql, params![team_id.to_string()])
            .await
            .map_err(|e| format!("actor_load_team: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("actor_load_team row: {}", e))?
        {
            result.push(ActorRow {
                id: row.get::<String>(0).unwrap_or_default(),
                team_id: row.get::<String>(1).unwrap_or_default(),
                actor_type: row.get::<String>(2).unwrap_or_default(),
                display_name: row.get::<String>(3).unwrap_or_default(),
                avatar_url: row.get::<String>(4).ok().filter(|s| !s.is_empty()),
                member_status: row.get::<String>(5).ok().filter(|s| !s.is_empty()),
                agent_status: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                metadata_json: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(8).unwrap_or_default(),
                updated_at: row.get::<String>(9).unwrap_or_default(),
                deleted_at: row.get::<String>(10).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(11).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    /// Load actor rows by a list of IDs (non-deleted only).
    /// Returns an empty vec if `ids` is empty or none match.
    pub async fn actor_load_by_ids(&self, ids: &[String]) -> Result<Vec<ActorRow>, String> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.conn.lock().await;
        // Build "?,?,?" placeholders
        let placeholders = ids
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT id, team_id, actor_type, display_name, avatar_url, member_status,
                    agent_status, metadata_json, created_at, updated_at, deleted_at, synced_at
             FROM actor WHERE id IN ({}) AND deleted_at IS NULL",
            placeholders
        );
        let bind_vals: Vec<Value> = ids.iter().map(|s| Value::Text(s.clone())).collect();
        let mut rows = conn
            .query(&sql, bind_vals)
            .await
            .map_err(|e| format!("actor_load_by_ids: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("actor_load_by_ids row: {}", e))?
        {
            result.push(ActorRow {
                id: row.get::<String>(0).unwrap_or_default(),
                team_id: row.get::<String>(1).unwrap_or_default(),
                actor_type: row.get::<String>(2).unwrap_or_default(),
                display_name: row.get::<String>(3).unwrap_or_default(),
                avatar_url: row.get::<String>(4).ok().filter(|s| !s.is_empty()),
                member_status: row.get::<String>(5).ok().filter(|s| !s.is_empty()),
                agent_status: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                metadata_json: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(8).unwrap_or_default(),
                updated_at: row.get::<String>(9).unwrap_or_default(),
                deleted_at: row.get::<String>(10).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(11).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn actor_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE actor SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("actor_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── session ──────────────────────────────────────────────────────────

    pub async fn session_upsert_batch(&self, rows: &[SessionRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO session
                    (id, team_id, title, mode, primary_agent_id, idea_id, summary,
                     last_message_preview, last_message_at, created_by, metadata_json,
                     created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15)
                 ON CONFLICT(id) DO UPDATE SET
                    team_id              = excluded.team_id,
                    title                = excluded.title,
                    mode                 = excluded.mode,
                    primary_agent_id     = excluded.primary_agent_id,
                    idea_id              = excluded.idea_id,
                    summary              = excluded.summary,
                    last_message_preview = excluded.last_message_preview,
                    last_message_at      = excluded.last_message_at,
                    created_by           = excluded.created_by,
                    metadata_json        = excluded.metadata_json,
                    created_at           = excluded.created_at,
                    updated_at           = excluded.updated_at,
                    deleted_at           = excluded.deleted_at,
                    synced_at            = excluded.synced_at
                 WHERE excluded.updated_at >= session.updated_at",
                params![
                    r.id.clone(),
                    r.team_id.clone(),
                    opt_val(&r.title),
                    opt_val(&r.mode),
                    opt_val(&r.primary_agent_id),
                    opt_val(&r.idea_id),
                    opt_val(&r.summary),
                    opt_val(&r.last_message_preview),
                    opt_val(&r.last_message_at),
                    opt_val(&r.created_by),
                    opt_val(&r.metadata_json),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("session_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn session_load_team(
        &self,
        team_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<SessionRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, team_id, title, mode, primary_agent_id, idea_id, summary,
                    last_message_preview, last_message_at, created_by, metadata_json,
                    created_at, updated_at, deleted_at, synced_at
             FROM session WHERE team_id = ?1 ORDER BY last_message_at DESC"
        } else {
            "SELECT id, team_id, title, mode, primary_agent_id, idea_id, summary,
                    last_message_preview, last_message_at, created_by, metadata_json,
                    created_at, updated_at, deleted_at, synced_at
             FROM session WHERE team_id = ?1 AND deleted_at IS NULL ORDER BY last_message_at DESC"
        };
        let mut rows = conn
            .query(sql, params![team_id.to_string()])
            .await
            .map_err(|e| format!("session_load_team: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("session_load_team row: {}", e))?
        {
            result.push(SessionRow {
                id: row.get::<String>(0).unwrap_or_default(),
                team_id: row.get::<String>(1).unwrap_or_default(),
                title: row.get::<String>(2).ok().filter(|s| !s.is_empty()),
                mode: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                primary_agent_id: row.get::<String>(4).ok().filter(|s| !s.is_empty()),
                idea_id: row.get::<String>(5).ok().filter(|s| !s.is_empty()),
                summary: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                last_message_preview: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                last_message_at: row.get::<String>(8).ok().filter(|s| !s.is_empty()),
                created_by: row.get::<String>(9).ok().filter(|s| !s.is_empty()),
                metadata_json: row.get::<String>(10).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(11).unwrap_or_default(),
                updated_at: row.get::<String>(12).unwrap_or_default(),
                deleted_at: row.get::<String>(13).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(14).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn session_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE session SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("session_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── session_participant ──────────────────────────────────────────────

    pub async fn session_participant_upsert_batch(
        &self,
        rows: &[SessionParticipantRow],
    ) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                // Conflict on the natural key (session_id, actor_id) because
                // session-create writes a synthesized "sess:actor" id locally
                // before Supabase sync brings the real UUID. Both refer to
                // the same logical participant — keep the latest id.
                "INSERT INTO session_participant
                    (id, session_id, actor_id, joined_at, created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(session_id, actor_id) DO UPDATE SET
                    id         = excluded.id,
                    joined_at  = excluded.joined_at,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at,
                    synced_at  = excluded.synced_at
                 WHERE excluded.updated_at >= session_participant.updated_at",
                params![
                    r.id.clone(),
                    r.session_id.clone(),
                    r.actor_id.clone(),
                    opt_val(&r.joined_at),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("session_participant_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn session_participant_load_session(
        &self,
        session_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<SessionParticipantRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, session_id, actor_id, joined_at, created_at, updated_at, deleted_at, synced_at
             FROM session_participant WHERE session_id = ?1"
        } else {
            "SELECT id, session_id, actor_id, joined_at, created_at, updated_at, deleted_at, synced_at
             FROM session_participant WHERE session_id = ?1 AND deleted_at IS NULL"
        };
        let mut rows = conn
            .query(sql, params![session_id.to_string()])
            .await
            .map_err(|e| format!("session_participant_load_session: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("session_participant_load_session row: {}", e))?
        {
            result.push(SessionParticipantRow {
                id: row.get::<String>(0).unwrap_or_default(),
                session_id: row.get::<String>(1).unwrap_or_default(),
                actor_id: row.get::<String>(2).unwrap_or_default(),
                joined_at: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(4).unwrap_or_default(),
                updated_at: row.get::<String>(5).unwrap_or_default(),
                deleted_at: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(7).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn session_participant_soft_delete(
        &self,
        id: &str,
        deleted_at: &str,
    ) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE session_participant SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("session_participant_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── message ──────────────────────────────────────────────────────────

    pub async fn message_upsert_batch(&self, rows: &[MessageRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO message
                    (id, team_id, session_id, turn_id, sender_actor_id, reply_to_message_id,
                     kind, content, metadata_json, model, mentions_json, origin,
                     created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)
                 ON CONFLICT(id) DO UPDATE SET
                    team_id             = excluded.team_id,
                    session_id          = excluded.session_id,
                    turn_id             = excluded.turn_id,
                    sender_actor_id     = excluded.sender_actor_id,
                    reply_to_message_id = excluded.reply_to_message_id,
                    kind                = excluded.kind,
                    content             = excluded.content,
                    metadata_json       = excluded.metadata_json,
                    model               = excluded.model,
                    mentions_json       = excluded.mentions_json,
                    origin              = excluded.origin,
                    created_at          = excluded.created_at,
                    updated_at          = excluded.updated_at,
                    deleted_at          = excluded.deleted_at,
                    synced_at           = excluded.synced_at
                 WHERE excluded.updated_at >= message.updated_at",
                params![
                    r.id.clone(),
                    r.team_id.clone(),
                    r.session_id.clone(),
                    opt_val(&r.turn_id),
                    opt_val(&r.sender_actor_id),
                    opt_val(&r.reply_to_message_id),
                    r.kind.clone(),
                    r.content.clone(),
                    opt_val(&r.metadata_json),
                    opt_val(&r.model),
                    opt_val(&r.mentions_json),
                    r.origin.clone(),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("message_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn message_load_session(
        &self,
        session_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<MessageRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, team_id, session_id, turn_id, sender_actor_id, reply_to_message_id,
                    kind, content, metadata_json, model, mentions_json, origin,
                    created_at, updated_at, deleted_at, synced_at
             FROM message WHERE session_id = ?1 ORDER BY created_at ASC"
        } else {
            "SELECT id, team_id, session_id, turn_id, sender_actor_id, reply_to_message_id,
                    kind, content, metadata_json, model, mentions_json, origin,
                    created_at, updated_at, deleted_at, synced_at
             FROM message WHERE session_id = ?1 AND deleted_at IS NULL ORDER BY created_at ASC"
        };
        let mut rows = conn
            .query(sql, params![session_id.to_string()])
            .await
            .map_err(|e| format!("message_load_session: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("message_load_session row: {}", e))?
        {
            result.push(MessageRow {
                id: row.get::<String>(0).unwrap_or_default(),
                team_id: row.get::<String>(1).unwrap_or_default(),
                session_id: row.get::<String>(2).unwrap_or_default(),
                turn_id: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                sender_actor_id: row.get::<String>(4).ok().filter(|s| !s.is_empty()),
                reply_to_message_id: row.get::<String>(5).ok().filter(|s| !s.is_empty()),
                kind: row.get::<String>(6).unwrap_or_default(),
                content: row.get::<String>(7).unwrap_or_default(),
                metadata_json: row.get::<String>(8).ok().filter(|s| !s.is_empty()),
                model: row.get::<String>(9).ok().filter(|s| !s.is_empty()),
                mentions_json: row.get::<String>(10).ok().filter(|s| !s.is_empty()),
                origin: row.get::<String>(11).unwrap_or_default(),
                created_at: row.get::<String>(12).unwrap_or_default(),
                updated_at: row.get::<String>(13).unwrap_or_default(),
                deleted_at: row.get::<String>(14).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(15).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn message_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE message SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("message_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── idea ─────────────────────────────────────────────────────────────

    pub async fn idea_upsert_batch(&self, rows: &[IdeaRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO idea
                    (id, team_id, workspace_id, parent_id, title, description, status,
                     created_by, archived, metadata_json, created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
                 ON CONFLICT(id) DO UPDATE SET
                    team_id       = excluded.team_id,
                    workspace_id  = excluded.workspace_id,
                    parent_id     = excluded.parent_id,
                    title         = excluded.title,
                    description   = excluded.description,
                    status        = excluded.status,
                    created_by    = excluded.created_by,
                    archived      = excluded.archived,
                    metadata_json = excluded.metadata_json,
                    created_at    = excluded.created_at,
                    updated_at    = excluded.updated_at,
                    deleted_at    = excluded.deleted_at,
                    synced_at     = excluded.synced_at
                 WHERE excluded.updated_at >= idea.updated_at",
                params![
                    r.id.clone(),
                    r.team_id.clone(),
                    opt_val(&r.workspace_id),
                    opt_val(&r.parent_id),
                    r.title.clone(),
                    opt_val(&r.description),
                    opt_val(&r.status),
                    opt_val(&r.created_by),
                    r.archived,
                    opt_val(&r.metadata_json),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("idea_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn idea_load_team(
        &self,
        team_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<IdeaRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, team_id, workspace_id, parent_id, title, description, status,
                    created_by, archived, metadata_json, created_at, updated_at, deleted_at, synced_at
             FROM idea WHERE team_id = ?1"
        } else {
            "SELECT id, team_id, workspace_id, parent_id, title, description, status,
                    created_by, archived, metadata_json, created_at, updated_at, deleted_at, synced_at
             FROM idea WHERE team_id = ?1 AND deleted_at IS NULL"
        };
        let mut rows = conn
            .query(sql, params![team_id.to_string()])
            .await
            .map_err(|e| format!("idea_load_team: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("idea_load_team row: {}", e))?
        {
            result.push(IdeaRow {
                id: row.get::<String>(0).unwrap_or_default(),
                team_id: row.get::<String>(1).unwrap_or_default(),
                workspace_id: row.get::<String>(2).ok().filter(|s| !s.is_empty()),
                parent_id: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                title: row.get::<String>(4).unwrap_or_default(),
                description: row.get::<String>(5).ok().filter(|s| !s.is_empty()),
                status: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                created_by: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                archived: row.get::<i64>(8).unwrap_or(0),
                metadata_json: row.get::<String>(9).ok().filter(|s| !s.is_empty()),
                created_at: row.get::<String>(10).unwrap_or_default(),
                updated_at: row.get::<String>(11).unwrap_or_default(),
                deleted_at: row.get::<String>(12).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(13).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn idea_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE idea SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("idea_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── claim ────────────────────────────────────────────────────────────

    pub async fn claim_upsert_batch(&self, rows: &[ClaimRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO claim
                    (id, idea_id, actor_id, claimed_at, created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(id) DO UPDATE SET
                    idea_id    = excluded.idea_id,
                    actor_id   = excluded.actor_id,
                    claimed_at = excluded.claimed_at,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at,
                    synced_at  = excluded.synced_at
                 WHERE excluded.updated_at >= claim.updated_at",
                params![
                    r.id.clone(),
                    r.idea_id.clone(),
                    r.actor_id.clone(),
                    r.claimed_at.clone(),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("claim_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn claim_load_idea(
        &self,
        idea_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<ClaimRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, idea_id, actor_id, claimed_at, created_at, updated_at, deleted_at, synced_at
             FROM claim WHERE idea_id = ?1"
        } else {
            "SELECT id, idea_id, actor_id, claimed_at, created_at, updated_at, deleted_at, synced_at
             FROM claim WHERE idea_id = ?1 AND deleted_at IS NULL"
        };
        let mut rows = conn
            .query(sql, params![idea_id.to_string()])
            .await
            .map_err(|e| format!("claim_load_idea: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("claim_load_idea row: {}", e))?
        {
            result.push(ClaimRow {
                id: row.get::<String>(0).unwrap_or_default(),
                idea_id: row.get::<String>(1).unwrap_or_default(),
                actor_id: row.get::<String>(2).unwrap_or_default(),
                claimed_at: row.get::<String>(3).unwrap_or_default(),
                created_at: row.get::<String>(4).unwrap_or_default(),
                updated_at: row.get::<String>(5).unwrap_or_default(),
                deleted_at: row.get::<String>(6).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(7).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn claim_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE claim SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("claim_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── submission ───────────────────────────────────────────────────────

    pub async fn submission_upsert_batch(&self, rows: &[SubmissionRow]) -> Result<(), String> {
        let conn = self.conn.lock().await;
        for r in rows {
            conn.execute(
                "INSERT INTO submission
                    (id, idea_id, actor_id, content, submitted_at, created_at, updated_at, deleted_at, synced_at)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
                 ON CONFLICT(id) DO UPDATE SET
                    idea_id      = excluded.idea_id,
                    actor_id     = excluded.actor_id,
                    content      = excluded.content,
                    submitted_at = excluded.submitted_at,
                    created_at   = excluded.created_at,
                    updated_at   = excluded.updated_at,
                    deleted_at   = excluded.deleted_at,
                    synced_at    = excluded.synced_at
                 WHERE excluded.updated_at >= submission.updated_at",
                params![
                    r.id.clone(),
                    r.idea_id.clone(),
                    r.actor_id.clone(),
                    opt_val(&r.content),
                    r.submitted_at.clone(),
                    r.created_at.clone(),
                    r.updated_at.clone(),
                    opt_val(&r.deleted_at),
                    r.synced_at.clone()
                ],
            )
            .await
            .map_err(|e| format!("submission_upsert_batch: {}", e))?;
        }
        Ok(())
    }

    pub async fn submission_load_idea(
        &self,
        idea_id: &str,
        include_deleted: bool,
    ) -> Result<Vec<SubmissionRow>, String> {
        let conn = self.conn.lock().await;
        let sql = if include_deleted {
            "SELECT id, idea_id, actor_id, content, submitted_at, created_at, updated_at, deleted_at, synced_at
             FROM submission WHERE idea_id = ?1"
        } else {
            "SELECT id, idea_id, actor_id, content, submitted_at, created_at, updated_at, deleted_at, synced_at
             FROM submission WHERE idea_id = ?1 AND deleted_at IS NULL"
        };
        let mut rows = conn
            .query(sql, params![idea_id.to_string()])
            .await
            .map_err(|e| format!("submission_load_idea: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("submission_load_idea row: {}", e))?
        {
            result.push(SubmissionRow {
                id: row.get::<String>(0).unwrap_or_default(),
                idea_id: row.get::<String>(1).unwrap_or_default(),
                actor_id: row.get::<String>(2).unwrap_or_default(),
                content: row.get::<String>(3).ok().filter(|s| !s.is_empty()),
                submitted_at: row.get::<String>(4).unwrap_or_default(),
                created_at: row.get::<String>(5).unwrap_or_default(),
                updated_at: row.get::<String>(6).unwrap_or_default(),
                deleted_at: row.get::<String>(7).ok().filter(|s| !s.is_empty()),
                synced_at: row.get::<String>(8).unwrap_or_default(),
            });
        }
        Ok(result)
    }

    pub async fn submission_soft_delete(&self, id: &str, deleted_at: &str) -> Result<(), String> {
        let now = deleted_at.to_string();
        let conn = self.conn.lock().await;
        conn.execute(
            "UPDATE submission SET deleted_at = ?1, updated_at = ?1, synced_at = ?1 WHERE id = ?2",
            params![now, id.to_string()],
        )
        .await
        .map_err(|e| format!("submission_soft_delete: {}", e))?;
        Ok(())
    }

    // ─── agent_runtime_event ──────────────────────────────────────────────

    pub async fn agent_runtime_event_upsert(
        &self,
        row: &AgentRuntimeEventRow,
    ) -> Result<(), String> {
        let conn = self.conn.lock().await;
        conn.execute(
            "INSERT INTO agent_runtime_event
                (id, session_id, turn_id, sender_actor_id, kind, content, metadata_json, model, created_at)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
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
                row.id.clone(),
                row.session_id.clone(),
                opt_val(&row.turn_id),
                opt_val(&row.sender_actor_id),
                row.kind.clone(),
                row.content.clone(),
                opt_val(&row.metadata_json),
                opt_val(&row.model),
                row.created_at.clone()
            ],
        )
        .await
        .map_err(|e| format!("agent_runtime_event_upsert: {}", e))?;
        Ok(())
    }

    pub async fn agent_runtime_event_load_session(
        &self,
        session_id: &str,
    ) -> Result<Vec<AgentRuntimeEventRow>, String> {
        let conn = self.conn.lock().await;
        let mut rows = conn
            .query(
                "SELECT id, session_id, turn_id, sender_actor_id, kind, content,
                        metadata_json, model, created_at
                 FROM agent_runtime_event
                 WHERE session_id = ?1
                 ORDER BY created_at ASC",
                params![session_id.to_string()],
            )
            .await
            .map_err(|e| format!("agent_runtime_event_load_session: {}", e))?;
        let mut result = Vec::new();
        while let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("agent_runtime_event_load_session row: {}", e))?
        {
            result.push(AgentRuntimeEventRow {
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
        Ok(result)
    }

    pub async fn agent_runtime_event_prune(&self, max_rows: i64) -> Result<(), String> {
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

    // ─── sync watermark ───────────────────────────────────────────────────

    pub async fn watermark_get(
        &self,
        table_name: &str,
        team_id: &str,
    ) -> Result<Option<String>, String> {
        let conn = self.conn.lock().await;
        let mut rows = conn
            .query(
                "SELECT last_sync_at FROM sync_state WHERE table_name = ?1 AND team_id = ?2",
                params![table_name.to_string(), team_id.to_string()],
            )
            .await
            .map_err(|e| format!("watermark_get: {}", e))?;
        if let Some(row) = rows
            .next()
            .await
            .map_err(|e| format!("watermark_get row: {}", e))?
        {
            return Ok(row.get::<String>(0).ok());
        }
        Ok(None)
    }

    pub async fn watermark_set(
        &self,
        table_name: &str,
        team_id: &str,
        last_sync_at: &str,
    ) -> Result<(), String> {
        let conn = self.conn.lock().await;
        conn.execute(
            "INSERT INTO sync_state (table_name, team_id, last_sync_at)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(table_name, team_id) DO UPDATE SET last_sync_at = excluded.last_sync_at",
            params![
                table_name.to_string(),
                team_id.to_string(),
                last_sync_at.to_string()
            ],
        )
        .await
        .map_err(|e| format!("watermark_set: {}", e))?;
        Ok(())
    }

    // ─── clear_team ───────────────────────────────────────────────────────

    /// Wipe all cached data for a given team (used by global ↻ refresh in Settings).
    pub async fn clear_team(&self, team_id: &str) -> Result<(), String> {
        let conn = self.conn.lock().await;
        // Cascade order: leaf tables before parent tables
        conn.execute(
            "DELETE FROM claim WHERE idea_id IN (SELECT id FROM idea WHERE team_id = ?1)",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team claim: {}", e))?;

        conn.execute(
            "DELETE FROM submission WHERE idea_id IN (SELECT id FROM idea WHERE team_id = ?1)",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team submission: {}", e))?;

        conn.execute(
            "DELETE FROM session_participant WHERE session_id IN (SELECT id FROM session WHERE team_id = ?1)",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team session_participant: {}", e))?;

        conn.execute(
            "DELETE FROM message WHERE team_id = ?1",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team message: {}", e))?;

        conn.execute(
            "DELETE FROM idea WHERE team_id = ?1",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team idea: {}", e))?;

        conn.execute(
            "DELETE FROM session WHERE team_id = ?1",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team session: {}", e))?;

        conn.execute(
            "DELETE FROM actor WHERE team_id = ?1",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team actor: {}", e))?;

        conn.execute(
            "DELETE FROM sync_state WHERE team_id = ?1",
            params![team_id.to_string()],
        )
        .await
        .map_err(|e| format!("clear_team sync_state: {}", e))?;

        Ok(())
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    /// Returns (store, tempdir). Caller must hold `_dir` to keep the temp directory alive.
    async fn new_store() -> (LocalCacheStore, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.db");
        let store = LocalCacheStore::new(&path).await.unwrap();
        (store, dir)
    }

    fn actor(id: &str, team: &str, updated_at: &str) -> ActorRow {
        ActorRow {
            id: id.to_string(),
            team_id: team.to_string(),
            actor_type: "member".to_string(),
            display_name: "Test".to_string(),
            avatar_url: None,
            member_status: None,
            agent_status: None,
            metadata_json: None,
            created_at: "2024-01-01T00:00:00Z".to_string(),
            updated_at: updated_at.to_string(),
            deleted_at: None,
            synced_at: "2024-01-01T00:00:00Z".to_string(),
        }
    }

    #[tokio::test]
    async fn upsert_and_load_actor() {
        let (store, _dir) = new_store().await;
        let a = actor("a1", "team1", "2024-01-01T00:00:00Z");
        store.actor_upsert_batch(&[a.clone()]).await.unwrap();
        let loaded = store.actor_load_team("team1", false).await.unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].id, "a1");
    }

    #[tokio::test]
    async fn upsert_newer_wins_older_doesnt() {
        let (store, _dir) = new_store().await;
        // Insert with updated_at=2
        let new = actor("a2", "team1", "2024-01-02T00:00:00Z");
        store.actor_upsert_batch(&[new]).await.unwrap();
        // Now try to overwrite with updated_at=1 (should be ignored)
        let old = ActorRow {
            display_name: "OldName".to_string(),
            updated_at: "2024-01-01T00:00:00Z".to_string(),
            ..actor("a2", "team1", "2024-01-01T00:00:00Z")
        };
        store.actor_upsert_batch(&[old]).await.unwrap();
        let loaded = store.actor_load_team("team1", false).await.unwrap();
        assert_eq!(loaded.len(), 1);
        // Should still have the newer name ("Test"), not "OldName"
        assert_eq!(loaded[0].display_name, "Test");
    }

    #[tokio::test]
    async fn soft_delete_hides_by_default() {
        let (store, _dir) = new_store().await;
        let a = actor("a3", "team1", "2024-01-01T00:00:00Z");
        store.actor_upsert_batch(&[a]).await.unwrap();

        store
            .actor_soft_delete("a3", "2024-01-02T00:00:00Z")
            .await
            .unwrap();

        // exclude deleted (default)
        let visible = store.actor_load_team("team1", false).await.unwrap();
        assert_eq!(visible.len(), 0);

        // include deleted
        let all = store.actor_load_team("team1", true).await.unwrap();
        assert_eq!(all.len(), 1);
        assert!(all[0].deleted_at.is_some());
    }

    #[tokio::test]
    async fn watermark_round_trip() {
        let (store, _dir) = new_store().await;
        let before = store.watermark_get("actor", "team1").await.unwrap();
        assert!(before.is_none());

        store
            .watermark_set("actor", "team1", "2024-06-01T12:00:00Z")
            .await
            .unwrap();

        let after = store.watermark_get("actor", "team1").await.unwrap();
        assert_eq!(after.unwrap(), "2024-06-01T12:00:00Z");
    }

    #[tokio::test]
    async fn clear_team_wipes_only_that_team() {
        let (store, _dir) = new_store().await;
        let a = actor("a_teamA", "teamA", "2024-01-01T00:00:00Z");
        let b = actor("b_teamB", "teamB", "2024-01-01T00:00:00Z");
        store.actor_upsert_batch(&[a, b]).await.unwrap();

        store.clear_team("teamA").await.unwrap();

        let team_a = store.actor_load_team("teamA", true).await.unwrap();
        let team_b = store.actor_load_team("teamB", true).await.unwrap();

        assert_eq!(team_a.len(), 0, "teamA should be wiped");
        assert_eq!(team_b.len(), 1, "teamB should be untouched");
    }
}
