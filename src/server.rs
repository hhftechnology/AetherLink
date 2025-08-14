use anyhow::{Context, Result};
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use iroh::protocol::{Router, ProtocolHandler};
use iroh::{Endpoint, NodeId};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::config::{Auth, Identity};
use crate::tunnel::{TUNNEL_ALPN, TunnelMessage};

type BoxBody = http_body_util::combinators::BoxBody<Bytes, hyper::Error>;

pub async fn run_server(
    identity: Identity,
    config_dir: std::path::PathBuf,
    admin_bind: SocketAddr,
) -> Result<()> {
    let auth = Arc::new(Auth::new(&config_dir)?);
    let state = Arc::new(ServerState::new());
    
    // Start Iroh endpoint
    let endpoint = Endpoint::builder()
        .secret_key(identity.secret_key.clone())
        .discovery_n0()
        .bind()
        .await?;
    
    info!("Server listening on Iroh network");
    info!("Node ID: {}", identity.node_id());
    
    // Start tunnel protocol handler
    let handler = TunnelHandler {
        state: state.clone(),
        auth: auth.clone(),
    };
    
    let router = Router::builder(endpoint.clone())
        .accept(TUNNEL_ALPN, handler)
        .spawn();
    
    // Start admin API
    let admin_listener = TcpListener::bind(admin_bind).await?;
    info!("Admin API listening on http://{}", admin_bind);
    
    // Run admin server
    let admin_state = state.clone();
    tokio::spawn(async move {
        loop {
            match admin_listener.accept().await {
                Ok((stream, _)) => {
                    let state = admin_state.clone();
                    tokio::spawn(async move {
                        let service = service_fn(move |req| {
                            handle_admin_request(state.clone(), req)
                        });
                        
                        if let Err(e) = http1::Builder::new()
                            .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                            .await
                        {
                            error!("Admin API error: {}", e);
                        }
                    });
                }
                Err(e) => error!("Failed to accept admin connection: {}", e),
            }
        }
    });
    
    // Wait for shutdown signal
    tokio::signal::ctrl_c().await?;
    info!("Shutting down server...");
    
    router.shutdown().await?;
    Ok(())
}

#[derive(Debug)]
struct ServerState {
    tunnels: Arc<RwLock<HashMap<String, TunnelInfo>>>,
}

#[derive(Debug, Clone)]
struct TunnelInfo {
    domain: String,
    client_id: NodeId,
    target_port: u16,
    created_at: std::time::SystemTime,
}

impl ServerState {
    fn new() -> Self {
        Self {
            tunnels: Arc::new(RwLock::new(HashMap::new())),
        }
    }
    
    async fn register_tunnel(&self, domain: String, client_id: NodeId, port: u16) -> Result<()> {
        let mut tunnels = self.tunnels.write().await;
        
        if tunnels.contains_key(&domain) {
            return Err(anyhow::anyhow!("Domain {} is already in use", domain));
        }
        
        tunnels.insert(domain.clone(), TunnelInfo {
            domain: domain.clone(),
            client_id,
            target_port: port,
            created_at: std::time::SystemTime::now(),
        });
        
        info!("Registered tunnel: {} → {}", domain, client_id);
        Ok(())
    }
    
    async fn unregister_tunnel(&self, domain: &str) {
        let mut tunnels = self.tunnels.write().await;
        if tunnels.remove(domain).is_some() {
            info!("Unregistered tunnel: {}", domain);
        }
    }
    
    async fn get_tunnel(&self, domain: &str) -> Option<TunnelInfo> {
        let tunnels = self.tunnels.read().await;
        tunnels.get(domain).cloned()
    }
    
    async fn list_tunnels(&self) -> Vec<TunnelInfo> {
        let tunnels = self.tunnels.read().await;
        tunnels.values().cloned().collect()
    }
}

struct TunnelHandler {
    state: Arc<ServerState>,
    auth: Arc<Auth>,
}

impl ProtocolHandler for TunnelHandler {
    fn accept(
        &self,
        conn: iroh::endpoint::Connection,
    ) -> impl std::future::Future<Output = Result<(), iroh::protocol::AcceptError>> + Send {
        let state = self.state.clone();
        let auth = self.auth.clone();
        
        async move {
            let client_id = conn.remote_node_id()?;
            
            // Check authorization
            if !auth.is_authorized(&client_id.to_string()) {
                warn!("Unauthorized client attempted connection: {}", client_id);
                return Err(iroh::protocol::AcceptError::User {
                    source: anyhow::anyhow!("Unauthorized client").into(),
                });
            }
            
            debug!("Accepted connection from {}", client_id);
            
            // Handle tunnel requests
            loop {
                match conn.accept_bi().await {
                    Ok((send, mut recv)) => {
                        // Read tunnel message
                        let mut buf = Vec::new();
                        recv.read_to_end(1024 * 1024, &mut buf).await?;
                        
                        match serde_json::from_slice::<TunnelMessage>(&buf) {
                            Ok(msg) => {
                                match msg {
                                    TunnelMessage::Register { domain, port } => {
                                        match state.register_tunnel(domain.clone(), client_id, port).await {
                                            Ok(_) => {
                                                let response = TunnelMessage::Registered { domain };
                                                let data = serde_json::to_vec(&response)?;
                                                send.write_all(&data).await?;
                                                send.finish()?;
                                            }
                                            Err(e) => {
                                                let response = TunnelMessage::Error { 
                                                    message: e.to_string() 
                                                };
                                                let data = serde_json::to_vec(&response)?;
                                                send.write_all(&data).await?;
                                                send.finish()?;
                                            }
                                        }
                                    }
                                    TunnelMessage::Unregister { domain } => {
                                        state.unregister_tunnel(&domain).await;
                                        let response = TunnelMessage::Unregistered { domain };
                                        let data = serde_json::to_vec(&response)?;
                                        send.write_all(&data).await?;
                                        send.finish()?;
                                    }
                                    TunnelMessage::List => {
                                        let tunnels = state.list_tunnels().await;
                                        let domains: Vec<String> = tunnels.iter()
                                            .filter(|t| t.client_id == client_id)
                                            .map(|t| t.domain.clone())
                                            .collect();
                                        let response = TunnelMessage::TunnelList { tunnels: domains };
                                        let data = serde_json::to_vec(&response)?;
                                        send.write_all(&data).await?;
                                        send.finish()?;
                                    }
                                    _ => {
                                        warn!("Unexpected message from client");
                                    }
                                }
                            }
                            Err(e) => {
                                error!("Failed to parse tunnel message: {}", e);
                            }
                        }
                    }
                    Err(e) => {
                        debug!("Connection closed: {}", e);
                        break;
                    }
                }
            }
            
            Ok(())
        }
    }
}

async fn handle_admin_request(
    state: Arc<ServerState>,
    req: Request<hyper::body::Incoming>,
) -> Result<Response<BoxBody>> {
    let response = match (req.method(), req.uri().path()) {
        (&Method::GET, "/health") => {
            Response::builder()
                .status(StatusCode::OK)
                .body(full_body("OK"))
                .unwrap()
        }
        
        (&Method::GET, "/tunnels") => {
            let tunnels = state.list_tunnels().await;
            let json = serde_json::to_string(&tunnels)?;
            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "application/json")
                .body(full_body(json))
                .unwrap()
        }
        
        _ => {
            Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(full_body("Not Found"))
                .unwrap()
        }
    };
    
    Ok(response)
}

fn full_body(data: impl Into<Bytes>) -> BoxBody {
    Full::new(data.into())
        .map_err(|never| match never {})
        .boxed()
}