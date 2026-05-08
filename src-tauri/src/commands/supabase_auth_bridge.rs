use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct SupabaseSession {
    pub user_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
}

#[tauri::command]
pub async fn supabase_get_session() -> Result<Option<SupabaseSession>, String> {
    Ok(None)
}

#[tauri::command]
pub async fn supabase_login() -> Result<String, String> {
    Err("not_implemented".into())
}

#[tauri::command]
pub async fn supabase_logout() -> Result<(), String> {
    Err("not_implemented".into())
}

#[tauri::command]
pub async fn supabase_handle_deeplink(_url: String) -> Result<(), String> {
    Err("not_implemented".into())
}
