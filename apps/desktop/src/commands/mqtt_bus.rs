use crate::mqtt::{ClientConfig, MqttBus, MqttClient};
use rumqttc::QoS;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, State};

#[derive(Debug, Serialize, Deserialize)]
pub struct MqttStatus {
    pub connected: bool,
    pub subscribed_topics: Vec<String>,
}

#[tauri::command]
pub async fn mqtt_connect(
    app: AppHandle,
    bus: State<'_, MqttBus>,
    broker_host: String,
    broker_port: u16,
    username: String,
    password: String,
    client_id: String,
    team_id: String,
) -> Result<(), String> {
    let cfg = ClientConfig {
        broker_host,
        broker_port,
        client_id,
        username,
        password,
        team_id,
    };
    let client = MqttClient::connect(cfg).map_err(|e| e.to_string())?;
    *bus.client.lock().await = Some(client);

    let bus_arc = (*bus).clone();
    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        crate::mqtt::client::run_event_loop(bus_arc, app_clone).await;
    });
    Ok(())
}

#[tauri::command]
pub async fn mqtt_subscribe(bus: State<'_, MqttBus>, topic: String) -> Result<(), String> {
    let client_guard = bus.client.lock().await;
    let client = client_guard.as_ref().ok_or("mqtt not connected")?;
    client
        .client
        .subscribe(&topic, QoS::AtLeastOnce)
        .await
        .map_err(|e| e.to_string())?;
    drop(client_guard);
    bus.subscribed.lock().await.insert(topic);
    Ok(())
}

#[tauri::command]
pub async fn mqtt_publish(
    bus: State<'_, MqttBus>,
    topic: String,
    bytes: Vec<u8>,
    retain: bool,
) -> Result<(), String> {
    let client_guard = bus.client.lock().await;
    let client = client_guard.as_ref().ok_or("mqtt not connected")?;
    client
        .client
        .publish(&topic, QoS::AtLeastOnce, retain, bytes)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn mqtt_status(bus: State<'_, MqttBus>) -> Result<MqttStatus, String> {
    let connected = bus.client.lock().await.is_some();
    let subscribed_topics: Vec<String> = bus.subscribed.lock().await.iter().cloned().collect();
    Ok(MqttStatus {
        connected,
        subscribed_topics,
    })
}
