//! Rustcord: a Discord client library with a C FFI suitable for iOS apps.

pub mod ffi;
pub mod gateway;
pub mod http;
pub mod models;

pub use http::HttpClient;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("http error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("websocket error: {0}")]
    Ws(#[from] tokio_tungstenite::tungstenite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("discord api error {status}: {body}")]
    Api { status: u16, body: String },
    #[error("gateway error: {0}")]
    Gateway(String),
}
