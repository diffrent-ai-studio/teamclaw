use anyhow::Result;
use rumqttc::{AsyncClient, EventLoop, LastWill, MqttOptions, QoS};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub struct ClientConfig {
    pub broker_host: String,
    pub broker_port: u16,
    pub client_id: String,
    pub username: String,
    pub password: String,
}

pub struct MqttClient {
    pub client: AsyncClient,
    pub event_loop: Arc<Mutex<EventLoop>>,
    pub client_id: String,
}

impl MqttClient {
    pub fn connect(cfg: ClientConfig) -> Result<Self> {
        let mut opts = MqttOptions::new(&cfg.client_id, &cfg.broker_host, cfg.broker_port);
        opts.set_credentials(&cfg.username, &cfg.password);
        opts.set_clean_session(false);
        opts.set_keep_alive(Duration::from_secs(30));

        let lwt_topic = super::topics::device_state_topic(&cfg.client_id);
        let lwt_payload = serde_json::json!({"status":"offline"}).to_string().into_bytes();
        opts.set_last_will(LastWill::new(lwt_topic, lwt_payload, QoS::AtLeastOnce, true));

        let (client, event_loop) = AsyncClient::new(opts, 64);
        Ok(Self {
            client,
            event_loop: Arc::new(Mutex::new(event_loop)),
            client_id: cfg.client_id,
        })
    }
}

pub async fn run_event_loop(bus: Arc<super::MqttBusInner>, app: tauri::AppHandle) {
    use rumqttc::{Event, Packet};
    use tauri::Emitter;

    let mut backoff_secs: u64 = 1;
    loop {
        let event_loop_arc = {
            let guard = bus.client.lock().await;
            guard.as_ref().map(|c| c.event_loop.clone())
        };
        let Some(event_loop) = event_loop_arc else {
            tokio::time::sleep(Duration::from_secs(1)).await;
            continue;
        };
        let mut event_loop = event_loop.lock().await;
        match event_loop.poll().await {
            Ok(Event::Incoming(Packet::Publish(p))) => {
                backoff_secs = 1;
                let payload = serde_json::json!({
                    "topic": p.topic,
                    "bytes": p.payload.to_vec(),
                });
                let _ = app.emit("mqtt:envelope", payload);
            }
            Ok(_) => {
                backoff_secs = 1;
            }
            Err(e) => {
                tracing::warn!("mqtt event loop error: {e}, retry in {backoff_secs}s");
                drop(event_loop);
                tokio::time::sleep(Duration::from_secs(backoff_secs)).await;
                backoff_secs = (backoff_secs * 2).min(60);
            }
        }
    }
}
