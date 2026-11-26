//! Minimal terminal Discord client built on the rustcord endpoints.
//!
//! Usage (DISCORD_TOKEN must be set):
//!   cargo run --example cli -- guilds
//!   cargo run --example cli -- channels <guild_id>
//!   cargo run --example cli -- messages <channel_id>
//!   cargo run --example cli -- send <channel_id> <text...>
//!   cargo run --example cli -- listen

use rustcord::{gateway, HttpClient};

#[tokio::main]
async fn main() -> Result<(), rustcord::Error> {
    let token = std::env::var("DISCORD_TOKEN").expect("set DISCORD_TOKEN");
    let http = HttpClient::new(token.clone());
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["guilds"] => {
            for g in http.guilds().await? {
                println!("{}\t{}", g.id, g.name);
            }
        }
        ["channels", guild] => {
            for c in http.guild_channels(guild).await? {
                println!("{}\t{}", c.id, c.name.unwrap_or_default());
            }
        }
        ["messages", channel] => {
            for m in http.messages(channel, 25).await?.iter().rev() {
                println!("[{}] {}: {}", m.timestamp, m.author.username, m.content);
            }
        }
        ["send", channel, text @ ..] => {
            let m = http.send_message(channel, &text.join(" ")).await?;
            println!("sent {}", m.id);
        }
        ["listen"] => {
            let me = http.current_user().await?;
            println!("logged in as {}", me.username);
            let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
            tokio::spawn(async move {
                if let Err(e) = gateway::run(&token, gateway::DEFAULT_INTENTS, tx).await {
                    eprintln!("gateway: {e}");
                }
            });
            while let Some(ev) = rx.recv().await {
                if ev.name == "MESSAGE_CREATE" {
                    println!("{}: {}", ev.data["author"]["username"], ev.data["content"]);
                }
            }
        }
        _ => eprintln!("usage: cli guilds | channels <guild> | messages <channel> | send <channel> <text> | listen"),
    }
    Ok(())
}
