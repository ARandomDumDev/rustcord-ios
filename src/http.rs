use crate::models::{Channel, Guild, Message, User};
use crate::Error;
use serde::de::DeserializeOwned;

const API: &str = "https://discord.com/api/v10";

#[derive(Clone)]
pub struct HttpClient {
    client: reqwest::Client,
    token: String,
}

impl HttpClient {
    pub fn new(token: impl Into<String>) -> Self {
        Self { client: reqwest::Client::new(), token: token.into() }
    }

    fn auth(&self) -> String {
        if self.token.starts_with("Bot ") || self.token.starts_with("Bearer ") {
            self.token.clone()
        } else {
            format!("Bot {}", self.token)
        }
    }

    async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, Error> {
        let resp = self
            .client
            .get(format!("{API}{path}"))
            .header("Authorization", self.auth())
            .send()
            .await?;
        Self::parse(resp).await
    }

    async fn parse<T: DeserializeOwned>(resp: reqwest::Response) -> Result<T, Error> {
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(Error::Api { status: status.as_u16(), body });
        }
        Ok(resp.json().await?)
    }

    pub async fn current_user(&self) -> Result<User, Error> {
        self.get("/users/@me").await
    }

    pub async fn guilds(&self) -> Result<Vec<Guild>, Error> {
        self.get("/users/@me/guilds").await
    }

    pub async fn guild_channels(&self, guild_id: &str) -> Result<Vec<Channel>, Error> {
        self.get(&format!("/guilds/{guild_id}/channels")).await
    }

    pub async fn messages(&self, channel_id: &str, limit: u8) -> Result<Vec<Message>, Error> {
        self.get(&format!("/channels/{channel_id}/messages?limit={}", limit.clamp(1, 100))).await
    }

    pub async fn send_message(&self, channel_id: &str, content: &str) -> Result<Message, Error> {
        let resp = self
            .client
            .post(format!("{API}/channels/{channel_id}/messages"))
            .header("Authorization", self.auth())
            .json(&serde_json::json!({ "content": content }))
            .send()
            .await?;
        Self::parse(resp).await
    }
}
