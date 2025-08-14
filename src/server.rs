use anyhow::Result;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use iroh_net::endpoint::{Endpoint, Connection};
use iroh_base::key::NodeId;
use std::collections::HashMap;
use std::net::SocketAddr;
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
        .alpns(vec![TUNNEL_ALPN.to_vec()])
        .bind(0)
        .await?;
    
    info!("Server listening on Iroh network");
    info!("Node ID: {}", identity.node_id());
    
    // Handle incoming connections
    let accept_state = state.clone();
    let accept_auth = auth.clone();
    let accept_endpoint = endpoint.clone();
    tokio::spawn(async move {
        loop {
            match accept_endpoint.accept().await {
                Some(incoming) => {
                    let state = accept_state.clone();
                    let auth = accept_auth.clone();
                    tokio::spawn(async move {
                        if let Ok(conn) = incoming.accept().await {
                            handle_connection(conn, state, auth).await;
                        }
                    });
                }
                None => break,
            }
        }
    });
    
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
    
    Ok(())
}

async fn handle_connection(
    conn: Connection,
    state: Arc<ServerState>,
    auth: Arc<Auth>,
) {
    let client_id = conn.remote_node_id();
    
    // Check authorization
    if !auth.is_authorized(&client_id.to_string()) {
        warn!("Unauthorized client attempted connection: {}", client_id);
        return;
    }
    
    debug!("Accepted connection from {}", client_id);
    
    // Handle tunnel requests
    loop {
        match conn.accept_bi().await {
            Ok((mut send, mut recv)) => {
                // Read tunnel message
                let mut buf = Vec::new();
                if recv.read_to_end(1024 * 1024, &mut buf).await.is_err() {
                    break;
                }
                
                match serde_json::from_slice::<TunnelMessage>(&buf) {
                    Ok(msg) => match msg {
                        TunnelMessage::Register { domain, port } => {
                            match state.register_tunnel(domain.clone(), client_id, port).await {
                                Ok(_) => {
                                    let response = TunnelMessage::Registered { domain };
                                    if let Ok(data) = serde_json::to_vec(&response) {
                                        let _ = send.write_all(&data).await;
                                        let _ = send.finish();
                                    }
                                }
                                Err(e) => {
                                    let response = TunnelMessage::Error { 
                                        message: e.to_string() 
                                    };
                                    if let Ok(data) = serde_json::to_vec(&response) {
                                        let _ = send.write_all(&data).await;
                                        let _ = send.finish();
                                    }
                                }
                            }
                        }
                        TunnelMessage::Unregister { domain } => {
                            state.unregister_tunnel(&domain).await;
                            let response = TunnelMessage::Unregistered { domain };
                            if let Ok(data) = serde_json::to_vec(&response) {
                                let _ = send.write_all(&data).await;
                                let _ = send.finish();
                            }
                        }
                        TunnelMessage::List => {
                            let tunnels = state.list_tunnels().await;
                            let domains: Vec<String> = tunnels.iter()
                                .filter(|t| t.client_id == client_id)
                                .map(|t| t.domain.clone())
                                .collect();
                            let response = TunnelMessage::TunnelList { tunnels: domains };
                            if let Ok(data) = serde_json::to_vec(&response) {
                                let _ = send.write_all(&data).await;
                                let _ = send.finish();
                            }
                        }
                        _ => {
                            warn!("Unexpected message from client");
                        }
                    },
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