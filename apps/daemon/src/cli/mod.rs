pub mod channel;
pub mod clear;
pub mod process;
pub mod test_client;

use clap::{Args, Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "amuxd", version, about = "AMUX Agent Multiplexer Daemon")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Start the daemon (writes ~/.config/amux/amuxd.pid while running).
    Start {
        #[arg(short, long)]
        daemonize: bool,
        #[arg(long)]
        config: Option<PathBuf>,
    },
    /// Stop the running daemon (SIGTERM via pidfile).
    Stop,
    /// Show daemon status (reads the pidfile).
    Status,
    /// Onboard this daemon. Without args, walks you through the iOS side
    /// and prompts you to paste the deeplink. Pass the URL to skip the
    /// interactive prompt (useful for scripts).
    Init {
        /// `amux://invite?token=...` URL from the iOS Actors tab.
        join_url: Option<String>,
    },
    /// Delete local daemon state (daemon.toml, members.toml, sessions.toml,
    /// supabase.toml, workspaces.toml). Use before running `init` against a
    /// different team or after revoking access.
    Clear {
        /// Skip the interactive confirmation prompt.
        #[arg(long)]
        force: bool,
    },
    /// Test: spawn claude and print parsed events (for development)
    TestSpawn {
        /// Prompt to send
        prompt: String,
        /// Working directory
        #[arg(long, default_value = ".")]
        worktree: String,
    },
    /// Test: simulate an iOS client — connect to broker, send commands, watch events
    TestClient {
        /// Config file path (uses same daemon.toml)
        #[arg(long)]
        config: Option<std::path::PathBuf>,
        #[command(subcommand)]
        action: TestClientAction,
    },
    /// Manage channel bindings (discord, wecom, feishu, kook, wechat, email).
    Channel(ChannelArgs),
}

#[derive(Args, Debug)]
pub struct ChannelArgs {
    #[command(subcommand)]
    pub action: ChannelAction,
}

#[derive(Subcommand, Debug)]
pub enum ChannelAction {
    /// List all channels and their enabled state.
    List,
    /// Bind a channel (per-platform credentials).
    Bind(ChannelBindArgs),
    /// Remove a channel binding.
    Unbind { platform: String },
    /// Verify channel credentials are configured.
    Test { platform: String },
    /// Signal a running amuxd to re-read channel config.
    Reload,
}

#[derive(Args, Debug)]
pub struct ChannelBindArgs {
    #[command(subcommand)]
    pub platform: ChannelBindPlatform,
}

#[derive(Subcommand, Debug)]
pub enum ChannelBindPlatform {
    /// Bind a Discord bot.
    Discord {
        #[arg(long)]
        bot_token: String,
        #[arg(long)]
        default_username: Option<String>,
    },
    /// Bind a WeCom bot.
    Wecom {
        #[arg(long)]
        bot_id: String,
        #[arg(long)]
        secret: String,
        #[arg(long)]
        encoding_aes_key: Option<String>,
    },
    /// Bind a Feishu app.
    Feishu {
        #[arg(long)]
        app_id: String,
        #[arg(long)]
        app_secret: String,
    },
    /// Bind a Kook bot.
    Kook {
        #[arg(long)]
        bot_token: String,
    },
    /// Bind a WeChat (iLink) account.
    Wechat {
        #[arg(long)]
        ilink_account: String,
        #[arg(long)]
        ilink_token: String,
    },
    /// Bind an Email (IMAP/SMTP) channel.
    Email {
        #[arg(long)]
        imap_host: String,
        #[arg(long)]
        imap_port: u16,
        #[arg(long)]
        imap_user: String,
        #[arg(long)]
        imap_pass: String,
        #[arg(long)]
        smtp_host: String,
        #[arg(long)]
        smtp_port: u16,
        #[arg(long)]
        smtp_user: String,
        #[arg(long)]
        smtp_pass: String,
    },
}

#[derive(Subcommand)]
pub enum TestClientAction {
    /// Watch all events from the daemon (subscribe to all topics)
    Watch,
    /// Send a StartAgent command
    StartAgent { worktree: String, prompt: String },
    /// Send a PeerAnnounce (authenticate with token)
    Announce { token: String },
    /// Full E2E: announce → start agent → watch events (single connection)
    E2e {
        token: String,
        worktree: String,
        prompt: String,
    },
}
