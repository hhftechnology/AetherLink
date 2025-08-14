use anyhow::{Context, Result};
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::client::conn::http1;
use hyper::server::conn::http1 as server_http1;
use hyper::service::service_fn;
use hyper::{Request, Response, StatusCode};
use iroh_net::endpoint::Endpoint;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tracing::{debug, error, info, warn};

use crate::config::Identity;
use crate::tunnel::{TUNNEL_ALPN, TunnelMessage};

type BoxBody = http_body_util::combinators::BoxBody<Bytes, hyper::Error>;

pub async fn create_tunnel(
    identity: Identity,
    server_id: String,
    domain: String,
    local_port: u16,
    bind_addr: SocketAddr,
) -> Result<()> {
    use iroh_base::key::NodeId;
    use std::str::FromStr;
    
    // Parse server node ID
    let server_node_id = NodeId::from_str(&server_id)
        .context("Invalid server node ID")?;
    
    // Start Iroh endpoint
    let endpoint = Endpoint::builder()
        .secret_key(identity.secret_key.clone())
        .alpns(vec![TUNNEL_ALPN.to_vec()])
        .bind(0)
        .await?;
    
    info!("Connecting to server: {}", server_id);
    
    // Connect to server  
    use iroh_net::NodeAddr;
    let node_addr = NodeAddr::new(server_node_id);
    let conn = endpoint.connect(node_addr, &TUNNEL_ALPN).await
        .context("Failed to connect to server")?;
    
    // Register tunnel
    let (mut send, mut recv) = conn.open_bi().await?;
    let msg = TunnelMessage::Register {
        domain: domain.clone(),
        port: local_port,
    };
    let data = serde_json::to_vec(&msg)?;
    send.write_all(&data).await?;
    send.finish()?;
    
    // Read response
    let mut buf = Vec::new();
    recv.read_to_end(1024 * 1024, &mut buf).await?;
    
    match serde_json::from_slice::<TunnelMessage>(&buf)? {
        TunnelMessage::Registered { domain: registered_domain } => {
            info!("✓ Tunnel registered: {}", registered_domain);
        }
        TunnelMessage::Error { message } => {
            return Err(anyhow::anyhow!("Failed to register tunnel: {}", message));
        }
        _ => {
            return Err(anyhow::anyhow!("Unexpected response from server"));
        }
    }
    
    // Set up local HTTP proxy
    let listener = TcpListener::bind(bind_addr).await?;
    let local_addr = listener.local_addr()?;
    
    info!("HTTP proxy listening on http://{}", local_addr);
    info!("Tunnel active: {} → localhost:{}", domain, local_port);
    info!("Press Ctrl+C to stop the tunnel");
    
    // Handle incoming HTTP requests
    let conn = Arc::new(conn);
    
    loop {
        tokio::select! {
            accept_result = listener.accept() => {
                match accept_result {
                    Ok((stream, peer_addr)) => {
                        debug!("Accepted connection from {}", peer_addr);
                        let conn = conn.clone();
                        let domain = domain.clone();
                        
                        tokio::spawn(async move {
                            if let Err(e) = handle_client_request(
                                stream, 
                                conn, 
                                domain, 
                                local_port
                            ).await {
                                error!("Failed to handle request: {}", e);
                            }
                        });
                    }
                    Err(e) => {
                        error!("Failed to accept connection: {}", e);
                    }
                }
            }
            
            _ = tokio::signal::ctrl_c() => {
                info!("Shutting down tunnel...");
                
                // Unregister tunnel
                if let Ok((mut send, _recv)) = conn.open_bi().await {
                    let msg = TunnelMessage::Unregister {
                        domain: domain.clone(),
                    };
                    if let Ok(data) = serde_json::to_vec(&msg) {
                        let _ = send.write_all(&data).await;
                        let _ = send.finish();
                    }
                }
                
                break;
            }
        }
    }
    
    Ok(())
}

async fn handle_client_request(
    stream: TcpStream,
    _conn: Arc<iroh_net::endpoint::Connection>,
    domain: String,
    local_port: u16,
) -> Result<()> {
    let service = service_fn(move |mut req: Request<hyper::body::Incoming>| {
        let domain = domain.clone();
        async move {
            // Add host header if missing
            if !req.headers().contains_key("host") {
                req.headers_mut().insert(
                    "host",
                    domain.parse().unwrap(),
                );
            }
            
            // Forward request to local service
            forward_to_local(req, local_port).await
        }
    });
    
    server_http1::Builder::new()
        .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
        .await?;
    
    Ok(())
}

async fn forward_to_local(
    req: Request<hyper::body::Incoming>,
    port: u16,
) -> Result<Response<BoxBody>> {
    // Connect to local service
    let stream = match TcpStream::connect(format!("127.0.0.1:{}", port)).await {
        Ok(s) => s,
        Err(e) => {
            warn!("Failed to connect to local service on port {}: {}", port, e);
            return Ok(Response::builder()
                .status(StatusCode::BAD_GATEWAY)
                .body(full_body("Local service unavailable"))
                .unwrap());
        }
    };
    
    let io = hyper_util::rt::TokioIo::new(stream);
    let (mut sender, conn) = http1::handshake(io).await?;
    
    tokio::spawn(async move {
        if let Err(e) = conn.await {
            error!("Connection error: {}", e);
        }
    });
    
    // Forward the request
    let (parts, body) = req.into_parts();
    let body_bytes = body.collect().await?.to_bytes();
    
    let mut new_req = Request::builder()
        .method(parts.method)
        .uri(parts.uri);
    
    for (key, value) in parts.headers {
        if let Some(key) = key {
            new_req = new_req.header(key, value);
        }
    }
    
    let new_req = new_req.body(Full::new(body_bytes))?;
    
    match sender.send_request(new_req).await {
        Ok(response) => {
            let (parts, body) = response.into_parts();
            let body_bytes = body.collect().await?.to_bytes();
            
            let mut new_response = Response::builder()
                .status(parts.status);
            
            for (key, value) in parts.headers {
                new_response = new_response.header(key, value);
            }
            
            Ok(new_response.body(full_body(body_bytes)).unwrap())
        }
        Err(e) => {
            error!("Failed to forward request: {}", e);
            Ok(Response::builder()
                .status(StatusCode::BAD_GATEWAY)
                .body(full_body("Failed to forward request"))
                .unwrap())
        }
    }
}

pub async fn list_tunnels(
    identity: Identity,
    server_id: String,
) -> Result<()> {
    use iroh_base::key::NodeId;
    use std::str::FromStr;
    
    // Parse server node ID
    let server_node_id = NodeId::from_str(&server_id)
        .context("Invalid server node ID")?;
    
    // Start Iroh endpoint
    let endpoint = Endpoint::builder()
        .secret_key(identity.secret_key.clone())
        .alpns(vec![TUNNEL_ALPN.to_vec()])
        .bind(0)
        .await?;
    
    // Connect to server
    use iroh_net::NodeAddr;
    let node_addr = NodeAddr::new(server_node_id);
    let conn = endpoint.connect(node_addr, &TUNNEL_ALPN).await
        .context("Failed to connect to server")?;
    
    // Request tunnel list
    let (mut send, mut recv) = conn.open_bi().await?;
    let msg = TunnelMessage::List;
    let data = serde_json::to_vec(&msg)?;
    send.write_all(&data).await?;
    send.finish()?;
    
    // Read response
    let mut buf = Vec::new();
    recv.read_to_end(1024 * 1024, &mut buf).await?;
    
    match serde_json::from_slice::<TunnelMessage>(&buf)? {
        TunnelMessage::TunnelList { tunnels } => {
            if tunnels.is_empty() {
                info!("No active tunnels");
            } else {
                info!("Active tunnels:");
                for tunnel in tunnels {
                    info!("  - {}", tunnel);
                }
            }
        }
        _ => {
            return Err(anyhow::anyhow!("Unexpected response from server"));
        }
    }
    
    Ok(())
}

fn full_body(data: impl Into<Bytes>) -> BoxBody {
    Full::new(data.into())
        .map_err(|never| match never {})
        .boxed()
}