//! Channel manager: boot and shut down `teamclaw_gateway` channels based on
//! `[channels.*]` entries in `daemon.toml`. Each gateway is constructed with
//! shared `AcpHandle` + `ChannelStore` adapters, populated with its per-channel
//! config (translated from `DaemonConfig`'s primitive fields into the gateway
//! crate's own config structs), and then started.
//!
//! The manager owns the gateway instances and tears them down via consuming
//! `shutdown(self)` calls when the daemon stops.

use std::sync::Arc;
use tokio::sync::Mutex;

use teamclaw_gateway::{
    AcpHandle, ChannelStore, DiscordConfig, DiscordGateway, EmailConfig, EmailGateway,
    EmailProvider, FeishuConfig, FeishuGateway, KookConfig, KookDmConfig, KookGateway,
    WeChatConfig, WeChatGateway, WeComConfig, WeComGateway,
};

use crate::config::{
    DaemonConfig, DiscordChannel, EmailChannel, FeishuChannel, KookChannel, WeChatChannel,
    WeComChannel,
};

#[derive(Default)]
struct RunningChannels {
    discord: Option<DiscordGateway>,
    wecom: Option<WeComGateway>,
    feishu: Option<FeishuGateway>,
    kook: Option<KookGateway>,
    wechat: Option<WeChatGateway>,
    email: Option<EmailGateway>,
}

pub struct ChannelManager {
    cfg: DaemonConfig,
    acp: Arc<dyn AcpHandle>,
    store: Arc<dyn ChannelStore>,
    team_id: String,
    primary_agent_actor_id: String,
    agent_owner_actor_ids: Vec<String>,
    /// Filesystem root that gateways may use for per-workspace state
    /// (`.teamclaw/email.db`, persisted iLink context tokens, etc.). For the
    /// amuxd-managed case this defaults to the amux config dir.
    workspace_path: String,
    running: Mutex<RunningChannels>,
}

impl ChannelManager {
    pub fn new(
        cfg: DaemonConfig,
        acp: Arc<dyn AcpHandle>,
        store: Arc<dyn ChannelStore>,
        team_id: String,
        primary_agent_actor_id: String,
        agent_owner_actor_ids: Vec<String>,
    ) -> Self {
        let workspace_path = DaemonConfig::config_dir().to_string_lossy().into_owned();
        Self {
            cfg,
            acp,
            store,
            team_id,
            primary_agent_actor_id,
            agent_owner_actor_ids,
            workspace_path,
            running: Mutex::new(RunningChannels::default()),
        }
    }

    /// Override the workspace path the gateways will use (e.g. for tests or
    /// when the daemon wants channels to share a specific workspace's state).
    pub fn with_workspace_path(mut self, workspace_path: impl Into<String>) -> Self {
        self.workspace_path = workspace_path.into();
        self
    }

    /// Start every channel whose `[channels.<name>]` section has `enabled = true`.
    ///
    /// Errors from individual channels are logged but do not abort startup of
    /// the remaining channels — running 4 out of 5 is better than 0 out of 5.
    pub async fn start_enabled(&self) -> anyhow::Result<()> {
        let mut running = self.running.lock().await;

        if let Some(c) = &self.cfg.channels.discord {
            if c.enabled {
                match self.start_discord(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] discord started");
                        running.discord = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] discord start failed: {e}"),
                }
            }
        }

        if let Some(c) = &self.cfg.channels.wecom {
            if c.enabled {
                match self.start_wecom(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] wecom started");
                        running.wecom = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] wecom start failed: {e}"),
                }
            }
        }

        if let Some(c) = &self.cfg.channels.feishu {
            if c.enabled {
                match self.start_feishu(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] feishu started");
                        running.feishu = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] feishu start failed: {e}"),
                }
            }
        }

        if let Some(c) = &self.cfg.channels.kook {
            if c.enabled {
                match self.start_kook(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] kook started");
                        running.kook = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] kook start failed: {e}"),
                }
            }
        }

        if let Some(c) = &self.cfg.channels.wechat {
            if c.enabled {
                match self.start_wechat(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] wechat started");
                        running.wechat = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] wechat start failed: {e}"),
                }
            }
        }

        if let Some(c) = &self.cfg.channels.email {
            if c.enabled {
                match self.start_email(c).await {
                    Ok(g) => {
                        println!("[ChannelManager] email started");
                        running.email = Some(g);
                    }
                    Err(e) => eprintln!("[ChannelManager] email start failed: {e}"),
                }
            }
        }

        Ok(())
    }

    /// Stop every running channel. Takes `self` by value so each gateway's
    /// consuming `shutdown(self)` can be invoked.
    pub async fn shutdown(self) {
        let mut running = self.running.into_inner();
        if let Some(g) = running.discord.take() {
            g.shutdown().await;
        }
        if let Some(g) = running.wecom.take() {
            g.shutdown().await;
        }
        if let Some(g) = running.feishu.take() {
            g.shutdown().await;
        }
        if let Some(g) = running.kook.take() {
            g.shutdown().await;
        }
        if let Some(g) = running.wechat.take() {
            g.shutdown().await;
        }
        if let Some(g) = running.email.take() {
            g.shutdown().await;
        }
    }

    // ----- per-channel constructors -----

    async fn start_discord(&self, c: &DiscordChannel) -> anyhow::Result<DiscordGateway> {
        let gw = DiscordGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
            self.workspace_path.clone(),
        );
        let mut cfg = DiscordConfig {
            enabled: true,
            token: c.bot_token.clone(),
            ..Default::default()
        };
        // Plumb optional default DM username into the DM allow-list when provided
        // so the operator can verify the bot answers DMs from at least themselves
        // without editing teamclaw.json directly. Leave alone otherwise.
        if let Some(name) = &c.default_username {
            if !name.is_empty() {
                cfg.dm.allow_from.push(name.clone());
            }
        }
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }

    async fn start_wecom(&self, c: &WeComChannel) -> anyhow::Result<WeComGateway> {
        let gw = WeComGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
            self.workspace_path.clone(),
        );
        let cfg = WeComConfig {
            enabled: true,
            bot_id: c.bot_id.clone(),
            secret: c.secret.clone(),
            encoding_aes_key: c.encoding_aes_key.clone(),
            owner_id: None,
        };
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }

    async fn start_feishu(&self, c: &FeishuChannel) -> anyhow::Result<FeishuGateway> {
        let gw = FeishuGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
            self.workspace_path.clone(),
        );
        let cfg = FeishuConfig {
            enabled: true,
            app_id: c.app_id.clone(),
            app_secret: c.app_secret.clone(),
            chats: Default::default(),
        };
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }

    async fn start_kook(&self, c: &KookChannel) -> anyhow::Result<KookGateway> {
        let gw = KookGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
            self.workspace_path.clone(),
        );
        let cfg = KookConfig {
            enabled: true,
            token: c.bot_token.clone(),
            // Default DM mode = open; the operator can lock down via the
            // gateway crate's `teamclaw.json` if desired. Until the manager
            // is wired to a richer config we let DMs through.
            dm: KookDmConfig {
                enabled: true,
                policy: "open".to_string(),
                allow_from: Vec::new(),
            },
            guilds: Default::default(),
        };
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }

    async fn start_wechat(&self, c: &WeChatChannel) -> anyhow::Result<WeChatGateway> {
        let gw = WeChatGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
            self.workspace_path.clone(),
        );
        let cfg = WeChatConfig {
            enabled: true,
            account_id: c.ilink_account.clone(),
            bot_token: c.ilink_token.clone(),
            ..Default::default()
        };
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }

    async fn start_email(&self, c: &EmailChannel) -> anyhow::Result<EmailGateway> {
        let gw = EmailGateway::new(
            self.acp.clone(),
            self.store.clone(),
            self.team_id.clone(),
            self.primary_agent_actor_id.clone(),
            self.agent_owner_actor_ids.clone(),
        );
        // EmailGateway's IMAP/SMTP "Custom" provider mode maps directly onto
        // the daemon-side EmailChannel primitive fields. Gmail OAuth flow
        // remains a Tauri-side concern and is not exposed via daemon.toml.
        let cfg = EmailConfig {
            enabled: true,
            provider: EmailProvider::Custom,
            imap_server: c.imap_host.clone(),
            imap_port: c.imap_port,
            smtp_server: c.smtp_host.clone(),
            smtp_port: c.smtp_port,
            username: c.imap_user.clone(),
            password: c.imap_pass.clone(),
            allowed_senders: c.allowed_senders.clone(),
            ..Default::default()
        };
        gw.set_workspace_path(&self.workspace_path).await;
        gw.set_config(cfg).await;
        gw.start().await.map_err(|e| anyhow::anyhow!(e))?;
        Ok(gw)
    }
}
