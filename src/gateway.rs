use crate::Error;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::tungstenite::Message as Ws;

const GATEWAY: &str = "wss://gateway.discord.gg/?v=10&encoding=json";

/// GUILDS | GUILD_MESSAGES | DIRECT_MESSAGES | MESSAGE_CONTENT
pub const DEFAULT_INTENTS: u64 = (1 << 0) | (1 << 9) | (1 << 12) | (1 << 15);

#[derive(Debug, Clone)]
pub struct Event {
    pub name: String,
    pub data: Value,
}

/// Connects to the gateway and forwards dispatch events to `tx` until the
/// connection closes or the receiver is dropped.
pub async fn run(token: &str, intents: u64, tx: UnboundedSender<Event>) -> Result<(), Error> {
    let (ws, _) = tokio_tungstenite::connect_async(GATEWAY).await?;
    let (mut sink, mut stream) = ws.split();

    let hello: Value = match stream.next().await {
        Some(Ok(Ws::Text(t))) => serde_json::from_str(&t)?,
        _ => return Err(Error::Gateway("no HELLO received".into())),
    };
    let interval = hello["d"]["heartbeat_interval"].as_u64().unwrap_or(41_250);

    let identify = json!({
        "op": 2,
        "d": {
            "token": token,
            "intents": intents,
            "properties": { "os": "ios", "browser": "rustcord", "device": "rustcord" }
        }
    });
    sink.send(Ws::Text(identify.to_string())).await?;

    let mut seq: Option<u64> = None;
    let mut ticker = tokio::time::interval(Duration::from_millis(interval));
    loop {
        tokio::select! {
            _ = ticker.tick() => {
                sink.send(Ws::Text(json!({"op": 1, "d": seq}).to_string())).await?;
            }
            msg = stream.next() => {
                let text = match msg {
                    Some(Ok(Ws::Text(t))) => t,
                    Some(Ok(Ws::Close(_))) | None => return Ok(()),
                    Some(Ok(_)) => continue,
                    Some(Err(e)) => return Err(e.into()),
                };
                let v: Value = serde_json::from_str(&text)?;
                if let Some(s) = v["s"].as_u64() { seq = Some(s); }
                match v["op"].as_u64() {
                    Some(0) => {
                        let name = v["t"].as_str().unwrap_or_default().to_string();
                        if tx.send(Event { name, data: v["d"].clone() }).is_err() {
                            return Ok(());
                        }
                    }
                    Some(1) => sink.send(Ws::Text(json!({"op": 1, "d": seq}).to_string())).await?,
                    Some(7) | Some(9) => return Err(Error::Gateway("reconnect required".into())),
                    _ => {}
                }
            }
        }
    }
}
