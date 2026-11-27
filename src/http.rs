use crate::models::{Channel, Guild, Message, User};
use crate::Error;
use serde::de::DeserializeOwned;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const API: &str = "https://discord.com/api/v10";

#[derive(Clone)]
pub struct HttpClient {
    client: reqwest::Client,
    token: String,
    cache: Arc<Mutex<HashMap<String, CachedResponse>>>,
}

struct CachedResponse {
    expires_at: Instant,
    body: Vec<u8>,
}

impl HttpClient {
    pub fn new(token: impl Into<String>) -> Self {
        Self {
            client: reqwest::Client::new(),
            token: token.into(),
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn auth(&self) -> String {
        if self.token.starts_with("Bot ") || self.token.starts_with("Bearer ") {
            self.token.clone()
        } else {
            format!("Bot {}", self.token)
        }
    }

    async fn get<T: DeserializeOwned>(&self, path: &str, ttl: Duration) -> Result<T, Error> {
        if let Some(body) = self.cached(path) {
            return Ok(serde_json::from_slice(&body)?);
        }
        let resp = self
            .client
            .get(format!("{API}{path}"))
            .header("Authorization", self.auth())
            .send()
            .await?;
        let status = resp.status();
        let body = resp.bytes().await?;
        if !status.is_success() {
            return Err(Error::Api {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&body).into_owned(),
            });
        }
        self.store_cache(path, body.to_vec(), ttl);
        Ok(serde_json::from_slice(&body)?)
    }

    fn cached(&self, path: &str) -> Option<Vec<u8>> {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        match cache.get(path) {
            Some(entry) if entry.expires_at > Instant::now() => Some(entry.body.clone()),
            Some(_) => {
                cache.remove(path);
                None
            }
            None => None,
        }
    }

    fn store_cache(&self, path: &str, body: Vec<u8>, ttl: Duration) {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        if cache.len() >= 256 {
            let now = Instant::now();
            cache.retain(|_, entry| entry.expires_at > now);
            if cache.len() >= 256 {
                if let Some(oldest) = cache
                    .iter()
                    .min_by_key(|(_, entry)| entry.expires_at)
                    .map(|(key, _)| key.clone())
                {
                    cache.remove(&oldest);
                }
            }
        }
        cache.insert(
            path.to_owned(),
            CachedResponse {
                expires_at: Instant::now() + ttl,
                body,
            },
        );
    }

    fn invalidate_prefix(&self, prefix: &str) {
        self.cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|key, _| !key.starts_with(prefix));
    }

    async fn parse<T: DeserializeOwned>(resp: reqwest::Response) -> Result<T, Error> {
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(Error::Api {
                status: status.as_u16(),
                body,
            });
        }
        Ok(resp.json().await?)
    }

    pub async fn current_user(&self) -> Result<User, Error> {
        self.get("/users/@me", Duration::from_secs(300)).await
    }

    pub async fn guilds(&self) -> Result<Vec<Guild>, Error> {
        self.get("/users/@me/guilds", Duration::from_secs(60)).await
    }

    pub async fn guild_channels(&self, guild_id: &str) -> Result<Vec<Channel>, Error> {
        self.get(
            &format!("/guilds/{guild_id}/channels"),
            Duration::from_secs(60),
        )
        .await
    }

    pub async fn create_dm(&self, recipient_id: &str) -> Result<Channel, Error> {
        let resp = self
            .client
            .post(format!("{API}/users/@me/channels"))
            .header("Authorization", self.auth())
            .json(&serde_json::json!({ "recipient_id": recipient_id }))
            .send()
            .await?;
        Self::parse(resp).await
    }

    pub async fn messages(&self, channel_id: &str, limit: u8) -> Result<Vec<Message>, Error> {
        self.get(
            &format!(
                "/channels/{channel_id}/messages?limit={}",
                limit.clamp(1, 100)
            ),
            Duration::from_secs(5),
        )
        .await
    }

    pub async fn send_message(&self, channel_id: &str, content: &str) -> Result<Message, Error> {
        let resp = self
            .client
            .post(format!("{API}/channels/{channel_id}/messages"))
            .header("Authorization", self.auth())
            .json(&serde_json::json!({ "content": content }))
            .send()
            .await?;
        let message: Message = Self::parse(resp).await?;
        self.invalidate_prefix(&format!("/channels/{channel_id}/messages?"));
        Ok(message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_cache_expires_and_invalidates_by_prefix() {
        let client = HttpClient::new("test-token");
        client.store_cache(
            "/channels/1/messages?limit=50",
            b"cached".to_vec(),
            Duration::from_secs(30),
        );
        assert_eq!(
            client.cached("/channels/1/messages?limit=50"),
            Some(b"cached".to_vec())
        );

        client.invalidate_prefix("/channels/1/messages?");
        assert_eq!(client.cached("/channels/1/messages?limit=50"), None);

        client.store_cache("/users/@me", b"stale".to_vec(), Duration::ZERO);
        assert_eq!(client.cached("/users/@me"), None);
    }
}
