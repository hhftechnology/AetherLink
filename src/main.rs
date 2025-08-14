use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::net::SocketAddr;
use std::path::PathBuf;
use tracing::{info, warn};

mod config;
mod server;
mod client;
mod tunnel;

use config::{Config, Identity};

#[derive(Parser, Debug)]
#[command(
    name = "aetherlink",
    version = env!("CARGO_PKG_VERSION"),
    about = "Lightweight HTTP tunnel using Iroh P2P transport",
    long_about = "AetherLink creates secure HTTP tunnels without requiring open ports or complex firewall rules"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Configuration directory path
    #[arg(short, long, env = "AETHERLINK_CONFIG", default_value = "~/.aetherlink")]
    config: PathBuf,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, env = "AETHERLINK_LOG_LEVEL", default_value = "info")]
    log_level: String,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize AetherLink identity and configuration
    Init {
        /// Force overwrite existing configuration
        #[arg(short, long)]
        force: bool,
    },

    /// Start AetherLink server (egress node)
    Server {
        /// Bind address for the admin API
        #[arg(short, long, default_value = "127.0.0.1:2019")]
        admin_bind: SocketAddr,
    },

    /// Create a tunnel to a local service
    Tunnel {
        /// Domain name for the tunnel (e.g., app.example.com)
        domain: String,

        /// Local port to tunnel
        #[arg(short, long)]
        local_port: u16,

        /// Server node ID or alias
        #[arg(short, long, env = "AETHERLINK_SERVER")]
        server: Option<String>,

        /// Local bind address for HTTP traffic
        #[arg(short, long, default_value = "127.0.0.1:0")]
        bind: SocketAddr,
    },

    /// List active tunnels
    List {
        /// Server to query (optional, uses default if not specified)
        #[arg(short, long)]
        server: Option<String>,
    },

    /// Show identity information
    Info,

    /// Add a server alias
    AddServer {
        /// Alias name for the server
        name: String,
        
        /// Server node ID (z32 format)
        node_id: String,
    },

    /// Authorize a client to connect
    Authorize {
        /// Client node ID to authorize
        client_id: String,
    },

    /// Revoke client authorization
    Revoke {
        /// Client node ID to revoke
        client_id: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::builder()
                .with_default_directive(cli.log_level.parse()?)
                .from_env_lossy(),
        )
        .with_target(false)
        .with_thread_ids(false)
        .init();

    // Expand home directory in config path
    let config_dir = shellexpand::tilde(&cli.config.to_string_lossy()).to_string();
    let config_path = PathBuf::from(config_dir);

    // Ensure config directory exists
    std::fs::create_dir_all(&config_path)
        .with_context(|| format!("Failed to create config directory: {:?}", config_path))?;

    let mut config = Config::load(&config_path)?;

    match cli.command {
        Commands::Init { force } => {
            if config.identity.is_some() && !force {
                warn!("Identity already exists. Use --force to overwrite.");
                return Ok(());
            }
            
            let identity = Identity::generate();
            config.identity = Some(identity.clone());
            config.save(&config_path)?;
            
            info!("✓ AetherLink initialized successfully");
            info!("Node ID: {}", identity.node_id());
            info!("Config directory: {:?}", config_path);
        }

        Commands::Server { admin_bind } => {
            let identity = config.identity
                .context("No identity found. Run 'aetherlink init' first")?;
            
            info!("Starting AetherLink server");
            info!("Node ID: {}", identity.node_id());
            info!("Admin API: http://{}", admin_bind);
            
            server::run_server(identity, config_path, admin_bind).await?;
        }

        Commands::Tunnel { domain, local_port, server, bind } => {
            let identity = config.identity
                .context("No identity found. Run 'aetherlink init' first")?;
            
            let server_id = if let Some(s) = server {
                config.resolve_server(&s)?
            } else {
                config.default_server
                    .context("No default server configured")?
            };
            
            info!("Creating tunnel to {}:{}", domain, local_port);
            info!("Server: {}", server_id);
            
            client::create_tunnel(
                identity,
                server_id,
                domain,
                local_port,
                bind,
            ).await?;
        }

        Commands::List { server } => {
            let identity = config.identity
                .context("No identity found. Run 'aetherlink init' first")?;
            
            let server_id = if let Some(s) = server {
                config.resolve_server(&s)?
            } else {
                config.default_server
                    .context("No default server configured")?
            };
            
            client::list_tunnels(identity, server_id).await?;
        }

        Commands::Info => {
            if let Some(identity) = config.identity {
                info!("AetherLink Identity Information");
                info!("================================");
                info!("Node ID: {}", identity.node_id());
                info!("Config directory: {:?}", config_path);
                
                if let Some(default_server) = config.default_server {
                    info!("Default server: {}", default_server);
                }
                
                if !config.servers.is_empty() {
                    info!("\nConfigured servers:");
                    for (name, id) in &config.servers {
                        info!("  {} → {}", name, id);
                    }
                }
            } else {
                warn!("No identity found. Run 'aetherlink init' first");
            }
        }

        Commands::AddServer { name, node_id } => {
            let server_id = node_id.parse()
                .context("Invalid node ID format")?;
            
            config.servers.insert(name.clone(), server_id);
            config.save(&config_path)?;
            
            info!("✓ Added server alias '{}' → {}", name, server_id);
        }

        Commands::Authorize { client_id } => {
            let client_node_id = client_id.parse()
                .context("Invalid client node ID")?;
            
            let auth_file = config_path.join("auth").join(&client_id);
            std::fs::create_dir_all(auth_file.parent().unwrap())?;
            std::fs::write(&auth_file, "")?;
            
            info!("✓ Authorized client: {}", client_node_id);
        }

        Commands::Revoke { client_id } => {
            let auth_file = config_path.join("auth").join(&client_id);
            if auth_file.exists() {
                std::fs::remove_file(&auth_file)?;
                info!("✓ Revoked authorization for client: {}", client_id);
            } else {
                warn!("Client {} was not authorized", client_id);
            }
        }
    }

    Ok(())
}

mod shellexpand {
    pub fn tilde(s: &str) -> std::borrow::Cow<str> {
        if s.starts_with("~/") {
            if let Ok(home) = std::env::var("HOME") {
                return std::borrow::Cow::Owned(s.replacen("~", &home, 1));
            }
        }
        std::borrow::Cow::Borrowed(s)
    }
}