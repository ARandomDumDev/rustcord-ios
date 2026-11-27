use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub username: String,
    #[serde(default)]
    pub global_name: Option<String>,
    #[serde(default)]
    pub avatar: Option<String>,
    #[serde(default)]
    pub bot: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Guild {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub icon: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Channel {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: u8,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub guild_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub channel_id: String,
    pub author: User,
    pub content: String,
    pub timestamp: String,
    #[serde(default)]
    pub attachments: Vec<Attachment>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attachment {
    pub id: String,
    pub filename: String,
    pub url: String,
    #[serde(default)]
    pub content_type: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_decodes_attachments_and_legacy_messages_without_them() {
        let message: Message = serde_json::from_str(
            r#"{"id":"m1","channel_id":"c1","author":{"id":"u1","username":"user"},"content":"","timestamp":"now","attachments":[{"id":"a1","filename":"photo.png","url":"https://cdn.discordapp.com/photo.png","content_type":"image/png"}]}"#,
        )
        .unwrap();
        assert_eq!(message.attachments.len(), 1);
        assert_eq!(
            message.attachments[0].content_type.as_deref(),
            Some("image/png")
        );

        let legacy: Message = serde_json::from_str(
            r#"{"id":"m2","channel_id":"c1","author":{"id":"u1","username":"user"},"content":"hello","timestamp":"now"}"#,
        )
        .unwrap();
        assert!(legacy.attachments.is_empty());
    }
}
