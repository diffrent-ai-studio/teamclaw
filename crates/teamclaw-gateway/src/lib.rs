#![allow(clippy::too_many_arguments)]

pub mod acp;
pub use acp::{AcpError, AcpHandle, AcpTurnOutcome, AmuxSessionId};

pub mod binding;
pub mod supabase_store;
pub use supabase_store::{ChannelStore, EnsureSessionOutcome, StoreError};

pub mod config;
pub mod discord;
pub mod email;
pub mod email_config;
pub mod email_db;
pub mod feishu;
pub mod feishu_config;
pub mod i18n;
pub mod kook;
pub mod kook_config;
pub mod pending_question;
pub mod session;
pub mod session_queue;
pub mod wechat;
pub mod wechat_config;
pub mod wecom;
pub mod wecom_config;

pub use config::*;
pub use discord::DiscordGateway;
pub use email::{AuthUrlCallback, EmailGateway};
pub use email_config::*;
pub use feishu::FeishuGateway;
pub use feishu_config::*;
pub use kook::KookGateway;
pub use kook_config::*;
pub use pending_question::{
    extract_question_marker, format_question_message, handle_question_event, parse_question_event,
    ForwardedQuestion, PendingQuestionStore, QuestionContext,
};
pub use session::SessionMapping;
pub use wechat::WeChatGateway;
pub use wechat_config::*;
pub use wecom::WeComGateway;
pub use wecom_config::*;

use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::time::Duration;

/// The `.teamclaw` directory name, matching the main crate's `TEAMCLAW_DIR`.
pub const TEAMCLAW_DIR: &str = ".teamclaw";

/// The config file name inside TEAMCLAW_DIR: `teamclaw.json`.
pub const CONFIG_FILE_NAME: &str = "teamclaw.json";

/// Identity of the person who sent a message through a gateway channel.
#[derive(Debug, Clone)]
pub struct ChannelSender {
    pub platform: String,
    #[allow(dead_code)]
    pub external_id: String,
    pub display_name: String,
}

pub const MAX_PROCESSED_MESSAGES: usize = 1000;

#[derive(Debug, Clone, PartialEq)]
pub enum FilterResult {
    Allow,
    Ignore,
    UserNotAllowed,
    ChannelNotConfigured,
}

pub struct ProcessedMessageTracker {
    messages: HashSet<String>,
    max_size: usize,
}

impl ProcessedMessageTracker {
    pub fn new(max_size: usize) -> Self {
        Self {
            messages: HashSet::new(),
            max_size,
        }
    }

    pub fn is_duplicate(&mut self, id: &str) -> bool {
        if self.messages.contains(id) {
            return true;
        }
        self.messages.insert(id.to_string());
        if self.messages.len() > self.max_size {
            let to_remove: Vec<String> = self.messages.iter().take(100).cloned().collect();
            for r in to_remove {
                self.messages.remove(&r);
            }
        }
        false
    }
}

// ==================== Permission Auto-Approval ====================

/// OpenCode permission request
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct PermissionRequest {
    pub id: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub permission: String,
    #[serde(default)]
    pub patterns: Vec<String>,
    pub always: Option<Vec<String>>,
    pub metadata: Option<serde_json::Value>,
}

/// Permission auto-approval service
pub struct PermissionAutoApprover {
    pub opencode_port: u16,
    pub polling_interval: Duration,
    pub max_duration: Duration,
}

impl PermissionAutoApprover {
    pub fn new(opencode_port: u16) -> Self {
        Self {
            opencode_port,
            polling_interval: Duration::from_secs(2),
            max_duration: Duration::from_secs(600),
        }
    }
}

impl Clone for PermissionAutoApprover {
    fn clone(&self) -> Self {
        Self {
            opencode_port: self.opencode_port,
            polling_interval: self.polling_interval,
            max_duration: self.max_duration,
        }
    }
}

// ==================== SSE / Message Helpers ====================

/// Parse a single SSE event from text
pub fn parse_sse_event(text: &str) -> Option<serde_json::Value> {
    for line in text.lines() {
        if let Some(data) = line.strip_prefix("data: ") {
            match serde_json::from_str::<serde_json::Value>(data) {
                Ok(json) => return Some(json),
                Err(e) => {
                    println!(
                        "[AsyncOpenCode] Failed to parse SSE data: {} (data: {})",
                        e,
                        &data[..data.len().min(100)]
                    );
                }
            }
        }
    }
    None
}

/// Fetch message content by message ID
pub async fn fetch_message_content(
    port: u16,
    session_id: &str,
    message_id: &str,
) -> Result<String, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());
    let url = format!("http://127.0.0.1:{}/session/{}/message", port, session_id);

    let response = client
        .get(&url)
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| format!("Failed to fetch messages: {}", e))?;

    let messages: Vec<serde_json::Value> = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse messages: {}", e))?;

    for msg in messages {
        let msg_id = msg
            .get("info")
            .and_then(|info| info.get("id"))
            .and_then(|id| id.as_str());

        if msg_id == Some(message_id) {
            return extract_message_content(&msg);
        }
    }

    Err(format!("Message {} not found", message_id))
}

/// Extract text content from an OpenCode message.
fn extract_message_content(message: &serde_json::Value) -> Result<String, String> {
    let parts = message
        .get("parts")
        .and_then(|p| p.as_array())
        .ok_or_else(|| "No parts in message".to_string())?;

    let mut text_parts = Vec::new();
    let mut reasoning_parts = Vec::new();

    for part in parts.iter() {
        if let Some(part_type) = part.get("type").and_then(|t| t.as_str()) {
            if part_type == "text" {
                if let Some(text) = part.get("text").and_then(|t| t.as_str()) {
                    text_parts.push(text.to_string());
                }
            } else if part_type == "reasoning" {
                if let Some(text) = part.get("text").and_then(|t| t.as_str()) {
                    reasoning_parts.push(text.to_string());
                }
            }
        }
    }

    if !text_parts.is_empty() {
        Ok(text_parts.join("\n"))
    } else if !reasoning_parts.is_empty() {
        Ok(reasoning_parts.join("\n"))
    } else {
        Err("No text content in message".to_string())
    }
}

// ==================== Model Helpers ====================

/// Information about a single model
#[derive(Debug, Clone)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
    pub provider: String,
}

/// Parse a stored model preference string ("provider/model") into (providerID, modelID)
pub fn parse_model_preference(model_str: &str) -> Option<(String, String)> {
    let parts: Vec<&str> = model_str.splitn(2, '/').collect();
    if parts.len() == 2 {
        Some((parts[0].to_string(), parts[1].to_string()))
    } else {
        None
    }
}

// ==================== Config Helpers ====================

/// Configuration file structure for channels
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct OpenCodeJsonConfigWithChannels {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mcp: Option<HashMap<String, serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channels: Option<ChannelsConfig>,
    #[serde(flatten)]
    pub other: HashMap<String, serde_json::Value>,
}

/// Ensure the .teamclaw directory exists in the workspace
pub fn ensure_teamclaw_dir(workspace_path: &str) -> Result<(), String> {
    let dir = format!("{}/{}", workspace_path, TEAMCLAW_DIR);
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create {} directory: {}", TEAMCLAW_DIR, e))
}

/// Get config file path from workspace (.teamclaw/teamclaw.json)
pub fn get_config_path(workspace_path: &str) -> String {
    format!("{}/{}/{}", workspace_path, TEAMCLAW_DIR, CONFIG_FILE_NAME)
}

/// Read configuration from file
pub fn read_config(workspace_path: &str) -> Result<OpenCodeJsonConfigWithChannels, String> {
    ensure_teamclaw_dir(workspace_path)?;
    let path = get_config_path(workspace_path);

    if !std::path::Path::new(&path).exists() {
        return Ok(OpenCodeJsonConfigWithChannels {
            schema: Some("https://opencode.ai/config.json".to_string()),
            ..Default::default()
        });
    }

    let content =
        std::fs::read_to_string(&path).map_err(|e| format!("Failed to read config file: {}", e))?;

    serde_json::from_str(&content).map_err(|e| format!("Failed to parse config file: {}", e))
}

/// Write configuration to file
pub fn write_config(
    workspace_path: &str,
    config: &OpenCodeJsonConfigWithChannels,
) -> Result<(), String> {
    ensure_teamclaw_dir(workspace_path)?;
    let path = get_config_path(workspace_path);

    let content = serde_json::to_string_pretty(config)
        .map_err(|e| format!("Failed to serialize config: {}", e))?;

    std::fs::write(&path, content).map_err(|e| format!("Failed to write config file: {}", e))
}
