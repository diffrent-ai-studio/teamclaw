pub mod client;
pub mod topics;

pub use client::{ClientConfig, MqttClient};

use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct MqttBusInner {
    pub client: Mutex<Option<MqttClient>>,
    pub subscribed: Mutex<HashSet<String>>,
}

impl MqttBusInner {
    pub fn new() -> Self {
        Self {
            client: Mutex::new(None),
            subscribed: Mutex::new(HashSet::new()),
        }
    }

    pub async fn force_reconnect(&self) {
        if let Some(client) = self.client.lock().await.as_ref() {
            let _ = client.client.disconnect().await;
        }
    }
}

pub type MqttBus = Arc<MqttBusInner>;
