// Thin RPC client over `amuxd.sock`. The desktop app no longer runs the
// channel gateways itself — amuxd owns those instances and persists their
// config in `daemon.toml`. The three commands here just forward to amuxd.
//
// Cron and `introspect_api` still reach into the underlying
// `teamclaw_gateway::*` modules for direct send helpers (e.g.
// `gateway::email::send_notification_email`, `gateway::wecom::send_proactive_message`),
// so we keep `pub use teamclaw_gateway::*` to preserve their `crate::commands::gateway::*`
// import paths. Likewise we keep a slim `GatewayState` carrying just the
// shared `SessionMapping` (cron consumes it for session lookup); the legacy
// per-platform `*Gateway` slots that used to live here are gone.

pub use teamclaw_gateway::*;

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

/// Slim per-app state. The legacy `*Gateway` slots were removed (amuxd owns
/// those now); only the cross-component session map remains, used by the
/// cron scheduler for session-id <-> chat-target lookup.
pub struct GatewayState {
    pub shared_session_mapping: SessionMapping,
    pub session_initialized: Mutex<bool>,
}

impl Default for GatewayState {
    fn default() -> Self {
        Self {
            shared_session_mapping: SessionMapping::new(),
            session_initialized: Mutex::new(false),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelStatus {
    pub platform: String,
    pub enabled: bool,
    pub connected: bool,
    #[serde(default, rename = "last_error", alias = "lastError")]
    pub last_error: Option<String>,
}

fn sock_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("amux")
        .join("amuxd.sock")
}

/// List the six known channel platforms with their `enabled` / `connected`
/// state as reported by amuxd over `amuxd.sock`. Errors out clearly when the
/// daemon is not running so the UI can surface an "amuxd unreachable" state.
#[tauri::command]
pub async fn list_channels() -> Result<Vec<ChannelStatus>, String> {
    let mut s = UnixStream::connect(sock_path())
        .map_err(|e| format!("amuxd not reachable: {e}"))?;
    s.write_all(b"channel-status\n")
        .map_err(|e| format!("write failed: {e}"))?;
    s.shutdown(std::net::Shutdown::Write)
        .map_err(|e| format!("shutdown write half failed: {e}"))?;
    let mut buf = String::new();
    s.read_to_string(&mut buf)
        .map_err(|e| format!("read failed: {e}"))?;
    serde_json::from_str(buf.trim())
        .map_err(|e| format!("bad response from amuxd: {e} (body={buf:?})"))
}

/// Replace `daemon.toml`'s `[channels.<platform>]` section with the JSON in
/// `config_json` (one of the daemon's per-platform config structs). amuxd
/// auto-reloads the channel manager so the change takes effect immediately.
#[tauri::command]
pub async fn save_channel_config(platform: String, config_json: String) -> Result<(), String> {
    let mut s = UnixStream::connect(sock_path())
        .map_err(|e| format!("amuxd not reachable: {e}"))?;
    // Single-line JSON keeps the framing simple — the daemon reads exactly
    // three newline-terminated tokens off the sock.
    let single_line = config_json.replace('\n', " ");
    let payload = format!("channel-save\n{platform}\n{single_line}\n");
    s.write_all(payload.as_bytes())
        .map_err(|e| format!("write failed: {e}"))?;
    Ok(())
}

/// Tell amuxd to re-read `daemon.toml` and restart all channels. Cheap;
/// useful when the daemon-managed config file was edited out-of-band.
#[tauri::command]
pub async fn reload_channels() -> Result<(), String> {
    let mut s = UnixStream::connect(sock_path())
        .map_err(|e| format!("amuxd not reachable: {e}"))?;
    s.write_all(b"channel-reload\n")
        .map_err(|e| format!("write failed: {e}"))?;
    Ok(())
}

// ─── Workspace teamclaw.json helpers (not channel-specific) ───────────────────
//
// These four commands manage non-channel fields of the workspace-level
// `teamclaw.json` (shortcuts list, system prompt, UI locale). They lived in
// this module historically because the file-reader helper was here; rather
// than scatter them across new modules we keep them here as siblings of the
// new sock-RPC commands. The H1 channel rewrite intentionally leaves them
// untouched.

use tauri::State;

/// Load personal shortcuts from the workspace config file (teamclaw.json).
#[tauri::command]
pub fn load_shortcuts(
    window: tauri::WebviewWindow,
    registry: State<'_, crate::commands::window::WindowRegistry>,
    workspace_path: Option<String>,
) -> Result<Vec<serde_json::Value>, String> {
    let workspace_path =
        crate::commands::team::resolve_workspace_path(workspace_path, &window, &registry)?;
    let config = teamclaw_gateway::read_config(&workspace_path)?;
    let shortcuts = config
        .other
        .get("shortcuts")
        .cloned()
        .unwrap_or(serde_json::json!([]));
    Ok(shortcuts.as_array().cloned().unwrap_or_default())
}

/// Save personal shortcuts to the workspace config file (teamclaw.json).
#[tauri::command]
pub fn save_shortcuts(
    window: tauri::WebviewWindow,
    registry: State<'_, crate::commands::window::WindowRegistry>,
    nodes: Vec<serde_json::Value>,
    workspace_path: Option<String>,
) -> Result<(), String> {
    let workspace_path =
        crate::commands::team::resolve_workspace_path(workspace_path, &window, &registry)?;
    let mut config = teamclaw_gateway::read_config(&workspace_path)?;
    config
        .other
        .insert("shortcuts".to_string(), serde_json::json!(nodes));
    teamclaw_gateway::write_config(&workspace_path, &config)
}

/// Load the per-workspace system prompt from teamclaw.json. Returns "" if unset.
#[tauri::command]
pub fn load_system_prompt(
    window: tauri::WebviewWindow,
    registry: State<'_, crate::commands::window::WindowRegistry>,
    workspace_path: Option<String>,
) -> Result<String, String> {
    let workspace_path =
        crate::commands::team::resolve_workspace_path(workspace_path, &window, &registry)?;
    let config = teamclaw_gateway::read_config(&workspace_path)?;
    Ok(config
        .other
        .get("systemPrompt")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string())
}

/// Save the per-workspace system prompt to teamclaw.json.
#[tauri::command]
pub fn save_system_prompt(
    window: tauri::WebviewWindow,
    registry: State<'_, crate::commands::window::WindowRegistry>,
    prompt: String,
    workspace_path: Option<String>,
) -> Result<(), String> {
    let workspace_path =
        crate::commands::team::resolve_workspace_path(workspace_path, &window, &registry)?;
    let mut config = teamclaw_gateway::read_config(&workspace_path)?;
    config
        .other
        .insert("systemPrompt".to_string(), serde_json::json!(prompt));
    teamclaw_gateway::write_config(&workspace_path, &config)
}

/// Set the locale in teamclaw.json for UI i18n.
#[tauri::command]
pub async fn set_config_locale(
    window: tauri::WebviewWindow,
    registry: State<'_, crate::commands::window::WindowRegistry>,
    locale: String,
) -> Result<(), String> {
    let workspace_path = crate::commands::window::current_workspace_for_window(&window, &registry)?;
    let mut config = teamclaw_gateway::read_config(&workspace_path)?;
    config.locale = Some(locale);
    teamclaw_gateway::write_config(&workspace_path, &config)
}
