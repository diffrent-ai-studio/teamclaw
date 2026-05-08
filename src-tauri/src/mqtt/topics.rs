pub fn session_topic(session_id: &str) -> String {
    format!("session/{session_id}/live")
}

pub fn device_state_topic(client_id: &str) -> String {
    format!("device/{client_id}/state")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn session_topic_format() {
        assert_eq!(session_topic("s1"), "session/s1/live");
    }
    #[test]
    fn device_state_topic_format() {
        assert_eq!(device_state_topic("d1"), "device/d1/state");
    }
}
